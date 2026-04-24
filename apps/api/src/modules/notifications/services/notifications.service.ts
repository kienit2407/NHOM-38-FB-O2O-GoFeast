import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { CreateNotificationDto } from '../dtos/create-notification.dto';
import {
    Notification,
    NotificationDocument,
    NotificationRecipientRole,
    NotificationType,
} from '../schemas/notification.schema';

@Injectable()
export class NotificationsService {
    constructor(
        @InjectModel(Notification.name)
        private readonly model: Model<NotificationDocument>,
    ) { }

    private resolveRecipientRole(
        role?: string,
    ): NotificationRecipientRole | undefined {
        switch (role) {
            case NotificationRecipientRole.CUSTOMER:
                return NotificationRecipientRole.CUSTOMER;
            case NotificationRecipientRole.DRIVER:
                return NotificationRecipientRole.DRIVER;
            case NotificationRecipientRole.MERCHANT:
                return NotificationRecipientRole.MERCHANT;
            case NotificationRecipientRole.ADMIN:
                return NotificationRecipientRole.ADMIN;
            default:
                return undefined;
        }
    }

    async createOne(dto: CreateNotificationDto) {
        return this.model.create({
            user_id: new Types.ObjectId(dto.userId),
            recipient_role: dto.recipientRole,
            type: dto.type,
            title: dto.title,
            body: dto.body,
            data: dto.data ?? {},
            is_read: false,
            read_at: null,
        });
    }
    async notifyMerchantReviewReceived(params: {
        userId: string;
        reviewId: string;
        reviewType: 'merchant' | 'product';
        merchantId: string;
        orderId: string;
        productId?: string;
        title?: string;
        body?: string;
    }) {
        return this.createOne({
            userId: params.userId,
            recipientRole: NotificationRecipientRole.MERCHANT,
            type: NotificationType.REVIEW_RECEIVED,
            title: params.title ?? 'Có đánh giá mới',
            body: params.body ?? 'Khách vừa gửi một đánh giá mới.',
            data: {
                action: 'open_review',
                review_id: params.reviewId,
                review_type: params.reviewType,
                merchant_id: params.merchantId,
                order_id: params.orderId,
                product_id: params.productId,
            },
        });
    }

    async notifyDriverReviewReceived(params: {
        userId: string;
        reviewId: string;
        orderId: string;
        driverId: string;
        title?: string;
        body?: string;
    }) {
        return this.createOne({
            userId: params.userId,
            recipientRole: NotificationRecipientRole.DRIVER,
            type: NotificationType.REVIEW_RECEIVED,
            title: params.title ?? 'Bạn vừa nhận được đánh giá mới',
            body: params.body ?? 'Khách vừa đánh giá chuyến giao hàng của bạn.',
            data: {
                action: 'open_order',
                review_id: params.reviewId,
                review_type: 'driver',
                order_id: params.orderId,
                driver_id: params.driverId,
            },
        });
    }
    async removeOne(userId: string, notificationId: string, role?: string) {
        const recipientRole = this.resolveRecipientRole(role);
        const row = await this.model.findOneAndDelete({
            _id: new Types.ObjectId(notificationId),
            user_id: new Types.ObjectId(userId),
            ...(recipientRole ? { recipient_role: recipientRole } : {}),
        });

        return { deleted: !!row };
    }

