import {
    BadRequestException,
    Injectable,
    NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';

import {
    Order,
    OrderDocument,
    OrderItemType,
    OrderStatus,
    OrderType,
} from '../schemas/order.schema';
import {
    Merchant,
    MerchantDocument,
} from 'src/modules/merchants/schemas/merchant.schema';
import { User, UserDocument } from 'src/modules/users/schemas/user.schema';

// nếu path khác thì sửa lại đúng project của mày
import { Review, ReviewDocument } from 'src/modules/reviews/schemas/review.schema';
import {
    MerchantReview,
    MerchantReviewDocument,
} from 'src/modules/reviews/schemas/merchant-review.schema';
import {
    DriverReview,
    DriverReviewDocument,
} from 'src/modules/reviews/schemas/driver-review.schema';
import { Cart, CartDocument, CartStatus } from 'src/modules/carts/schemas';

@Injectable()
export class CustomerOrderQueryService {
    constructor(
        @InjectModel(Order.name)
        private readonly orderModel: Model<OrderDocument>,
        @InjectModel(Merchant.name)
        private readonly merchantModel: Model<MerchantDocument>,
        @InjectModel(User.name)
        private readonly userModel: Model<UserDocument>,
        @InjectModel(Review.name)
        private readonly reviewModel: Model<ReviewDocument>,
        @InjectModel(MerchantReview.name)
        private readonly merchantReviewModel: Model<MerchantReviewDocument>,
        @InjectModel(DriverReview.name)
        private readonly driverReviewModel: Model<DriverReviewDocument>,
        @InjectModel(Cart.name)
        private readonly cartModel: Model<CartDocument>,

    ) { }

    private readonly activeStatuses: OrderStatus[] = [
        OrderStatus.PENDING,
        OrderStatus.CONFIRMED,
        OrderStatus.PREPARING,
        OrderStatus.READY_FOR_PICKUP,
        OrderStatus.DRIVER_ASSIGNED,
        OrderStatus.DRIVER_ARRIVED,
        OrderStatus.PICKED_UP,
        OrderStatus.DELIVERING,
        OrderStatus.DELIVERED,
    ];

    private oid(id: string, name = 'id') {
        if (!Types.ObjectId.isValid(id)) {
            throw new BadRequestException(`Invalid ${name}`);
        }
        return new Types.ObjectId(id);
    }

    private statusLabel(status: string, orderType?: string | null) {
        const isDineIn = orderType === OrderType.DINE_IN;

        switch (status) {
            case 'pending':
                return 'Chờ xác nhận';
            case 'confirmed':
                return 'Đã xác nhận';
            case 'preparing':
                return 'Đang chuẩn bị';
            case 'ready_for_pickup':
                return isDineIn ? 'Sẵn sàng phục vụ' : 'Sẵn sàng lấy món';
            case 'driver_assigned':
                return 'Đã có tài xế';
            case 'driver_arrived':
                return 'Tài xế đã tới quán';
            case 'picked_up':
                return 'Đã lấy món';
            case 'delivering':
                return 'Đang giao';
            case 'delivered':
                return 'Đã giao';
            case 'completed':
                return 'Hoàn thành';
            case 'cancelled':
                return 'Đã huỷ';
            default:
                return status;
        }
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
            label: this.statusLabel(order.status, order.order_type),
        };
    }

    private sumItemCount(items: any[] = []) {
        return items.reduce((sum, it) => sum + Number(it?.quantity ?? 0), 0);
    }

    private buildItemsPreview(items: any[] = []) {
        return items.slice(0, 2).map((it) => {
            const name =
                it?.item_type === OrderItemType.TOPPING
                    ? it?.topping_name ?? 'Topping'
                    : it?.product_name ?? 'Sản phẩm';

            return `${Number(it?.quantity ?? 0)}x ${name}`;
        });
    }

    private async getMerchantMap(merchantIds: string[]) {
        const uniqueIds = [...new Set(merchantIds.filter(Boolean))].map(
            (id) => this.oid(id, 'merchantId'),
        );

        if (!uniqueIds.length) return new Map<string, any>();

        const merchants = await this.merchantModel
            .find({ _id: { $in: uniqueIds }, deleted_at: null })
            .select('_id name logo_url address')
            .lean();

        return new Map(
            merchants.map((m: any) => [
                String(m._id),
                {
                    id: String(m._id),
                    name: m.name ?? '',
                    logo_url: m.logo_url ?? null,
                    address: m.address ?? '',
                },
            ]),
        );
    }

    private buildListItem(order: any, merchant: any) {
        const display = this.displayStatus(order);
        return {
            id: String(order._id),
            order_number: order.order_number,
            status: order.status,
            status_label: display.label,
            display_status: display.status,
            display_status_label: display.label,
            order_type: order.order_type,
            created_at: order.created_at,
            updated_at: order.updated_at,
            total_amount: Number(order.total_amount ?? 0),
            item_count: this.sumItemCount(order.items),
            eta_at: order.estimated_delivery_time
                ? new Date(order.estimated_delivery_time).toISOString()
                : null,
            eta_min: order.estimated_delivery_time
                ? Math.max(
                    0,
                    Math.ceil(
                        (new Date(order.estimated_delivery_time).getTime() - Date.now()) /
                        60000,
                    ),
                )
                : null,
            merchant: merchant ?? {
                id: String(order.merchant_id ?? ''),
                name: '',
                logo_url: null,
                address: '',
            },
            items_preview: this.buildItemsPreview(order.items),
            actions: {
                can_cancel: order.status === OrderStatus.PENDING,
                can_open_detail: true,
            },
        };
    }

    async getTabCounts(customerUserId: string) {
        const customerId = this.oid(customerUserId, 'customerUserId');

        const [
            activeCount,
            historyCount,
            productReviewCount,
            merchantReviewCount,
            driverReviewCount,
            draftCount,
        ] = await Promise.all([
            this.orderModel.countDocuments({
                customer_id: customerId,
                status: { $in: this.activeStatuses },
            }),
            this.orderModel.countDocuments({
                customer_id: customerId,
                status: OrderStatus.COMPLETED,
            }),
            this.reviewModel.countDocuments({
                user_id: customerId,
                deleted_at: null,
            }),
            this.merchantReviewModel.countDocuments({
                customer_id: customerId,
                deleted_at: null,
            }),
            this.driverReviewModel.countDocuments({
                customer_id: customerId,
                deleted_at: null,
            }),
            this.cartModel.countDocuments({
                user_id: customerId,
                order_type: OrderType.DELIVERY,
                status: CartStatus.ACTIVE,
                deleted_at: null,
                'items.0': { $exists: true },
            }),
        ]);

        return {
            active_count: Number(activeCount ?? 0),
            review_count:
                Number(productReviewCount ?? 0) +
                Number(merchantReviewCount ?? 0) +
                Number(driverReviewCount ?? 0),
            history_count: Number(historyCount ?? 0),
            draft_count: Number(draftCount ?? 0),
        };
    }
    async getActiveOrders(
        customerUserId: string,
        query: { limit?: number; cursor?: string },
    ) {
        const customerId = this.oid(customerUserId, 'customerUserId');
        const limit = Math.min(Math.max(Number(query.limit ?? 10), 1), 30);

        const where: any = {
            customer_id: customerId,
            status: { $in: this.activeStatuses },
        };

        if (query.cursor) {
            const d = new Date(query.cursor);
            if (!Number.isNaN(d.getTime())) {
                where.created_at = { $lt: d };
            }
        }

        const rows = await this.orderModel
            .find(where)
            .sort({ created_at: -1, _id: -1 })
            .limit(limit + 1)
            .lean();

        const hasMore = rows.length > limit;
        const sliced = hasMore ? rows.slice(0, limit) : rows;

        const merchantMap = await this.getMerchantMap(
            sliced.map((x: any) => String(x.merchant_id ?? '')),
        );

        const items = sliced.map((row: any) =>
            this.buildListItem(row, merchantMap.get(String(row.merchant_id))),
        );

        return {
            items,
            next_cursor:
                hasMore && items.length
                    ? new Date(items[items.length - 1].created_at).toISOString()
                    : null,
            has_more: hasMore,
        };
    }

    async getHistoryOrders(
        customerUserId: string,
        query: { limit?: number; cursor?: string },
    ) {
        const customerId = this.oid(customerUserId, 'customerUserId');
        const limit = Math.min(Math.max(Number(query.limit ?? 10), 1), 30);

        const where: any = {
            customer_id: customerId,
            status: OrderStatus.COMPLETED,
        };

        if (query.cursor) {
            const d = new Date(query.cursor);
            if (!Number.isNaN(d.getTime())) {
                where.created_at = { $lt: d };
            }
        }

        const rows = await this.orderModel
            .find(where)
            .sort({ created_at: -1, _id: -1 })
            .limit(limit + 1)
            .lean();

        const hasMore = rows.length > limit;
        const sliced = hasMore ? rows.slice(0, limit) : rows;

        const merchantMap = await this.getMerchantMap(
            sliced.map((x: any) => String(x.merchant_id ?? '')),
        );

        const items = sliced.map((row: any) =>
            this.buildListItem(row, merchantMap.get(String(row.merchant_id))),
        );

        return {
            items,
            next_cursor:
                hasMore && items.length
                    ? new Date(items[items.length - 1].created_at).toISOString()
                    : null,
            has_more: hasMore,
        };
    }

    async getOrderDetail(customerUserId: string, orderId: string) {
        const customerId = this.oid(customerUserId, 'customerUserId');

        const order: any = await this.orderModel
            .findOne({
                _id: this.oid(orderId, 'orderId'),
                customer_id: customerId,
            })
            .lean();

        if (!order) {
            throw new NotFoundException('Order not found');
        }

        const [merchant, driver, merchantReviewed, driverReviewed] =
            await Promise.all([
                this.merchantModel
                    .findById(order.merchant_id)
                    .select('_id name logo_url address')
                    .lean(),
                order.driver_id
                    ? this.userModel
                        .findById(order.driver_id)
                        .select('_id full_name phone avatar_url')
                        .lean()
                    : null,
                this.merchantReviewModel.countDocuments({
                    customer_id: customerId,
                    order_id: order._id,
                    deleted_at: null,
                }),
                order.driver_id
                    ? this.driverReviewModel.countDocuments({
                        customer_id: customerId,
                        driver_user_id: order.driver_id,
                        order_id: order._id,
                        deleted_at: null,
                    })
                    : 0,
            ]);

        const display = this.displayStatus(order);

        return {
            id: String(order._id),
            order_number: order.order_number,
            status: order.status,
            status_label: display.label,
            display_status: display.status,
            display_status_label: display.label,
            order_type: order.order_type,
            created_at: order.created_at,
            updated_at: order.updated_at,
            payment_method: order.payment_method ?? '',
            payment_status: order.payment_status ?? '',
            subtotal: Number(order.subtotal ?? 0),
            delivery_fee: Number(order.delivery_fee ?? 0),
            total_amount: Number(order.total_amount ?? 0),
            discounts: {
                food_discount: Number(order?.discounts?.food_discount ?? 0),
                delivery_discount: Number(order?.discounts?.delivery_discount ?? 0),
                total_discount: Number(order?.discounts?.total_discount ?? 0),
            },
            merchant: merchant
                ? {
                    id: String(merchant._id),
                    name: merchant.name ?? '',
                    logo_url: merchant.logo_url ?? null,
                    address: merchant.address ?? '',
                }
                : null,
            driver: driver
                ? {
                    id: String(driver._id),
                    full_name: driver.full_name ?? '',
                    phone: driver.phone ?? '',
                    avatar_url: driver.avatar_url ?? null,
                }
                : null,
            delivery_address: order.delivery_address
                ? {
                    address: order.delivery_address.address ?? '',
                    receiver_name: order.delivery_address.receiver_name ?? '',
                    receiver_phone: order.delivery_address.receiver_phone ?? '',
                    note: order.delivery_address.note ?? '',
                }
                : null,
            items: (order.items ?? []).map((it: any) => ({
                id: String(it._id ?? ''),
                item_type: it.item_type,
                product_id:
                    it.item_type === OrderItemType.PRODUCT && it.product_id
                        ? String(it.product_id)
                        : null,
                topping_id:
                    it.item_type === OrderItemType.TOPPING && it.topping_id
                        ? String(it.topping_id)
                        : null,
                name:
                    it.item_type === OrderItemType.TOPPING
                        ? it.topping_name ?? 'Topping'
                        : it.product_name ?? 'Sản phẩm',
                image:
                    it.item_type === OrderItemType.TOPPING
                        ? null
                        : it.product_image ?? null,
                quantity: Number(it.quantity ?? 0),
                unit_price: Number(it.unit_price ?? 0),
                item_total: Number(it.item_total ?? 0),
                selected_options: it.selected_options ?? [],
                selected_toppings: it.selected_toppings ?? [],
            })),

            status_history: (order.status_history ?? []).map((x: any) => ({
                status: x.status ?? '',
                changed_at: x.changed_at ? new Date(x.changed_at).toISOString() : null,
                note: x.note ?? null,
            })),
            actions: {
                can_cancel: order.status === OrderStatus.PENDING,
                can_review_merchant: order.status === OrderStatus.COMPLETED,
                can_review_driver:
                    order.status === OrderStatus.COMPLETED && !!order.driver_id,
            },
            review_status: {
                merchant_reviewed: Number(merchantReviewed ?? 0) > 0,
                driver_reviewed: Number(driverReviewed ?? 0) > 0,
            },
        };
    }
}
