import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';

import {
    Order,
    OrderDocument,
    OrderStatus,
    OrderType,
} from 'src/modules/orders/schemas/order.schema';
import {
    Merchant,
    MerchantApprovalStatus,
    MerchantDocument,
} from 'src/modules/merchants/schemas/merchant.schema';
import { User, UserDocument } from 'src/modules/users/schemas/user.schema';
import {
    DriverProfile,
    DriverProfileDocument,
    DriverVerificationStatus,
} from 'src/modules/drivers/schemas/driver-profile.schema';
import { OrderLifecycleService } from 'src/modules/orders/services/order-lifecycle.service';

import { AdminDashboardQueryDto } from '../dtos/admin-dashboard-query.dto';
import { AdminOrdersQueryDto } from '../dtos/admin-orders-query.dto';
import { AdminGlobalSearchQueryDto } from '../dtos/admin-global-search-query.dto';

@Injectable()
export class AdminOpsService {
    private readonly tz = 'Asia/Ho_Chi_Minh';

    private readonly acceptedStatuses: string[] = [
        OrderStatus.CONFIRMED,
        OrderStatus.PREPARING,
        OrderStatus.READY_FOR_PICKUP,
        OrderStatus.DRIVER_ASSIGNED,
        OrderStatus.DRIVER_ARRIVED,
        OrderStatus.PICKED_UP,
        OrderStatus.DELIVERING,
        OrderStatus.DELIVERED,
        OrderStatus.COMPLETED,
        OrderStatus.SERVED,
    ];

    constructor(
        @InjectModel(Order.name)
        private readonly orderModel: Model<OrderDocument>,
        @InjectModel(Merchant.name)
        private readonly merchantModel: Model<MerchantDocument>,
        @InjectModel(User.name)
        private readonly userModel: Model<UserDocument>,
        @InjectModel(DriverProfile.name)
        private readonly driverProfileModel: Model<DriverProfileDocument>,
        private readonly orderLifecycleService: OrderLifecycleService,
    ) { }

    private parsePage(raw?: string, fallback = 1) {
        const n = Number(raw ?? fallback);
        if (!Number.isFinite(n)) return fallback;
        return Math.max(1, Math.floor(n));
    }

    private parseLimit(raw?: string, fallback = 20, max = 100) {
        const n = Number(raw ?? fallback);
        if (!Number.isFinite(n)) return fallback;
        return Math.max(1, Math.min(max, Math.floor(n)));
    }

    private parseHeatmapHours(raw?: string) {
        const n = Number(raw ?? 6);
        if (!Number.isFinite(n)) return 6;
        return Math.max(1, Math.min(24, Math.floor(n)));
    }

    private escapeRegex(input: string) {
        return input.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }

    private oid(id: string, name = 'id') {
        if (!Types.ObjectId.isValid(id)) {
            throw new BadRequestException(`Invalid ${name}`);
        }
        return new Types.ObjectId(id);
    }

    private dateKeyInTz(date = new Date()) {
        const parts = new Intl.DateTimeFormat('en-CA', {
            timeZone: this.tz,
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
        }).formatToParts(date);

        const y = parts.find((x) => x.type === 'year')?.value;
        const m = parts.find((x) => x.type === 'month')?.value;
        const d = parts.find((x) => x.type === 'day')?.value;

        return `${y}-${m}-${d}`;
    }

    private hourLabel(hour: number) {
        return `${String(hour).padStart(2, '0')}:00`;
    }