    async clearAll(userId: string, role?: string) {
        const recipientRole = this.resolveRecipientRole(role);
        const res = await this.model.deleteMany({
            user_id: new Types.ObjectId(userId),
            ...(recipientRole ? { recipient_role: recipientRole } : {}),
        });

        return {
            deleted: res.deletedCount ?? 0,
        };
    }
    async notifyCustomerReviewReply(params: {
        userId: string;
        reviewId: string;
        reviewType: 'merchant' | 'product';
        merchantId: string;
        orderId: string;
        productId?: string;
        title?: string;
        body?: string;
    }) {
        return this.createOne({
            userId: params.userId,
            recipientRole: NotificationRecipientRole.CUSTOMER,
            type: NotificationType.REVIEW_REPLIED,
            title: params.title ?? 'Quán đã phản hồi đánh giá của bạn',
            body: params.body ?? 'Bạn vừa nhận được phản hồi cho đánh giá của mình.',
            data: {
                action:
                    params.reviewType === 'product'
                        ? 'open_product_detail'
                        : 'open_merchant_detail',
                review_id: params.reviewId,
                review_type: params.reviewType,
                merchant_id: params.merchantId,
                order_id: params.orderId,
                product_id: params.productId,
            },
        });
    }
    toRealtimePayload(row: any) {
        return {
            id: String(row._id),
            type: row.type,
            title: row.title,
            body: row.body,
            is_read: !!row.is_read,
            created_at: row.created_at,
            data: {
                action: row.data?.action ?? null,
                order_id: row.data?.order_id ? String(row.data.order_id) : null,
                order_number: row.data?.order_number ?? null,
                image_url: row.data?.image_url ?? null,
                merchant_id: row.data?.merchant_id ? String(row.data.merchant_id) : null,
                driver_id: row.data?.driver_id ? String(row.data.driver_id) : null,
                product_id: row.data?.product_id ? String(row.data.product_id) : null,
                review_id: row.data?.review_id ? String(row.data.review_id) : null,
                review_type: row.data?.review_type ?? null,
                promotion_id: row.data?.promotion_id ? String(row.data.promotion_id) : null,
                table_number: row.data?.table_number ?? null,
                order_type: row.data?.order_type ?? null,
            },
        };
    }
    async createMany(inputs: CreateNotificationDto[]) {
        if (!inputs.length) return [];
        return this.model.insertMany(
            inputs.map((dto) => ({
                user_id: new Types.ObjectId(dto.userId),
                recipient_role: dto.recipientRole,
                type: dto.type,
                title: dto.title,
                body: dto.body,
                data: dto.data ?? {},
                is_read: false,
                read_at: null,
            })),
        );
    }

    async listMine(
        userId: string,
        page = 1,
        limit = 20,
        opts?: { excludePromotion?: boolean; role?: string },
    ) {
        const skip = (page - 1) * limit;
        const recipientRole = this.resolveRecipientRole(opts?.role);

        const filter: any = {
            user_id: new Types.ObjectId(userId),
            ...(recipientRole ? { recipient_role: recipientRole } : {}),
        };

        if (opts?.excludePromotion) {
            filter.type = { $ne: NotificationType.PROMOTION };
        }

        const [items, total, unread] = await Promise.all([
            this.model.find(filter).sort({ created_at: -1 }).skip(skip).limit(limit).lean(),
            this.model.countDocuments(filter),
            this.model.countDocuments({
                ...filter,
                is_read: false,
            }),
        ]);

        return { items, total, unread, page, limit };
    }

    async getUnreadCount(
        userId: string,
        opts?: { excludePromotion?: boolean; role?: string },
    ) {
        const recipientRole = this.resolveRecipientRole(opts?.role);
        const filter: any = {
            user_id: new Types.ObjectId(userId),
            is_read: false,
            ...(recipientRole ? { recipient_role: recipientRole } : {}),
        };

        if (opts?.excludePromotion) {
            filter.type = { $ne: NotificationType.PROMOTION };
        }

        const unread = await this.model.countDocuments(filter);
        return { unread };
    }

    async markRead(userId: string, notificationId: string, role?: string) {
        const recipientRole = this.resolveRecipientRole(role);
        return this.model.findOneAndUpdate(
            {
                _id: new Types.ObjectId(notificationId),
                user_id: new Types.ObjectId(userId),
                ...(recipientRole ? { recipient_role: recipientRole } : {}),
            },
            {
                $set: {
                    is_read: true,
                    read_at: new Date(),
                },
            },
            { new: true },
        );
    }

    async markAllRead(userId: string, role?: string) {
        const recipientRole = this.resolveRecipientRole(role);
        const res = await this.model.updateMany(
            {
                user_id: new Types.ObjectId(userId),
                is_read: false,
                ...(recipientRole ? { recipient_role: recipientRole } : {}),
            },
            {
                $set: {
                    is_read: true,
                    read_at: new Date(),
                },
            },
        );

        return {
            matched: res.matchedCount,
            modified: res.modifiedCount,
        };
    }



    // =========================
    // helper dùng cho business flow
    // =========================

    async notifyCustomerOrderCreated(params: {
        userId: string;
        orderId: string;
        orderNumber?: string;
        imageUrl?: string;
        orderType?: string;
    }) {
        return this.createOne({
            userId: params.userId,
            recipientRole: NotificationRecipientRole.CUSTOMER,
            type: NotificationType.ORDER_CREATED,
            title: 'Đặt đơn thành công',
            body: 'Đơn hàng của bạn đã được tạo thành công.',
            data: {
                action: 'open_order',
                order_id: params.orderId,
                order_number: params.orderNumber,
                image_url: params.imageUrl,
                order_type: params.orderType,
            },
        });
    }

