import {
    BadRequestException,
    ConflictException,
    Injectable,
    Logger,
    NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';

import {
    Order,
    OrderDocument,
    OrderStatus,
    OrderType,
    PaymentMethod,
    PaymentStatus,
} from '../schemas/order.schema';

import {
    Merchant,
    MerchantDocument,
} from 'src/modules/merchants/schemas/merchant.schema';

import { DriverProfilesService } from 'src/modules/drivers/services/driver-profiles.service';
import { NotificationsService } from 'src/modules/notifications/services/notifications.service';
import {
    DispatchOfferLifecycleHandler,
    DispatchOfferService,
} from 'src/modules/realtime/services/dispatch-offer.service';
import { RealtimeGateway } from 'src/modules/realtime/realtime.gateway';
import { RealtimeEvents } from 'src/modules/realtime/realtime.events';
import { DeliveryRouteResolverService } from 'src/modules/geo/services/delivery-route-resolver.service';
import { SettlementService } from './settlement.service';
import {
    Table,
    TableDocument,
    TableSession,
    TableSessionDocument,
    TableSessionStatus,
    TableStatus,
} from 'src/modules/dinein/schemas';

@Injectable()
export class OrderLifecycleService implements DispatchOfferLifecycleHandler {
    private readonly DRIVER_OFFER_TTL_MS = 20_000;
    private readonly DRIVER_SEARCH_RADIUS_METERS = 5000;
    private readonly DRIVER_SEARCH_LIMIT = 20;
    private readonly DRIVER_OFFER_BATCH_SIZE = 5;
    private readonly DRIVER_LOCATION_FRESH_MS = 3 * 60 * 1000;
    private readonly MAX_DISPATCH_WAVES = 3;
    private readonly logger = new Logger(OrderLifecycleService.name);
    constructor(
        @InjectModel(Order.name)
        private readonly orderModel: Model<OrderDocument>,
        @InjectModel(Merchant.name)
        private readonly merchantModel: Model<MerchantDocument>,
        @InjectModel(Table.name)
        private readonly tableModel: Model<TableDocument>,
        @InjectModel(TableSession.name)
        private readonly tableSessionModel: Model<TableSessionDocument>,
        private readonly driverProfilesService: DriverProfilesService,
        private readonly notificationsService: NotificationsService,
        private readonly dispatchOfferService: DispatchOfferService,
        private readonly realtimeGateway: RealtimeGateway,
        private readonly deliveryRouteResolver: DeliveryRouteResolverService,
        private readonly settlementService: SettlementService,
    ) {
        this.dispatchOfferService.attachLifecycleHandler(this);
    }

    private oid(id: string, name = 'id') {
        if (!Types.ObjectId.isValid(id)) {
            throw new BadRequestException(`Invalid ${name}`);
        }
        return new Types.ObjectId(id);
    }
    private async emitOrderStatus(params: {
        order: any;
        status: string;
        message: string;
        etaMin?: number | null;
        etaAt?: string | null;
    }) {
        const orderId = String(params.order._id);
        const orderNumber = params.order?.order_number ?? null;
        const orderType = params.order?.order_type ?? null;
        const tableSessionId = params.order?.table_session_id
            ? String(params.order.table_session_id)
            : null;
        const merchantId = String(params.order.merchant_id);
        const customerUserId = params.order?.customer_id
            ? String(params.order.customer_id)
            : null;
        const driverId = params.order.driver_id ? String(params.order.driver_id) : null;
        const nowIso = new Date().toISOString();

        const customerPayload = {
            orderId,
            status: params.status,
            orderType,
            tableSessionId,
            merchantId,
            driverId,
            etaMin: params.etaMin ?? null,
            etaAt: params.etaAt ?? null,
            message: params.message,
            updatedAt: nowIso,
        };

        if (customerUserId) {
            this.realtimeGateway.emitToCustomer(
                customerUserId,
                'customer:order:status',
                customerPayload,
            );
        } else if (orderType === OrderType.DINE_IN && tableSessionId) {
            this.realtimeGateway.emitToDineInSession(
                tableSessionId,
                'customer:order:status',
                customerPayload,
            );
        }

        this.realtimeGateway.emitToMerchant(
            merchantId,
            'merchant:order:status',
            {
                orderId,
                status: params.status,
                orderType,
                tableSessionId,
                merchantId,
                driverId,
                message: params.message,
                updatedAt: nowIso,
            },
        );

        if (driverId) {
            this.realtimeGateway.emitToDriver(
                driverId,
                'driver:order:status',
                {
                    orderId,
                    status: params.status,
                    message: params.message,
                    updatedAt: nowIso,
                },
            );
        }

        this.realtimeGateway.emitToOrder(orderId, 'order:status:changed', {
            orderId,
            orderNumber,
            orderType,
            status: params.status,
            driverId,
            message: params.message,
            etaMin: params.etaMin ?? null,
            etaAt: params.etaAt ?? null,
            updatedAt: nowIso,
        });

        this.realtimeGateway.emitToAdmins('admin:order:status', {
            orderId,
            orderNumber,
            orderType,
            status: params.status,
            merchantId,
            customerUserId,
            driverId,
            message: params.message,
            etaMin: params.etaMin ?? null,
            etaAt: params.etaAt ?? null,
            updatedAt: nowIso,
        });
    }
    private async setOrderStatus(params: {
        order: any;
        status: OrderStatus;
        changedBy?: string | null;
        note?: string | null;
        message: string;
        etaMin?: number | null;
        etaAt?: string | null;
    }) {
        params.order.status = params.status;

        if (params.etaAt) {
            params.order.estimated_delivery_time = new Date(params.etaAt);
        }

        params.order.status_history.push(
            this.buildHistory({
                status: params.status,
                changedBy: params.changedBy,
                note: params.note ?? params.message,
            }) as any,
        );

        await params.order.save();

        await this.emitOrderStatus({
            order: params.order,
            status: params.status,
            message: params.message,
            etaMin: params.etaMin ?? null,
            etaAt: params.etaAt ?? null,
        });

        if (params.order?.customer_id) {
            await this.notificationsService.notifyCustomerOrderStatus({
                userId: String(params.order.customer_id),
                orderId: String(params.order._id),
                orderNumber: params.order.order_number,
                imageUrl: this.getOrderPreviewImage(params.order) ?? undefined,
                status: params.status,
                body: params.message,
                orderType: params.order.order_type,
            });
        }
    }
    private buildHistory(params: {
        status: string;
        changedBy?: string | null;
        note?: string | null;
    }) {
        return {
            status: params.status,
            changed_at: new Date(),
            changed_by:
                params.changedBy && Types.ObjectId.isValid(params.changedBy)
                    ? new Types.ObjectId(params.changedBy)
                    : null,
            note: params.note ?? null,
        };
    }

    private canStartDispatch(order: OrderDocument) {
        if (order.order_type !== OrderType.DELIVERY) return false;
        if (order.status === OrderStatus.CANCELLED) return false;
        if (order.status === OrderStatus.COMPLETED) return false;
        if (order.driver_id) return false;

        if (order.payment_method === PaymentMethod.CASH) {
            return true;
        }

        return order.payment_status === PaymentStatus.PAID;
    }
    private getOrderPreviewImage(order: any): string | null {
        const items = Array.isArray(order?.items) ? order.items : [];

        for (const item of items) {
            const image = item?.product_image;
            if (typeof image === 'string' && image.trim().length > 0) {
                return image.trim();
            }
        }

        return null;
    }

    private async finalizeTableAfterDineInCompletion(order: any) {
        const tableSessionId = order?.table_session_id
            ? String(order.table_session_id)
            : null;
        if (!tableSessionId) return;

        const session = await this.tableSessionModel.findById(
            this.oid(tableSessionId, 'tableSessionId'),
        );
        if (!session) return;

        const pendingOrdersInSession = await this.orderModel.countDocuments({
            table_session_id: session._id,
            _id: { $ne: order._id },
            status: { $nin: [OrderStatus.CANCELLED, OrderStatus.COMPLETED] },
        });
        if (pendingOrdersInSession > 0) return;

        const now = new Date();
        if (
            ![TableSessionStatus.COMPLETED, TableSessionStatus.CANCELLED].includes(
                session.status as TableSessionStatus,
            )
        ) {
            session.status = TableSessionStatus.COMPLETED;
            session.ended_at = session.ended_at ?? now;
            if (!Number.isFinite(Number(session.total_amount ?? 0)) || Number(session.total_amount ?? 0) <= 0) {
                session.total_amount = Number(order?.total_amount ?? 0);
            }
            await session.save();
        }

        const releaseResult = await this.tableModel.updateOne(
            {
                _id: session.table_id,
                merchant_id: session.merchant_id,
                current_session_id: session._id,
            },
            {
                $set: {
                    status: TableStatus.AVAILABLE,
                    current_session_id: null,
                },
            },
        );

        let table: any = await this.tableModel.findById(session.table_id).lean();

        if (
            (releaseResult.modifiedCount ?? 0) === 0 &&
            table &&
            !table.current_session_id &&
            table.status === TableStatus.OCCUPIED
        ) {
            await this.tableModel.updateOne(
                {
                    _id: session.table_id,
                    merchant_id: session.merchant_id,
                },
                {
                    $set: {
                        status: TableStatus.AVAILABLE,
                        current_session_id: null,
                    },
                },
            );
            table = await this.tableModel.findById(session.table_id).lean();
        }

        const payload = {
            action: 'closed',
            reason: 'payment_completed',
            orderId: String(order._id),
            merchantId: String(order.merchant_id),
            tableId: String(session.table_id),
            tableSessionId: String(session._id),
            tableStatus: table?.status ?? TableStatus.AVAILABLE,
            updatedAt: now.toISOString(),
        };

        this.realtimeGateway.emitToDineInSession(
            String(session._id),
            RealtimeEvents.CUSTOMER_DINEIN_SESSION,
            payload,
        );

        if (order?.customer_id) {
            this.realtimeGateway.emitToCustomer(
                String(order.customer_id),
                RealtimeEvents.CUSTOMER_DINEIN_SESSION,
                payload,
            );
        }

        this.realtimeGateway.emitToMerchant(
            String(order.merchant_id),
            RealtimeEvents.MERCHANT_TABLE_STATUS,
            {
                merchantId: String(order.merchant_id),
                tableId: String(session.table_id),
                tableNumber: table?.table_number ?? null,
                status: table?.status ?? TableStatus.AVAILABLE,
                currentSessionId: null,
                reason: 'payment_completed',
                updatedAt: now.toISOString(),
            },
        );
    }
    private async getBusyDriverIds() {
        const rawIds = await this.orderModel.distinct('driver_id', {
            order_type: OrderType.DELIVERY,
            driver_id: { $ne: null },
            status: {
                $nin: [OrderStatus.CANCELLED, OrderStatus.COMPLETED],
            },
        });

        return new Set(
            rawIds
                .filter(Boolean)
                .map((x: any) => String(x)),
        );
    }

    /**
     * Phase 3:
     * kích hoạt order delivery sau khi hợp lệ:
     * - notify merchant
     * - start dispatch
     */
    async activateDeliveryOrder(orderId: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) {
            throw new NotFoundException('Order not found');
        }

        if (order.order_type !== OrderType.DELIVERY) {
            return {
                ok: false,
                reason: 'not_delivery_order',
            };
        }

        if (!this.canStartDispatch(order)) {
            return {
                ok: false,
                reason: 'order_not_dispatchable',
            };
        }

        const merchant: any = await this.merchantModel
            .findById(order.merchant_id)
            .select('_id name address owner_user_id')
            .lean();

        if (!merchant) {
            throw new NotFoundException('Merchant not found');
        }

        const merchantUserId =
            merchant?.owner_user_id != null ? String(merchant.owner_user_id) : null;

        if (merchantUserId) {
            await this.notificationsService.notifyMerchantNewOrder({
                userId: merchantUserId,
                orderId: String(order._id),
                orderNumber: order.order_number,
                imageUrl: this.getOrderPreviewImage(order) ?? undefined,
                orderType: order.order_type,
            });
        }

        const itemCount = (order.items ?? []).reduce(
            (sum: number, it: any) => sum + Number(it.quantity ?? 0),
            0,
        );

        const nowIso = new Date().toISOString();

        const shouldAutoConfirm = order.status === OrderStatus.PENDING;
        if (shouldAutoConfirm) {
            order.status = OrderStatus.CONFIRMED;
            order.status_history.push(
                this.buildHistory({
                    status: OrderStatus.CONFIRMED,
                    note: 'Delivery order auto-confirmed by system',
                }) as any,
            );
        }

        this.realtimeGateway.emitToMerchant(
            String(order.merchant_id),
            'merchant:order:new',
            {
                orderId: String(order._id),
                orderNumber: order.order_number,
                orderType: order.order_type,
                status: order.status,
                paymentMethod: order.payment_method,
                totalAmount: Number(order.total_amount ?? 0),
                itemCount,
                customerName: order.delivery_address?.receiver_name ?? null,
                customerPhone: order.delivery_address?.receiver_phone ?? null,
                customerAddress: order.delivery_address?.address ?? null,
                orderNote: order.order_note ?? null,
                createdAt: nowIso,
                message: 'Có đơn giao hàng mới, hệ thống đang tìm tài xế',
            },
        );

        this.realtimeGateway.emitToAdmins('admin:order:new', {
            orderId: String(order._id),
            orderNumber: order.order_number,
            orderType: order.order_type,
            status: order.status,
            merchantId: String(order.merchant_id),
            customerUserId: String(order.customer_id),
            driverId: order.driver_id ? String(order.driver_id) : null,
            paymentMethod: order.payment_method,
            totalAmount: Number(order.total_amount ?? 0),
            itemCount,
            createdAt: nowIso,
            message: 'Có đơn mới vừa tạo',
        });

        order.status_history.push(
            this.buildHistory({
                status: 'merchant_notified',
                note: 'Merchant has been notified about the new delivery order',
            }) as any,
        );
        await order.save();

        let dispatch: any = null;
        try {
            dispatch = await this.startDispatchForOrder(String(order._id), {
                wave: 1,
            });
        } catch (e: any) {
            this.logger.error(
                `[activateDeliveryOrder] dispatch failed for order=${String(order._id)}: ${e?.message ?? e}`,
            );

            const failedAt = new Date().toISOString();
            order.driver_accept_deadline_at = null;
            order.status_history.push(
                this.buildHistory({
                    status: 'dispatch_expired',
                    note: e?.message ?? 'Dispatch failed after order activation',
                }) as any,
            );
            await order.save();

            this.realtimeGateway.emitToCustomer(
                String(order.customer_id),
                'customer:dispatch:expired',
                {
                    orderId: String(order._id),
                    status: 'dispatch_expired',
                    reason: 'dispatch_failed',
                    message: 'Hiện chưa tìm được tài xế phù hợp cho đơn của bạn',
                    updatedAt: failedAt,
                },
            );

            this.realtimeGateway.emitToMerchant(
                String(order.merchant_id),
                'merchant:dispatch:expired',
                {
                    orderId: String(order._id),
                    status: 'dispatch_expired',
                    reason: 'dispatch_failed',
                    message: 'Đơn hiện chưa tìm được tài xế phù hợp',
                    updatedAt: failedAt,
                },
            );

            dispatch = {
                ok: false,
                reason: 'dispatch_failed',
                message: e?.message ?? 'Dispatch failed',
            };
        }

        return {
            ok: true,
            orderId: String(order._id),
            merchantNotified: Boolean(merchantUserId),
            dispatch,
        };
    }

    async activateDineInOrder(orderId: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) {
            throw new NotFoundException('Order not found');
        }

        if (order.order_type !== OrderType.DINE_IN) {
            return {
                ok: false,
                reason: 'not_dine_in_order',
            };
        }

        if (order.status === OrderStatus.CANCELLED) {
            return {
                ok: false,
                reason: 'order_cancelled',
            };
        }

        if (order.status === OrderStatus.COMPLETED) {
            return {
                ok: false,
                reason: 'order_completed',
            };
        }

        if (
            order.payment_method !== PaymentMethod.CASH &&
            order.payment_status !== PaymentStatus.PAID
        ) {
            return {
                ok: false,
                reason: 'order_not_paid',
            };
        }

        const history = Array.isArray(order.status_history) ? order.status_history : [];
        const hasMerchantNotified = history.some(
            (x: any) => String(x?.status ?? '') === 'merchant_notified',
        );
        if (hasMerchantNotified) {
            return {
                ok: true,
                reason: 'already_notified',
            };
        }

        const merchant: any = await this.merchantModel
            .findById(order.merchant_id)
            .select('_id name address owner_user_id')
            .lean();

        if (!merchant) {
            throw new NotFoundException('Merchant not found');
        }

        const merchantUserId =
            merchant?.owner_user_id != null ? String(merchant.owner_user_id) : null;

        if (merchantUserId) {
            await this.notificationsService.notifyMerchantNewOrder({
                userId: merchantUserId,
                orderId: String(order._id),
                orderNumber: order.order_number,
                imageUrl: this.getOrderPreviewImage(order) ?? undefined,
                orderType: order.order_type,
            });
        }

        const itemCount = (order.items ?? []).reduce(
            (sum: number, it: any) => sum + Number(it.quantity ?? 0),
            0,
        );

        const nowIso = new Date().toISOString();

        this.realtimeGateway.emitToMerchant(
            String(order.merchant_id),
            'merchant:order:new',
            {
                orderId: String(order._id),
                orderNumber: order.order_number,
                orderType: order.order_type,
                tableSessionId: order.table_session_id
                    ? String(order.table_session_id)
                    : null,
                status: OrderStatus.PENDING,
                paymentMethod: order.payment_method,
                totalAmount: Number(order.total_amount ?? 0),
                itemCount,
                orderNote: order.order_note ?? null,
                createdAt: nowIso,
                message: 'Có đơn tại quán mới chờ xác nhận',
            },
        );

        this.realtimeGateway.emitToAdmins('admin:order:new', {
            orderId: String(order._id),
            orderNumber: order.order_number,
            orderType: order.order_type,
            tableSessionId: order.table_session_id
                ? String(order.table_session_id)
                : null,
            status: order.status,
            merchantId: String(order.merchant_id),
            customerUserId: order.customer_id ? String(order.customer_id) : null,
            driverId: null,
            paymentMethod: order.payment_method,
            totalAmount: Number(order.total_amount ?? 0),
            itemCount,
            createdAt: nowIso,
            message: 'Có đơn tại quán mới vừa tạo',
        });

        order.status_history.push(
            this.buildHistory({
                status: 'merchant_notified',
                note: 'Merchant has been notified about the new dine-in order',
            }) as any,
        );
        await order.save();

        return {
            ok: true,
            orderId: String(order._id),
            merchantNotified: Boolean(merchantUserId),
        };
    }
    async startDispatchForOrder(
        orderId: string,
        opts?: {
            excludedDriverIds?: string[];
            wave?: number;
        },
    ) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        if (!this.canStartDispatch(order)) {
            return { ok: false, reason: 'order_not_dispatchable' };
        }

        const merchant: any = await this.merchantModel
            .findById(order.merchant_id)
            .select('_id name address location')
            .lean();

        if (!merchant) throw new NotFoundException('Merchant not found');

        const merchantCoords = merchant?.location?.coordinates;
        if (!Array.isArray(merchantCoords) || merchantCoords.length !== 2) {
            throw new BadRequestException('Merchant location is missing');
        }

        const merchantLat = Number(merchantCoords[1]);
        const merchantLng = Number(merchantCoords[0]);

        const nearbyDrivers =
            await this.driverProfilesService.findNearbyAvailableApproved({
                lat: merchantLat,
                lng: merchantLng,
                radiusMeters: this.DRIVER_SEARCH_RADIUS_METERS,
                limit: this.DRIVER_SEARCH_LIMIT,
            });

        const busyDriverIds = await this.getBusyDriverIds();
        const now = Date.now();
        const excluded = new Set((opts?.excludedDriverIds ?? []).map(String));

        const eligibleDriverIds = nearbyDrivers
            .filter((x: any) => {
                const driverUserId = String(x.user_id);
                if (busyDriverIds.has(driverUserId)) return false;
                if (excluded.has(driverUserId)) return false;

                const lastUpdate = x.last_location_update
                    ? new Date(x.last_location_update).getTime()
                    : 0;

                if (!lastUpdate) return false;
                return now - lastUpdate <= this.DRIVER_LOCATION_FRESH_MS;
            })
            .map((x: any) => String(x.user_id));

        const candidateDriverIds = eligibleDriverIds.slice(0, this.DRIVER_OFFER_BATCH_SIZE);
        const wave = Number(opts?.wave ?? 1);

        this.logger.log(
            `[dispatch] order=${orderId} wave=${wave} nearby=${nearbyDrivers.length} eligible=${eligibleDriverIds.length} candidate=${candidateDriverIds.length}`,
        );

        this.logger.log(
            `[dispatch] candidateDriverIds=${candidateDriverIds.join(',') || '[]'}`,
        );

        this.logger.log(
            `[dispatch] merchantLat=${merchantLat}, merchantLng=${merchantLng}`,
        );

        if (!candidateDriverIds.length) {
            const nowIso = new Date().toISOString();

            this.realtimeGateway.emitToCustomer(
                String(order.customer_id),
                'customer:dispatch:expired',
                {
                    orderId: String(order._id),
                    status: 'dispatch_expired',
                    reason: 'no_candidate_drivers',
                    message: 'Hiện chưa tìm được tài xế phù hợp cho đơn của bạn',
                    updatedAt: nowIso,
                },
            );

            this.realtimeGateway.emitToMerchant(
                String(order.merchant_id),
                'merchant:dispatch:expired',
                {
                    orderId: String(order._id),
                    status: 'dispatch_expired',
                    reason: 'no_candidate_drivers',
                    message: 'Đơn hiện chưa tìm được tài xế phù hợp',
                    updatedAt: nowIso,
                },
            );
            order.driver_accept_deadline_at = null;
            order.status_history.push(
                this.buildHistory({
                    status: 'dispatch_expired',
                    note: `No candidate drivers available at wave ${wave}`,
                }) as any,
            );
            await order.save();

            return { ok: false, reason: 'no_candidate_drivers', wave };
        }

        const offerExpiresAt = new Date(Date.now() + this.DRIVER_OFFER_TTL_MS);

        const itemCount = (order.items ?? []).reduce(
            (sum: number, it: any) => sum + Number(it.quantity ?? 0),
            0,
        );

        const customerCoords = order.delivery_address?.location?.coordinates ?? [];
        const customerLng =
            Array.isArray(customerCoords) && customerCoords.length === 2
                ? Number(customerCoords[0])
                : null;
        const customerLat =
            Array.isArray(customerCoords) && customerCoords.length === 2
                ? Number(customerCoords[1])
                : null;

        order.driver_accept_deadline_at = offerExpiresAt;
        order.assignment_attempts = Number(order.assignment_attempts ?? 0) + 1;
        order.status_history.push(
            this.buildHistory({
                status: 'dispatch_searching',
                note: `Dispatch wave ${wave}. Candidates: ${candidateDriverIds.length}`,
            }) as any,
        );
        await order.save();

        this.dispatchOfferService.startOffer({
            orderId: String(order._id),
            customerUserId: String(order.customer_id),
            merchantId: String(order.merchant_id),
            candidateDriverIds,
            payload: {
                wave,
                triedDriverIds: [...excluded, ...candidateDriverIds],
                orderNumber: order.order_number,
                merchantId: String(order.merchant_id),
                merchantName: merchant.name ?? null,
                merchantAddress: merchant.address ?? null,
                merchantLat,
                merchantLng,

                customerName: order.delivery_address?.receiver_name ?? null,
                customerPhone: order.delivery_address?.receiver_phone ?? null,
                customerAddress: order.delivery_address?.address ?? null,
                customerLat,
                customerLng,

                orderNote: order.order_note ?? null,
                itemCount,
                totalAmount: Number(order.total_amount ?? 0),
                deliveryFee: Number(order.delivery_fee ?? 0),
                paymentMethod: order.payment_method,
            },
        });
        return {
            ok: true,
            orderId: String(order._id),
            candidateCount: candidateDriverIds.length,
            offerExpiresAt: offerExpiresAt.toISOString(),
            wave,
        };
    }

    async onDriverAcceptedOffer(params: {
        orderId: string;
        driverId: string;
        offer?: any;
    }) {
        const order = await this.orderModel.findById(this.oid(params.orderId, 'orderId'));
        if (!order) {
            throw new NotFoundException('Order not found');
        }

        if (order.order_type !== OrderType.DELIVERY) {
            throw new BadRequestException('Order is not a delivery order');
        }

        if (order.status === OrderStatus.CANCELLED) {
            throw new BadRequestException('Order already cancelled');
        }

        if (order.status === OrderStatus.COMPLETED) {
            throw new BadRequestException('Order already completed');
        }

        if (order.driver_id && String(order.driver_id) !== params.driverId) {
            throw new ConflictException('Order already assigned to another driver');
        }

        order.driver_id = this.oid(params.driverId, 'driverId');
        order.status = OrderStatus.DRIVER_ASSIGNED;
        order.driver_assigned_at = new Date();
        order.driver_accept_deadline_at = null;

        order.status_history.push(
            this.buildHistory({
                status: OrderStatus.DRIVER_ASSIGNED,
                changedBy: params.driverId,
                note: 'Driver accepted delivery offer',
            }) as any,
        );

        await order.save();

        await this.emitOrderStatus({
            order,
            status: OrderStatus.DRIVER_ASSIGNED,
            message: 'Đã có tài xế nhận đơn',
        });
    }

    async onDispatchOfferExpired(params: {
        orderId: string;
        reason: string;
        offer?: any;
    }) {
        const order = await this.orderModel.findById(this.oid(params.orderId, 'orderId'));
        if (!order) return { willRetry: false };
        if (order.driver_id) return { willRetry: false };

        const wave = Number(params.offer?.payload?.wave ?? 1);
        const triedDriverIds = Array.isArray(params.offer?.payload?.triedDriverIds)
            ? params.offer.payload.triedDriverIds.map(String)
            : [];

        if (wave < this.MAX_DISPATCH_WAVES) {
            order.status_history.push(
                this.buildHistory({
                    status: 'dispatch_retrying',
                    note: `Retry dispatch wave ${wave + 1}`,
                }) as any,
            );
            await order.save();

            await this.startDispatchForOrder(String(order._id), {
                excludedDriverIds: triedDriverIds,
                wave: wave + 1,
            });

            return { willRetry: true };
        }

        order.driver_accept_deadline_at = null;
        order.status_history.push(
            this.buildHistory({
                status: 'dispatch_expired',
                note: `Driver dispatch expired after wave ${wave}: ${params.reason}`,
            }) as any,
        );
        await order.save();

        return { willRetry: false };
    }
    async merchantConfirmOrder(merchantUserId: string, orderId: string, note?: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        if (order.status !== OrderStatus.PENDING) {
            throw new BadRequestException('Only pending order can be confirmed');
        }

        await this.setOrderStatus({
            order,
            status: OrderStatus.CONFIRMED,
            changedBy: merchantUserId,
            note,
            message: 'Quán đã xác nhận đơn hàng',
        });

        if (order.order_type === OrderType.DELIVERY && !order.driver_id) {
            this.logger.log(
                `[merchantConfirmOrder] starting dispatch for order=${String(order._id)}`,
            );

            const dispatch = await this.startDispatchForOrder(String(order._id), {
                wave: 1,
            });
            this.logger.log(
                `[merchantConfirmOrder] dispatch result for order=${String(order._id)} => ${JSON.stringify(dispatch)}`,
            );
            return {
                order,
                dispatch,
            };
        }

        return {
            order,
            dispatch: null,
        };
    }

    async merchantRetryDispatch(orderId: string, merchantUserId: string, note?: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        const merchant = await this.merchantModel.findOne({
            _id: order.merchant_id,
            owner_user_id: this.oid(merchantUserId, 'merchantUserId'),
            deleted_at: null,
        });

        if (!merchant) {
            throw new NotFoundException('Merchant not found');
        }

        if (order.order_type !== OrderType.DELIVERY) {
            throw new BadRequestException('Only delivery order supports dispatch retry');
        }

        if (order.driver_id) {
            throw new BadRequestException('Order already has driver assigned');
        }

        if (
            ![
                OrderStatus.CONFIRMED,
                OrderStatus.PREPARING,
                OrderStatus.READY_FOR_PICKUP,
            ].includes(order.status)
        ) {
            throw new BadRequestException(
                'Order is not eligible for manual dispatch retry',
            );
        }

        const activeOffer = this.dispatchOfferService.getOffer(String(order._id));
        if (activeOffer?.status === 'pending') {
            throw new ConflictException('Dispatch is still searching driver');
        }

        const history = Array.isArray(order.status_history) ? order.status_history : [];
        let lastDispatchMarker: string | null = null;
        for (let i = history.length - 1; i >= 0; i -= 1) {
            const s = String(history[i]?.status ?? '');
            if (
                s === 'dispatch_expired' ||
                s === 'dispatch_searching' ||
                s === 'dispatch_retrying'
            ) {
                lastDispatchMarker = s;
                break;
            }
        }

        if (lastDispatchMarker !== 'dispatch_expired') {
            throw new BadRequestException('Manual dispatch is only available after dispatch expired');
        }

        order.status_history.push(
            this.buildHistory({
                status: 'dispatch_manual_retry',
                changedBy: merchantUserId,
                note: note ?? 'Merchant manually retried dispatch',
            }) as any,
        );
        await order.save();

        const dispatch = await this.startDispatchForOrder(String(order._id), {
            wave: 1,
        });

        return {
            order,
            dispatch,
        };
    }

    async merchantRejectPendingOrder(
        merchantUserId: string,
        orderId: string,
        reason?: string,
    ) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        const merchant = await this.merchantModel.findOne({
            _id: order.merchant_id,
            owner_user_id: this.oid(merchantUserId, 'merchantUserId'),
            deleted_at: null,
        });

        if (!merchant) {
            throw new NotFoundException('Merchant not found');
        }

        if (order.status !== OrderStatus.PENDING) {
            throw new BadRequestException('Only pending order can be rejected');
        }

        if (order.driver_id) {
            throw new BadRequestException('Order already has driver assigned');
        }

        order.cancelled_by = 'merchant';
        order.cancel_reason = reason ?? 'merchant_rejected';
        order.driver_accept_deadline_at = null;

        await this.setOrderStatus({
            order,
            status: OrderStatus.CANCELLED,
            changedBy: merchantUserId,
            note: reason,
            message: 'Quán đã từ chối đơn hàng',
        });

        this.dispatchOfferService.cancelOffer(String(order._id), 'merchant_rejected');

        const cancelledPayload = {
            orderId: String(order._id),
            status: 'cancelled',
            orderType: order.order_type,
            tableSessionId: order.table_session_id
                ? String(order.table_session_id)
                : null,
            cancelledBy: 'merchant',
            reason: reason ?? null,
            message: 'Quán đã từ chối đơn hàng của bạn',
            updatedAt: new Date().toISOString(),
        };

        if (order.customer_id) {
            this.realtimeGateway.emitToCustomer(
                String(order.customer_id),
                'customer:order:cancelled',
                cancelledPayload,
            );
        } else if (order.order_type === OrderType.DINE_IN && order.table_session_id) {
            this.realtimeGateway.emitToDineInSession(
                String(order.table_session_id),
                'customer:order:cancelled',
                cancelledPayload,
            );
        }

        return order;
    }
    async merchantStartPreparing(merchantUserId: string, orderId: string, note?: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        if (order.status === OrderStatus.PREPARING) {
            return order;
        }

        if (
            ![OrderStatus.CONFIRMED, OrderStatus.DRIVER_ASSIGNED].includes(
                order.status,
            )
        ) {
            throw new BadRequestException(
                'Only confirmed/driver_assigned order can move to preparing',
            );
        }

        await this.setOrderStatus({
            order,
            status: OrderStatus.PREPARING,
            changedBy: merchantUserId,
            note,
            message: 'Quán đang chuẩn bị món',
        });

        return order;
    }

    async merchantReadyForPickup(merchantUserId: string, orderId: string, note?: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        if (order.status === OrderStatus.READY_FOR_PICKUP) {
            return order;
        }

        if (![OrderStatus.PREPARING, OrderStatus.DRIVER_ARRIVED].includes(order.status)) {
            throw new BadRequestException('Only preparing/driver_arrived order can move to ready_for_pickup');
        }

        await this.setOrderStatus({
            order,
            status: OrderStatus.READY_FOR_PICKUP,
            changedBy: merchantUserId,
            note,
            message:
                order.order_type === OrderType.DINE_IN
                    ? 'Món đã sẵn sàng để phục vụ khách tại quán'
                    : 'Món đã sẵn sàng để tài xế lấy',
        });

        return order;
    }
    async driverArrivedAtMerchant(driverUserId: string, orderId: string, note?: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        if (!order.driver_id || String(order.driver_id) !== driverUserId) {
            throw new BadRequestException('Driver is not assigned to this order');
        }

        if (![OrderStatus.CONFIRMED, OrderStatus.PREPARING, OrderStatus.READY_FOR_PICKUP].includes(order.status)) {
            throw new BadRequestException('Order is not in merchant pickup flow');
        }

        if (order.driver_arrived_at) {
            throw new BadRequestException('Driver already arrived at merchant');
        }

        order.driver_arrived_at = new Date();

        order.status_history.push(
            this.buildHistory({
                status: 'driver_arrived',
                changedBy: driverUserId,
                note: note ?? 'Tài xế đã tới quán',
            }) as any,
        );

        await order.save();

        await this.emitOrderStatus({
            order,
            status: order.status, // giữ nguyên status chính
            message: 'Tài xế đã tới quán',
        });

        return order;
    }
    //ACTION CHO DRIVER
    async driverPickedUpOrder(driverUserId: string, orderId: string, note?: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        if (!order.driver_id || String(order.driver_id) !== driverUserId) {
            throw new BadRequestException('Driver is not assigned to this order');
        }

        if (order.status !== OrderStatus.READY_FOR_PICKUP) {
            throw new BadRequestException('Order is not ready to be picked up');
        }

        const customerCoords = order.delivery_address?.location?.coordinates;
        if (!Array.isArray(customerCoords) || customerCoords.length !== 2) {
            throw new BadRequestException('Customer location missing');
        }

        const merchant: any = await this.merchantModel
            .findById(order.merchant_id)
            .select('location')
            .lean();

        const route = await this.deliveryRouteResolver.resolve({
            origin: {
                lat: Number(merchant.location.coordinates[1]),
                lng: Number(merchant.location.coordinates[0]),
            },
            destination: {
                lat: Number(customerCoords[1]),
                lng: Number(customerCoords[0]),
            },
            prepMin: 0,
            radiusKm: 999,
        });

        order.driver_arrived_at = order.driver_arrived_at ?? new Date();

        await this.setOrderStatus({
            order,
            status: OrderStatus.PICKED_UP,
            changedBy: driverUserId,
            note,
            message: 'Tài xế đã lấy món',
            etaMin: route.etaMin,
            etaAt: route.etaAt,
        });

        return order;
    }

    async driverStartDelivering(driverUserId: string, orderId: string, note?: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        if (!order.driver_id || String(order.driver_id) !== driverUserId) {
            throw new BadRequestException('Driver is not assigned to this order');
        }

        if (![OrderStatus.PICKED_UP, OrderStatus.DELIVERING].includes(order.status)) {
            throw new BadRequestException('Order is not ready for delivering');
        }

        await this.setOrderStatus({
            order,
            status: OrderStatus.DELIVERING,
            changedBy: driverUserId,
            note,
            message: 'Tài xế đang giao hàng',
        });

        return order;
    }

    async driverDeliveredOrder(driverUserId: string, orderId: string, note?: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        if (!order.driver_id || String(order.driver_id) !== driverUserId) {
            throw new BadRequestException('Driver is not assigned to this order');
        }

        if (![OrderStatus.PICKED_UP, OrderStatus.DELIVERING].includes(order.status)) {
            throw new BadRequestException('Order is not in delivering state');
        }

        await this.setOrderStatus({
            order,
            status: OrderStatus.DELIVERED,
            changedBy: driverUserId,
            note,
            message: 'Đơn hàng đã được giao tới khách',
        });

        return order;
    }

    async driverCompleteOrder(
        driverUserId: string,
        orderId: string,
        dto: { proof_of_delivery_images: string[]; note?: string },
    ) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        if (!order.driver_id || String(order.driver_id) !== driverUserId) {
            throw new BadRequestException('Driver is not assigned to this order');
        }

        if (order.status !== OrderStatus.DELIVERED) {
            throw new BadRequestException('Only delivered order can be completed');
        }

        order.proof_of_delivery_images = dto.proof_of_delivery_images ?? [];
        order.settlement = await this.settlementService.buildSettlement(order);

        await this.setOrderStatus({
            order,
            status: OrderStatus.COMPLETED,
            changedBy: driverUserId,
            note: dto.note,
            message: 'Đơn hàng đã hoàn tất',
        });

        return order;
    }

    async completeDineInOrderAfterPayment(
        orderId: string,
        opts?: { changedBy?: string | null; note?: string | null },
    ) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) {
            throw new NotFoundException('Order not found');
        }

        if (order.order_type !== OrderType.DINE_IN) {
            throw new BadRequestException('Only dine-in order can be completed by payment');
        }

        if (order.status === OrderStatus.CANCELLED) {
            throw new BadRequestException('Cancelled order cannot be completed');
        }

        if (order.status === OrderStatus.COMPLETED) {
            try {
                await this.finalizeTableAfterDineInCompletion(order);
            } catch (e) {
                this.logger.error(
                    `[completeDineInOrderAfterPayment] finalize table failed for order=${String(order._id)}`,
                    e instanceof Error ? e.stack : undefined,
                );
            }
            return order;
        }

        if (order.payment_status !== PaymentStatus.PAID) {
            throw new BadRequestException('Only paid dine-in order can be completed');
        }

        order.settlement = await this.settlementService.buildSettlement(order);

        await this.setOrderStatus({
            order,
            status: OrderStatus.COMPLETED,
            changedBy: opts?.changedBy ?? null,
            note: opts?.note ?? null,
            message: 'Đơn tại quán đã hoàn tất',
        });

        try {
            await this.finalizeTableAfterDineInCompletion(order);
        } catch (e) {
            this.logger.error(
                `[completeDineInOrderAfterPayment] finalize table failed for order=${String(order._id)}`,
                e instanceof Error ? e.stack : undefined,
            );
        }

        return order;
    }

    async adminForceCancelOrder(adminUserId: string, orderId: string, reason?: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        if (order.status === OrderStatus.CANCELLED) {
            throw new BadRequestException('Order already cancelled');
        }

        if (order.status === OrderStatus.COMPLETED) {
            throw new BadRequestException('Completed order cannot be force cancelled');
        }

        order.cancelled_by = 'system';
        order.cancel_reason = reason ?? 'admin_force_cancelled';
        order.driver_accept_deadline_at = null;

        await this.setOrderStatus({
            order,
            status: OrderStatus.CANCELLED,
            changedBy: adminUserId,
            note: reason,
            message: 'Đơn hàng đã bị huỷ bởi admin',
        });

        this.dispatchOfferService.cancelOffer(String(order._id), 'admin_force_cancelled');

        const cancelledPayload = {
            orderId: String(order._id),
            status: 'cancelled',
            orderType: order.order_type,
            tableSessionId: order.table_session_id
                ? String(order.table_session_id)
                : null,
            cancelledBy: 'admin',
            reason: reason ?? null,
            message: 'Đơn hàng đã bị huỷ bởi quản trị viên',
            updatedAt: new Date().toISOString(),
        };

        if (order.customer_id) {
            this.realtimeGateway.emitToCustomer(
                String(order.customer_id),
                'customer:order:cancelled',
                cancelledPayload,
            );
        } else if (order.order_type === OrderType.DINE_IN && order.table_session_id) {
            this.realtimeGateway.emitToDineInSession(
                String(order.table_session_id),
                'customer:order:cancelled',
                cancelledPayload,
            );
        }

        const merchant: any = await this.merchantModel
            .findById(order.merchant_id)
            .select('owner_user_id')
            .lean();

        if (merchant?.owner_user_id) {
            await this.notificationsService.notifyMerchantOrderStatus({
                userId: String(merchant.owner_user_id),
                orderId: String(order._id),
                status: OrderStatus.CANCELLED,
                body: 'Đơn hàng đã bị huỷ bởi quản trị viên',
            });
        }

        return order;
    }

    //============ACTION OF CUSTOMER
    async customerCancelPendingOrder(customerUserId: string, orderId: string, reason?: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId'));
        if (!order) throw new NotFoundException('Order not found');

        if (String(order.customer_id) !== customerUserId) {
            throw new BadRequestException('Order does not belong to customer');
        }

        if (order.status !== OrderStatus.PENDING) {
            throw new BadRequestException('Only pending order can be cancelled');
        }

        if (order.driver_id) {
            throw new BadRequestException('Order already has driver assigned');
        }

        order.status = OrderStatus.CANCELLED;
        order.cancelled_by = 'customer';
        order.cancel_reason = reason ?? 'customer_cancelled';
        order.driver_accept_deadline_at = null;
        order.status_history.push(
            this.buildHistory({
                status: OrderStatus.CANCELLED,
                changedBy: customerUserId,
                note: reason ?? 'Customer cancelled order',
            }) as any,
        );
        await order.save();

        this.dispatchOfferService.cancelOffer(String(order._id), 'customer_cancelled');
        await this.emitOrderStatus({
            order,
            status: OrderStatus.CANCELLED,
            message: 'Khách đã hủy đơn hàng',
        });

        const cancelledPayload = {
            orderId: String(order._id),
            status: 'cancelled',
            orderType: order.order_type,
            tableSessionId: order.table_session_id
                ? String(order.table_session_id)
                : null,
            cancelledBy: 'customer',
            reason: reason ?? null,
            message: 'Bạn đã hủy đơn hàng',
            updatedAt: new Date().toISOString(),
        };

        if (order.customer_id) {
            this.realtimeGateway.emitToCustomer(
                String(order.customer_id),
                'customer:order:cancelled',
                cancelledPayload,
            );
        } else if (order.order_type === OrderType.DINE_IN && order.table_session_id) {
            this.realtimeGateway.emitToDineInSession(
                String(order.table_session_id),
                'customer:order:cancelled',
                cancelledPayload,
            );
        }

        const merchant: any = await this.merchantModel
            .findById(order.merchant_id)
            .select('owner_user_id')
            .lean();

        if (merchant?.owner_user_id) {
            await this.notificationsService.notifyMerchantOrderStatus({
                userId: String(merchant.owner_user_id),
                orderId: String(order._id),
                status: OrderStatus.CANCELLED,
                body: 'Khách đã hủy đơn hàng',
            });
        }

        return order;
    }
}