    private async getHeatmapPoints(hours: number) {
        const since = new Date(Date.now() - hours * 60 * 60 * 1000);

        const rows = await this.orderModel.aggregate([
            {
                $match: {
                    created_at: { $gte: since },
                },
            },
            {
                $lookup: {
                    from: 'merchants',
                    localField: 'merchant_id',
                    foreignField: '_id',
                    as: 'merchant',
                },
            },
            {
                $unwind: {
                    path: '$merchant',
                    preserveNullAndEmptyArrays: true,
                },
            },
            {
                $addFields: {
                    delivery_coords: '$delivery_address.location.coordinates',
                    merchant_coords: '$merchant.location.coordinates',
                },
            },
            {
                $addFields: {
                    point_coords: {
                        $cond: [
                            {
                                $and: [
                                    { $eq: ['$order_type', OrderType.DELIVERY] },
                                    { $isArray: '$delivery_coords' },
                                ],
                            },
                            '$delivery_coords',
                            '$merchant_coords',
                        ],
                    },
                },
            },
            {
                $match: {
                    point_coords: { $type: 'array' },
                    'point_coords.0': { $type: 'number' },
                    'point_coords.1': { $type: 'number' },
                },
            },
            {
                $project: {
                    _id: 1,
                    order_type: 1,
                    status: 1,
                    lat: { $arrayElemAt: ['$point_coords', 1] },
                    lng: { $arrayElemAt: ['$point_coords', 0] },
                    weight: {
                        $cond: [
                            { $eq: ['$status', OrderStatus.CANCELLED] },
                            0.3,
                            1,
                        ],
                    },
                    created_at: 1,
                },
            },
            {
                $sort: { created_at: -1 },
            },
            {
                $limit: 1200,
            },
        ]);

        return rows.map((row: any) => ({
            id: String(row._id),
            order_type: row.order_type,
            status: row.status,
            lat: Number(row.lat),
            lng: Number(row.lng),
            weight: Number(row.weight ?? 1),
            created_at: row.created_at,
        }));
    }

    async getDashboardSummary(query: AdminDashboardQueryDto) {
        const todayKey = this.dateKeyInTz(new Date());
        const heatmapHours = this.parseHeatmapHours(query.heatmap_hours);

        const [todayRows, hourlyRows, activeDrivers, pendingMerchants, pendingDrivers, heatmapPoints] = await Promise.all([
            this.orderModel.aggregate([
                {
                    $match: {
                        $expr: {
                            $eq: [
                                {
                                    $dateToString: {
                                        format: '%Y-%m-%d',
                                        date: '$created_at',
                                        timezone: this.tz,
                                    },
                                },
                                todayKey,
                            ],
                        },
                    },
                },
                {
                    $group: {
                        _id: null,
                        total_orders_today: { $sum: 1 },
                        gmv_today: {
                            $sum: { $ifNull: ['$total_amount', 0] },
                        },
                        cancelled_orders_today: {
                            $sum: {
                                $cond: [{ $eq: ['$status', OrderStatus.CANCELLED] }, 1, 0],
                            },
                        },
                        accepted_orders_today: {
                            $sum: {
                                $cond: [{ $in: ['$status', this.acceptedStatuses] }, 1, 0],
                            },
                        },
                        unique_customers: {
                            $addToSet: '$customer_id',
                        },
                    },
                },
                {
                    $project: {
                        _id: 0,
                        total_orders_today: 1,
                        gmv_today: 1,
                        cancelled_orders_today: 1,
                        accepted_orders_today: 1,
                        active_users: {
                            $size: {
                                $filter: {
                                    input: '$unique_customers',
                                    as: 'c',
                                    cond: { $ne: ['$$c', null] },
                                },
                            },
                        },
                    },
                },
            ]),
            this.orderModel.aggregate([
                {
                    $match: {
                        $expr: {
                            $eq: [
                                {
                                    $dateToString: {
                                        format: '%Y-%m-%d',
                                        date: '$created_at',
                                        timezone: this.tz,
                                    },
                                },
                                todayKey,
                            ],
                        },
                    },
                },
                {
                    $group: {
                        _id: {
                            $hour: {
                                date: '$created_at',
                                timezone: this.tz,
                            },
                        },
                        orders: { $sum: 1 },
                    },
                },
                { $sort: { _id: 1 } },
            ]),
            this.driverProfileModel.countDocuments({
                verification_status: DriverVerificationStatus.APPROVED,
                last_location_update: { $gte: new Date(Date.now() - 15 * 60 * 1000) },
            }),
            this.merchantModel.countDocuments({
                deleted_at: null,
                approval_status: MerchantApprovalStatus.PENDING_APPROVAL,
            }),
            this.driverProfileModel.countDocuments({
                verification_status: DriverVerificationStatus.PENDING,
            }),
            this.getHeatmapPoints(heatmapHours),
        ]);

        const today = todayRows[0] ?? {
            total_orders_today: 0,
            gmv_today: 0,
            cancelled_orders_today: 0,
            accepted_orders_today: 0,
            active_users: 0,
        };

        const totalOrdersToday = Number(today.total_orders_today ?? 0);
        const cancelledOrdersToday = Number(today.cancelled_orders_today ?? 0);
        const acceptedOrdersToday = Number(today.accepted_orders_today ?? 0);

        const cancellationRate =
            totalOrdersToday > 0
                ? Number(((cancelledOrdersToday / totalOrdersToday) * 100).toFixed(1))
                : 0;

        const acceptanceRate =
            totalOrdersToday > 0
                ? Number(((acceptedOrdersToday / totalOrdersToday) * 100).toFixed(1))
                : 0;

        const hourlyMap = new Map<number, number>();
        for (const row of hourlyRows) {
            hourlyMap.set(Number(row._id), Number(row.orders ?? 0));
        }

        const ordersPerHour = Array.from({ length: 24 }, (_, hour) => ({
            hour: this.hourLabel(hour),
            orders: hourlyMap.get(hour) ?? 0,
        }));

        return {
            total_orders_today: totalOrdersToday,
            gmv_today: Number(today.gmv_today ?? 0),
            active_users: Number(today.active_users ?? 0),
            active_drivers: Number(activeDrivers ?? 0),
            cancellation_rate: cancellationRate,
            acceptance_rate: acceptanceRate,
            pending_merchants: Number(pendingMerchants ?? 0),
            pending_drivers: Number(pendingDrivers ?? 0),
            orders_per_hour: ordersPerHour,
            heatmap_hours: heatmapHours,
            heatmap_points: heatmapPoints,
            last_updated: new Date().toISOString(),
        };
    }