    async notifyCustomerOrderStatus(params: {
        userId: string;
        orderId: string;
        orderNumber?: string;
        imageUrl?: string;
        status: string;
        body?: string;
        orderType?: string;
    }) {
        return this.createOne({
            userId: params.userId,
            recipientRole: NotificationRecipientRole.CUSTOMER,
            type: NotificationType.ORDER_STATUS,
            title: 'Cập nhật đơn hàng',
            body: params.body ?? `Đơn hàng của bạn đã chuyển sang trạng thái ${params.status}.`,
            data: {
                action: 'open_order',
                order_id: params.orderId,
                order_number: params.orderNumber,
                image_url: params.imageUrl,
                order_type: params.orderType,
            },
        });
    }

    async notifyDriverNewOffer(params: {
        userId: string;
        orderId: string;
        orderNumber?: string;
        imageUrl?: string;
    }) {
        return this.createOne({
            userId: params.userId,
            recipientRole: NotificationRecipientRole.DRIVER,
            type: NotificationType.ORDER_OFFER,
            title: 'Có đơn mới',
            body: 'Bạn vừa nhận được một đề nghị đơn hàng mới.',
            data: {
                action: 'open_order_offer',
                order_id: params.orderId,
                order_number: params.orderNumber,
                image_url: params.imageUrl,
            },
        });
    }

    async notifyMerchantNewOrder(params: {
        userId: string;
        orderId: string;
        orderNumber?: string;
        imageUrl?: string;
        orderType?: string;
        tableNumber?: string;
    }) {
        const isDineIn = params.orderType === 'dine_in';

        return this.createOne({
            userId: params.userId,
            recipientRole: NotificationRecipientRole.MERCHANT,
            type: NotificationType.ORDER_CREATED,
            title: isDineIn
                ? `Đơn mới tại bàn ${params.tableNumber ?? ''}`.trim()
                : 'Đơn mới',
            body: isDineIn
                ? 'Nhà hàng vừa nhận được đơn tại bàn mới.'
                : 'Nhà hàng vừa nhận được đơn mới từ khách.',
            data: {
                action: 'open_order',
                order_id: params.orderId,
                order_number: params.orderNumber,
                image_url: params.imageUrl,
                order_type: params.orderType,
                table_number: params.tableNumber,
            },
        });
    }

    async notifyMerchantOrderStatus(params: {
        userId: string;
        orderId: string;
        orderNumber?: string;
        imageUrl?: string;
        status: string;
        body?: string;
        orderType?: string;
    }) {
        return this.createOne({
            userId: params.userId,
            recipientRole: NotificationRecipientRole.MERCHANT,
            type: NotificationType.ORDER_STATUS,
            title: 'Cập nhật đơn hàng',
            body: params.body ?? `Đơn hàng đã chuyển sang trạng thái ${params.status}.`,
            data: {
                action: 'open_order',
                order_id: params.orderId,
                order_number: params.orderNumber,
                image_url: params.imageUrl,
                order_type: params.orderType,
            },
        });
    }

    async notifyAdminMerchantApproval(params: {
        userId: string;
        merchantId: string;
        title?: string;
        body?: string;
    }) {
        return this.createOne({
            userId: params.userId,
            recipientRole: NotificationRecipientRole.ADMIN,
            type: NotificationType.MERCHANT_APPROVAL,
            title: params.title ?? 'Có merchant chờ duyệt',
            body: params.body ?? 'Một merchant mới vừa nộp hồ sơ và đang chờ duyệt.',
            data: {
                action: 'open_merchant_review',
                merchant_id: params.merchantId,
            },
        });
    }

    async notifyAdminDriverApproval(params: {
        userId: string;
        driverUserId: string;
        title?: string;
        body?: string;
    }) {
        return this.createOne({
            userId: params.userId,
            recipientRole: NotificationRecipientRole.ADMIN,
            type: NotificationType.DRIVER_APPROVAL,
            title: params.title ?? 'Có tài xế chờ duyệt',
            body: params.body ?? 'Một tài xế mới vừa nộp hồ sơ và đang chờ duyệt.',
            data: {
                action: 'open_driver_review',
                driver_id: params.driverUserId,
            },
        });
    }
}
