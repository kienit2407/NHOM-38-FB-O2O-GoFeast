import {
    BadRequestException,
    Inject,
    forwardRef,
    Injectable,
    NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';

import { Merchant, MerchantDocument } from 'src/modules/merchants/schemas/merchant.schema';
import { Table, TableDocument, TableStatus } from '../schemas/table.schema';
import {
    TableSession,
    TableSessionDocument,
    TableSessionStatus,
} from '../schemas/table-session.schema';
import { DineInSessionTokenService } from './dinein-session-token.service';
import { RealtimeGateway } from 'src/modules/realtime/realtime.gateway';
import { RealtimeEvents } from 'src/modules/realtime/realtime.events';

@Injectable()
export class PublicDineInService {
    constructor(
        @InjectModel(Table.name)
        private readonly tableModel: Model<TableDocument>,
        @InjectModel(TableSession.name)
        private readonly tableSessionModel: Model<TableSessionDocument>,
        @InjectModel(Merchant.name)
        private readonly merchantModel: Model<MerchantDocument>,

        private readonly dineInTokenService: DineInSessionTokenService,
        @Inject(forwardRef(() => RealtimeGateway))
        private readonly realtimeGateway: RealtimeGateway,
    ) { }

    private oid(id: string, name = 'id') {
        if (!Types.ObjectId.isValid(id)) {
            throw new BadRequestException(`Invalid ${name}`);
        }
        return new Types.ObjectId(id);
    }

    private async getTableOrThrow(tableId: string) {
        const table: any = await this.tableModel
            .findOne({
                _id: this.oid(tableId, 'tableId'),
                deleted_at: null,
            })
            .lean();

        if (!table) throw new NotFoundException('Table not found');
        if (!table.is_active) {
            throw new BadRequestException('Table is inactive');
        }

        return table;
    }

    private async getMerchantOrThrow(merchantId: Types.ObjectId | string) {
        const merchant: any = await this.merchantModel
            .findOne({
                _id: typeof merchantId === 'string' ? this.oid(merchantId) : merchantId,
                deleted_at: null,
            })
            .lean();

        if (!merchant) throw new NotFoundException('Merchant not found');
        if (merchant.is_accepting_orders === false) {
            throw new BadRequestException('Merchant is not accepting orders');
        }

        return merchant;
    }

    private async findActiveSessionForTable(table: any) {
        let session: any = null;

        if (table.current_session_id) {
            session = await this.tableSessionModel
                .findOne({
                    _id: table.current_session_id,
                    table_id: table._id,
                    merchant_id: table.merchant_id,
                    status: TableSessionStatus.ACTIVE,
                })
                .lean();
        }

        if (!session) {
            session = await this.tableSessionModel
                .findOne({
                    table_id: table._id,
                    merchant_id: table.merchant_id,
                    status: TableSessionStatus.ACTIVE,
                })
                .sort({ started_at: -1, created_at: -1 })
                .lean();
        }

        return session;
    }

    private buildPayload(args: {
        merchant: any;
        table: any;
        session: any;
        token?: string | null;
    }) {
        return {
            merchant: {
                id: String(args.merchant._id),
                name: args.merchant.name,
                logo_url: args.merchant.logo_url ?? null,
                address: args.merchant.address ?? null,
            },
            table: {
                id: String(args.table._id),
                table_number: args.table.table_number,
                name: args.table.name ?? null,
                capacity: Number(args.table.capacity ?? 0),
                status: args.table.status,
                is_active: args.table.is_active === true,
            },
            table_session: {
                id: String(args.session._id),
                status: args.session.status,
                started_at: args.session.started_at,
            },
            ...(args.token ? { dine_in_token: args.token } : {}),
            mode: 'guest',
        };
    }

    private emitMerchantTableStatus(args: {
        merchantId: string;
        tableId: string;
        tableNumber: string;
        status: TableStatus;
        tableSessionId?: string | null;
        reason: string;
    }) {
        this.realtimeGateway.emitToMerchant(
            args.merchantId,
            RealtimeEvents.MERCHANT_TABLE_STATUS,
            {
                merchantId: args.merchantId,
                tableId: args.tableId,
                tableNumber: args.tableNumber,
                status: args.status,
                currentSessionId: args.tableSessionId ?? null,
                reason: args.reason,
                updatedAt: new Date().toISOString(),
            },
        );
    }

    async enterTable(args: { tableId: string; guestName?: string | null }) {
        const table: any = await this.getTableOrThrow(args.tableId);
        const merchant: any = await this.getMerchantOrThrow(table.merchant_id);

        if (
            table.status === TableStatus.RESERVED &&
            !table.current_session_id
        ) {
            throw new BadRequestException('Table is reserved');
        }

        let session = await this.findActiveSessionForTable(table);

        if (!session) {
            const created = await this.tableSessionModel.create({
                table_id: table._id,
                merchant_id: table.merchant_id,
                customer_id: null,
                guest_name: args.guestName?.trim() || null,
                status: TableSessionStatus.ACTIVE,
                started_at: new Date(),
                ended_at: null,
                total_amount: 0,
            });

            session = created.toObject();

            await this.tableModel.updateOne(
                { _id: table._id },
                {
                    $set: {
                        current_session_id: created._id,
                        status: TableStatus.OCCUPIED,
                    },
                },
            );

            table.current_session_id = created._id;
            table.status = TableStatus.OCCUPIED;
        } else {
            if (
                String(table.current_session_id ?? '') !== String(session._id)
            ) {
                await this.tableModel.updateOne(
                    { _id: table._id },
                    {
                        $set: {
                            current_session_id: session._id,
                            status: TableStatus.OCCUPIED,
                        },
                    },
                );

                table.current_session_id = session._id;
                table.status = TableStatus.OCCUPIED;
            }
        }

        const token = await this.dineInTokenService.sign({
            type: 'dine_in',
            role: 'guest',
            merchant_id: String(merchant._id),
            table_id: String(table._id),
            table_session_id: String(session._id),
        });

        this.emitMerchantTableStatus({
            merchantId: String(merchant._id),
            tableId: String(table._id),
            tableNumber: String(table.table_number ?? ''),
            status: TableStatus.OCCUPIED,
            tableSessionId: String(session._id),
            reason: 'table_entered',
        });

        return this.buildPayload({
            merchant,
            table,
            session,
            token,
        });
    }

    async getCurrentSessionFromToken(args: {
        merchantId: string;
        tableId: string;
        tableSessionId: string;
    }) {
        const table = await this.getTableOrThrow(args.tableId);
        const merchant = await this.getMerchantOrThrow(args.merchantId);

        const session: any = await this.tableSessionModel
            .findOne({
                _id: this.oid(args.tableSessionId, 'tableSessionId'),
                table_id: table._id,
                merchant_id: merchant._id,
                status: TableSessionStatus.ACTIVE,
            })
            .lean();

        if (!session) {
            throw new NotFoundException('Active table session not found');
        }

        return this.buildPayload({
            merchant,
            table,
            session,
            token: null,
        });
    }

    async leaveTable() {
        return { ok: true };
    }
}