    async getOrders(query: AdminOrdersQueryDto) {
        const page = this.parsePage(query.page, 1);
        const limit = this.parseLimit(query.limit, 20, 100);
        const skip = (page - 1) * limit;

        const baseMatch: any = {};
        if (query.order_type) {
            baseMatch.order_type = query.order_type;
        }
        if (query.status && query.status !== 'all') {
            baseMatch.status = query.status;
        }

        const q = (query.q ?? '').trim();
        const qRegex = q ? new RegExp(this.escapeRegex(q), 'i') : null;
        const qOid = q && Types.ObjectId.isValid(q) ? new Types.ObjectId(q) : null;

        const pipeline: any[] = [
            { $match: baseMatch },
            {
                $lookup: {
                    from: 'users',
                    localField: 'customer_id',
                    foreignField: '_id',
                    as: 'customer',
                },
            },
            {
                $unwind: {
                    path: '$customer',
                    preserveNullAndEmptyArrays: true,
                },
            },
            {
                $lookup: {
                    from: 'users',
                    localField: 'driver_id',
                    foreignField: '_id',
                    as: 'driver',
                },
            },
            {
                $unwind: {
                    path: '$driver',
                    preserveNullAndEmptyArrays: true,
                },
            },
            {
                $lookup: {
                    from: 'merchants',
                    localField: 'merchant_id',
                    foreignField: '_id',
                    as: 'merchant',
                },
            },
            {
                $unwind: {
                    path: '$merchant',
                    preserveNullAndEmptyArrays: true,
                },
            },
            {
                $lookup: {
                    from: 'table_sessions',
                    localField: 'table_session_id',
                    foreignField: '_id',
                    as: 'table_session',
                },
            },
            {
                $unwind: {
                    path: '$table_session',
                    preserveNullAndEmptyArrays: true,
                },
            },
            {
                $lookup: {
                    from: 'tables',
                    localField: 'table_session.table_id',
                    foreignField: '_id',
                    as: 'table',
                },
            },
            {
                $unwind: {
                    path: '$table',
                    preserveNullAndEmptyArrays: true,
                },
            },
        ];

        if (qRegex || qOid) {
            const searchOr: any[] = [];

            if (qRegex) {
                searchOr.push(
                    { order_number: qRegex },
                    { 'customer.full_name': qRegex },
                    { 'customer.phone': qRegex },
                    { 'merchant.name': qRegex },
                    { 'merchant.phone': qRegex },
                    { 'driver.full_name': qRegex },
                    { 'driver.phone': qRegex },
                );
            }

            if (qOid) {
                searchOr.push(
                    { _id: qOid },
                    { 'customer._id': qOid },
                    { 'merchant._id': qOid },
                    { 'driver._id': qOid },
                );
            }

            pipeline.push({ $match: { $or: searchOr } });
        }

        pipeline.push(
            { $sort: { created_at: -1 } },
            {
                $facet: {
                    items: [
                        { $skip: skip },
                        { $limit: limit },
                        {
                            $project: {
                                _id: 0,
                                id: { $toString: '$_id' },
                                order_number: 1,
                                order_type: 1,
                                status: 1,
                                customer: {
                                    id: {
                                        $cond: [
                                            { $ifNull: ['$customer._id', false] },
                                            { $toString: '$customer._id' },
                                            null,
                                        ],
                                    },
                                    full_name: {
                                        $ifNull: [
                                            '$delivery_address.receiver_name',
                                            { $ifNull: ['$customer.full_name', 'Khách hàng'] },
                                        ],
                                    },
                                    phone: {
                                        $ifNull: ['$delivery_address.receiver_phone', '$customer.phone'],
                                    },
                                },
                                merchant: {
                                    id: {
                                        $cond: [
                                            { $ifNull: ['$merchant._id', false] },
                                            { $toString: '$merchant._id' },
                                            null,
                                        ],
                                    },
                                    name: { $ifNull: ['$merchant.name', 'N/A'] },
                                },
                                driver: {
                                    $cond: [
                                        { $ifNull: ['$driver._id', false] },
                                        {
                                            id: { $toString: '$driver._id' },
                                            full_name: { $ifNull: ['$driver.full_name', ''] },
                                            phone: '$driver.phone',
                                        },
                                        null,
                                    ],
                                },
                                table: {
                                    $cond: [
                                        { $ifNull: ['$table._id', false] },
                                        {
                                            session_id: {
                                                $cond: [
                                                    { $ifNull: ['$table_session._id', false] },
                                                    { $toString: '$table_session._id' },
                                                    null,
                                                ],
                                            },
                                            table_id: { $toString: '$table._id' },
                                            table_number: '$table.table_number',
                                            table_name: '$table.name',
                                        },
                                        null,
                                    ],
                                },
                                subtotal: { $ifNull: ['$subtotal', 0] },
                                delivery_fee: { $ifNull: ['$delivery_fee', 0] },
                                platform_fee: { $ifNull: ['$platform_fee', 0] },
                                total_amount: { $ifNull: ['$total_amount', 0] },
                                payment_method: { $ifNull: ['$payment_method', null] },
                                payment_status: { $ifNull: ['$payment_status', null] },
                                cancel_reason: { $ifNull: ['$cancel_reason', null] },
                                created_at: 1,
                                updated_at: 1,
                            },
                        },
                    ],
                    total: [{ $count: 'value' }],
                    status_counts: [
                        {
                            $group: {
                                _id: '$status',
                                count: { $sum: 1 },
                            },
                        },
                    ],
                },
            },
        );

        const [agg] = await this.orderModel.aggregate(pipeline);

        const items = agg?.items ?? [];
        const total = Number(agg?.total?.[0]?.value ?? 0);

        const statusCounts = (agg?.status_counts ?? []).reduce(
            (acc: Record<string, number>, cur: any) => {
                acc[String(cur._id)] = Number(cur.count ?? 0);
                return acc;
            },
            {},
        );

        return {
            items,
            total,
            page,
            limit,
            status_counts: statusCounts,
        };
    }

