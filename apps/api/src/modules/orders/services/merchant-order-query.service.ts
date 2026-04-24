import {
    BadRequestException,
    Injectable,
    NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';

import { Order, OrderDocument, OrderStatus, OrderType } from '../schemas/order.schema';
import {
    Merchant,
    MerchantDocument,
} from 'src/modules/merchants/schemas/merchant.schema';
import { User, UserDocument } from 'src/modules/users/schemas/user.schema';
import { MerchantOrdersQueryDto } from '../dtos/merchant-orders.query.dto';

@Injectable()
export class MerchantOrderQueryService {
    constructor(
        @InjectModel(Order.name)
        private readonly orderModel: Model<OrderDocument>,
        @InjectModel(Merchant.name)
        private readonly merchantModel: Model<MerchantDocument>,
        @InjectModel(User.name)
        private readonly userModel: Model<UserDocument>,
    ) { }

    private oid(id: string, name = 'id') {
        if (!Types.ObjectId.isValid(id)) {
            throw new BadRequestException(`Invalid ${name}`);
        }
        return new Types.ObjectId(id);
    }

    private async getMerchantByOwnerUserId(ownerUserId: string) {
        const merchant = await this.merchantModel
            .findOne({
                owner_user_id: this.oid(ownerUserId, 'ownerUserId'),
                deleted_at: null,
            })
            .lean();

        if (!merchant) {
            throw new NotFoundException('Merchant not found');
        }

        return merchant;
    }

    private buildActions(order: any) {
        const allowManualDispatchStatuses = [
            OrderStatus.CONFIRMED,
            OrderStatus.PREPARING,
            OrderStatus.READY_FOR_PICKUP,
        ];

        const history = Array.isArray(order?.status_history) ? order.status_history : [];
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

        const canManualDispatch =
            order?.order_type === OrderType.DELIVERY &&
            !order?.driver_id &&
            allowManualDispatchStatuses.includes(order?.status) &&
            lastDispatchMarker === 'dispatch_expired';

        const canSettlePayment =
            order?.order_type === OrderType.DINE_IN &&
            ![OrderStatus.CANCELLED, OrderStatus.COMPLETED].includes(order?.status) &&
            order?.payment_status !== 'paid';

        const isDelivery = order?.order_type === OrderType.DELIVERY;
        const isDineIn = order?.order_type === OrderType.DINE_IN;

        return {
            can_confirm: isDineIn && order.status === OrderStatus.PENDING,
            can_reject: isDineIn && order.status === OrderStatus.PENDING,
            can_preparing:
                (isDineIn && order.status === OrderStatus.CONFIRMED) ||
                (isDelivery && order.status === OrderStatus.DRIVER_ASSIGNED),
            can_ready_for_pickup:
                order.status === OrderStatus.PREPARING &&
                (isDineIn || isDelivery),
            can_manual_dispatch: canManualDispatch,
            can_settle_payment: canSettlePayment,
        };
    }

    private getLastDispatchMarker(order: any): string | null {
        const history = Array.isArray(order?.status_history) ? order.status_history : [];
        for (let i = history.length - 1; i >= 0; i -= 1) {
            const status = String(history[i]?.status ?? '');
            if (
                status === 'dispatch_searching' ||
                status === 'dispatch_retrying' ||
                status === 'dispatch_expired'
            ) {
                return status;
            }
        }
        return null;
    }

    private displayStatus(order: any) {
        if (
            order?.order_type === OrderType.DELIVERY &&
            !order?.driver_id &&
            ![OrderStatus.CANCELLED, OrderStatus.COMPLETED].includes(order?.status)
        ) {
            const marker = this.getLastDispatchMarker(order);
            if (marker === 'dispatch_searching' || marker === 'dispatch_retrying') {
                return {
                    status: 'searching_driver',
                    label: 'Đang tìm tài xế',
                };
            }
            if (marker === 'dispatch_expired') {
                return {
                    status: 'dispatch_expired',
                    label: 'Chưa tìm được tài xế',
                };
            }
        }

        return {
            status: order.status,
            label: null,
        };
    }

    private mapItem(item: any) {
        return {
            id: String(item?._id ?? ''),
            item_type: item?.item_type ?? 'product',
            name:
                item?.item_type === 'topping'
                    ? item?.topping_name ?? ''
                    : item?.product_name ?? '',
            product_name: item?.product_name ?? '',
            topping_name: item?.topping_name ?? null,
            quantity: Number(item?.quantity ?? 0),
            unit_price: Number(item?.unit_price ?? 0),
            base_price:
                item?.base_price != null ? Number(item.base_price) : null,
            item_total: Number(item?.item_total ?? 0),
            selected_options: (item?.selected_options ?? []).map((x: any) => ({
                option_name: x?.option_name ?? '',
                choice_name: x?.choice_name ?? '',
                price_modifier: Number(x?.price_modifier ?? 0),
            })),
            selected_toppings: (item?.selected_toppings ?? []).map((x: any) => ({
                topping_id: x?.topping_id ? String(x.topping_id) : null,
                topping_name: x?.topping_name ?? '',
                quantity: Number(x?.quantity ?? 0),
                unit_price: Number(x?.unit_price ?? 0),
            })),
            note: item?.note ?? '',
        };
    }

    private mapOrder(order: any, customer: any, driver: any) {
        const display = this.displayStatus(order);
        return {
            id: String(order._id),
            order_id: String(order._id),
            order_number: order.order_number,
            order_type: order.order_type,
            status: order.status,
            display_status: display.status,
            display_status_label: display.label,

            customer: {
                id: customer?._id ? String(customer._id) : null,
                full_name:
                    order?.delivery_address?.receiver_name ??
                    customer?.full_name ??
                    'Khách hàng',
                phone:
                    order?.delivery_address?.receiver_phone ??
                    customer?.phone ??
                    null,
            },

            driver: !driver
                ? null
                : {
                    id: String(driver._id),
                    full_name: driver.full_name ?? '',
                    phone: driver.phone ?? null,
                    avatar_url: driver.avatar_url ?? null,
                },

            delivery_address: order?.delivery_address
                ? {
                    address: order.delivery_address.address ?? null,
                    receiver_name: order.delivery_address.receiver_name ?? null,
                    receiver_phone: order.delivery_address.receiver_phone ?? null,
                    note: order.delivery_address.note ?? null,
                }
                : null,

            table_session_id: order?.table_session_id
                ? String(order.table_session_id)
                : null,

            items: (order.items ?? []).map((item: any) => this.mapItem(item)),

            subtotal: Number(order?.subtotal ?? 0),
            delivery_fee: Number(order?.delivery_fee ?? 0),
            platform_fee: Number(order?.platform_fee ?? 0),
            total_amount: Number(order?.total_amount ?? 0),

            payment_method: order?.payment_method ?? null,
            payment_status: order?.payment_status ?? null,

            order_note: order?.order_note ?? '',
            cancel_reason: order?.cancel_reason ?? null,
            cancelled_by: order?.cancelled_by ?? null,

            driver_assigned_at: order?.driver_assigned_at
                ? new Date(order.driver_assigned_at).toISOString()
                : null,
            estimated_delivery_time: order?.estimated_delivery_time
                ? new Date(order.estimated_delivery_time).toISOString()
                : null,

            created_at: order?.created_at
                ? new Date(order.created_at).toISOString()
                : null,
            updated_at: order?.updated_at
                ? new Date(order.updated_at).toISOString()
                : null,

            actions: this.buildActions(order),
        };
    }

    async listForMerchantOwner(ownerUserId: string, query: MerchantOrdersQueryDto) {
        const merchant = await this.getMerchantByOwnerUserId(ownerUserId);

        const page = Number(query.page ?? 1);
        const limit = Number(query.limit ?? 20);
        const skip = (page - 1) * limit;

        const filter: any = {
            merchant_id: merchant._id,
        };

        if (query.status) filter.status = query.status;
        if (query.order_type) filter.order_type = query.order_type;

        const [orders, total] = await Promise.all([
            this.orderModel
                .find(filter)
                .sort({ created_at: -1 })
                .skip(skip)
                .limit(limit)
                .lean(),
            this.orderModel.countDocuments(filter),
        ]);

        const customerIds = [
            ...new Set(
                orders
                    .map((x: any) => x.customer_id?.toString?.())
                    .filter(Boolean),
            ),
        ];

        const driverIds = [
            ...new Set(
                orders
                    .map((x: any) => x.driver_id?.toString?.())
                    .filter(Boolean),
            ),
        ];

        const customers = await this.userModel
            .find({ _id: { $in: customerIds.map((x) => this.oid(x)) } })
            .select('_id full_name phone avatar_url')
            .lean();

        const drivers = await this.userModel
            .find({ _id: { $in: driverIds.map((x) => this.oid(x)) } })
            .select('_id full_name phone avatar_url')
            .lean();

        const customerMap = new Map(
            customers.map((x: any) => [String(x._id), x]),
        );
        const driverMap = new Map(
            drivers.map((x: any) => [String(x._id), x]),
        );

        return {
            items: orders.map((order: any) =>
                this.mapOrder(
                    order,
                    customerMap.get(String(order.customer_id)) ?? null,
                    order.driver_id
                        ? driverMap.get(String(order.driver_id)) ?? null
                        : null,
                ),
            ),
            total,
            page,
            limit,
        };
    }

    async getDetailForMerchantOwner(ownerUserId: string, orderId: string) {
        const merchant = await this.getMerchantByOwnerUserId(ownerUserId);

        const order = await this.orderModel
            .findOne({
                _id: this.oid(orderId, 'orderId'),
                merchant_id: merchant._id,
            })
            .lean();

        if (!order) {
            throw new NotFoundException('Order not found');
        }

        const customer = await this.userModel
            .findById(order.customer_id)
            .select('_id full_name phone avatar_url')
            .lean();

        const driver = order.driver_id
            ? await this.userModel
                .findById(order.driver_id)
                .select('_id full_name phone avatar_url')
                .lean()
            : null;

        return this.mapOrder(order, customer, driver);
    }
}