    async getOrderDetail(orderId: string) {
        const oid = this.oid(orderId, 'orderId');

        const rows = await this.orderModel.aggregate([
            { $match: { _id: oid } },
            {
                $lookup: {
                    from: 'users',
                    localField: 'customer_id',
                    foreignField: '_id',
                    as: 'customer',
                },
            },
            {
                $unwind: {
                    path: '$customer',
                    preserveNullAndEmptyArrays: true,
                },
            },
            {
                $lookup: {
                    from: 'users',
                    localField: 'driver_id',
                    foreignField: '_id',
                    as: 'driver',
                },
            },
            {
                $unwind: {
                    path: '$driver',
                    preserveNullAndEmptyArrays: true,
                },
            },
            {
                $lookup: {
                    from: 'merchants',
                    localField: 'merchant_id',
                    foreignField: '_id',
                    as: 'merchant',
                },
            },
            {
                $unwind: {
                    path: '$merchant',
                    preserveNullAndEmptyArrays: true,
                },
            },
            {
                $lookup: {
                    from: 'table_sessions',
                    localField: 'table_session_id',
                    foreignField: '_id',
                    as: 'table_session',
                },
            },
            {
                $unwind: {
                    path: '$table_session',
                    preserveNullAndEmptyArrays: true,
                },
            },
            {
                $lookup: {
                    from: 'tables',
                    localField: 'table_session.table_id',
                    foreignField: '_id',
                    as: 'table',
                },
            },
            {
                $unwind: {
                    path: '$table',
                    preserveNullAndEmptyArrays: true,
                },
            },
            {
                $project: {
                    _id: 0,
                    id: { $toString: '$_id' },
                    order_number: 1,
                    order_type: 1,
                    status: 1,
                    customer: {
                        id: {
                            $cond: [
                                { $ifNull: ['$customer._id', false] },
                                { $toString: '$customer._id' },
                                null,
                            ],
                        },
                        full_name: {
                            $ifNull: [
                                '$delivery_address.receiver_name',
                                { $ifNull: ['$customer.full_name', 'Khách hàng'] },
                            ],
                        },
                        phone: {
                            $ifNull: ['$delivery_address.receiver_phone', '$customer.phone'],
                        },
                    },
                    merchant: {
                        id: {
                            $cond: [
                                { $ifNull: ['$merchant._id', false] },
                                { $toString: '$merchant._id' },
                                null,
                            ],
                        },
                        name: { $ifNull: ['$merchant.name', 'N/A'] },
                        address: { $ifNull: ['$merchant.address', null] },
                    },
                    driver: {
                        $cond: [
                            { $ifNull: ['$driver._id', false] },
                            {
                                id: { $toString: '$driver._id' },
                                full_name: { $ifNull: ['$driver.full_name', ''] },
                                phone: '$driver.phone',
                            },
                            null,
                        ],
                    },
                    table: {
                        $cond: [
                            { $ifNull: ['$table._id', false] },
                            {
                                session_id: {
                                    $cond: [
                                        { $ifNull: ['$table_session._id', false] },
                                        { $toString: '$table_session._id' },
                                        null,
                                    ],
                                },
                                table_id: { $toString: '$table._id' },
                                table_number: '$table.table_number',
                                table_name: '$table.name',
                            },
                            null,
                        ],
                    },
                    items: { $ifNull: ['$items', []] },
                    status_history: { $ifNull: ['$status_history', []] },
                    delivery_address: { $ifNull: ['$delivery_address', null] },
                    order_note: { $ifNull: ['$order_note', ''] },
                    subtotal_before_discount: { $ifNull: ['$subtotal_before_discount', 0] },
                    delivery_fee_before_discount: { $ifNull: ['$delivery_fee_before_discount', 0] },
                    subtotal: { $ifNull: ['$subtotal', 0] },
                    delivery_fee: { $ifNull: ['$delivery_fee', 0] },
                    platform_fee: { $ifNull: ['$platform_fee', 0] },
                    total_amount: { $ifNull: ['$total_amount', 0] },
                    discounts: { $ifNull: ['$discounts', {}] },
                    applied_vouchers: { $ifNull: ['$applied_vouchers', []] },
                    payment_method: { $ifNull: ['$payment_method', null] },
                    payment_status: { $ifNull: ['$payment_status', null] },
                    paid_at: { $ifNull: ['$paid_at', null] },
                    cancel_reason: { $ifNull: ['$cancel_reason', null] },
                    cancelled_by: { $ifNull: ['$cancelled_by', null] },
                    driver_assigned_at: { $ifNull: ['$driver_assigned_at', null] },
                    driver_arrived_at: { $ifNull: ['$driver_arrived_at', null] },
                    estimated_prep_time: { $ifNull: ['$estimated_prep_time', 0] },
                    estimated_delivery_time: { $ifNull: ['$estimated_delivery_time', null] },
                    proof_of_delivery_images: { $ifNull: ['$proof_of_delivery_images', []] },
                    settlement: { $ifNull: ['$settlement', {}] },
                    created_at: 1,
                    updated_at: 1,
                },
            },
        ]);

        const row = rows[0];
        if (!row) {
            throw new NotFoundException('Order not found');
        }

        const changedByIds: Types.ObjectId[] = Array.isArray(row.status_history)
            ? row.status_history
                .map((x: any) => x?.changed_by)
                .filter((x: any) => x && Types.ObjectId.isValid(String(x)))
                .map((x: any) => new Types.ObjectId(String(x)))
            : [];

        const uniqueChangedByIds: Types.ObjectId[] = Array.from(
            new Set(changedByIds.map((x) => String(x))),
        ).map((id) => new Types.ObjectId(id));

        const changedUsers = uniqueChangedByIds.length
            ? await this.userModel
                .find({ _id: { $in: uniqueChangedByIds } })
                .select('_id full_name email')
                .lean()
            : [];

        const changedByMap = new Map(
            changedUsers.map((u: any) => [
                String(u._id),
                u.full_name || u.email || String(u._id),
            ]),
        );

        return {
            ...row,
            status_history: (row.status_history ?? []).map((x: any) => {
                const changedById = x?.changed_by ? String(x.changed_by) : null;
                return {
                    status: x?.status ?? '',
                    changed_at: x?.changed_at ?? null,
                    changed_by: changedById,
                    changed_by_name: changedById ? changedByMap.get(changedById) ?? null : null,
                    note: x?.note ?? null,
                };
            }),
        };
    }

    async forceCancelOrder(adminUserId: string, orderId: string, reason?: string) {
        await this.orderLifecycleService.adminForceCancelOrder(
            adminUserId,
            orderId,
            reason,
        );

        return this.getOrderDetail(orderId);
    }

    private pickTopResult(data: {
        orders: any[];
        merchants: any[];
        drivers: any[];
    }) {
        if (data.orders.length > 0) {
            return { type: 'order', ...data.orders[0] };
        }

        if (data.merchants.length > 0) {
            return { type: 'merchant', ...data.merchants[0] };
        }

        if (data.drivers.length > 0) {
            return { type: 'driver', ...data.drivers[0] };
        }

        return null;
    }

    async searchGlobal(query: AdminGlobalSearchQueryDto) {
        const q = (query.q ?? '').trim();
        const limit = this.parseLimit(query.limit, 5, 20);

        if (!q) {
            return {
                query: '',
                orders: [],
                merchants: [],
                drivers: [],
                top_result: null,
            };
        }

        const regex = new RegExp(this.escapeRegex(q), 'i');
        const qOid = Types.ObjectId.isValid(q) ? new Types.ObjectId(q) : null;

        const orderFilter: any = {
            $or: [
                { order_number: regex },
            ],
        };

        if (qOid) {
            orderFilter.$or.push({ _id: qOid });
        }

        const merchantFilter: any = {
            deleted_at: null,
            $or: [
                { name: regex },
                { email: regex },
                { phone: regex },
            ],
        };

        if (qOid) {
            merchantFilter.$or.push({ _id: qOid });
        }

        const [orders, merchants, drivers] = await Promise.all([
            this.orderModel
                .find(orderFilter)
                .sort({ created_at: -1 })
                .limit(limit)
                .select('_id order_number order_type status created_at')
                .lean(),
            this.merchantModel
                .find(merchantFilter)
                .sort({ created_at: -1 })
                .limit(limit)
                .select('_id name email phone approval_status')
                .lean(),
            this.driverProfileModel.aggregate([
                {
                    $lookup: {
                        from: 'users',
                        localField: 'user_id',
                        foreignField: '_id',
                        as: 'user',
                    },
                },
                {
                    $unwind: '$user',
                },
                {
                    $match: {
                        $or: [
                            { 'user.full_name': regex },
                            { 'user.phone': regex },
                            { 'user.email': regex },
                            { vehicle_plate: regex },
                            ...(qOid ? [{ 'user._id': qOid }] : []),
                        ],
                    },
                },
                { $sort: { updated_at: -1 } },
                { $limit: limit },
                {
                    $project: {
                        _id: 0,
                        user_id: { $toString: '$user._id' },
                        full_name: { $ifNull: ['$user.full_name', ''] },
                        phone: '$user.phone',
                        email: '$user.email',
                        verification_status: '$verification_status',
                        vehicle_plate: '$vehicle_plate',
                    },
                },
            ]),
        ]);

        const mappedOrders = orders.map((x: any) => ({
            id: String(x._id),
            order_number: x.order_number,
            order_type: x.order_type,
            status: x.status,
            created_at: x.created_at,
        }));

        const mappedMerchants = merchants.map((x: any) => ({
            id: String(x._id),
            name: x.name,
            email: x.email ?? null,
            phone: x.phone ?? null,
            approval_status: x.approval_status,
        }));

        const mappedDrivers = drivers.map((x: any) => ({
            user_id: x.user_id,
            full_name: x.full_name,
            phone: x.phone ?? null,
            email: x.email ?? null,
            verification_status: x.verification_status,
            vehicle_plate: x.vehicle_plate ?? null,
        }));

        const payload = {
            query: q,
            orders: mappedOrders,
            merchants: mappedMerchants,
            drivers: mappedDrivers,
        };

        return {
            ...payload,
            top_result: this.pickTopResult(payload),
        };
    }
}
