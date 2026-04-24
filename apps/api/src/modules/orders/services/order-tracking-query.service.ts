import {
    BadRequestException,
    Injectable,
    NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';

import { Order, OrderDocument } from '../schemas/order.schema';
import {
    Merchant,
    MerchantDocument,
} from 'src/modules/merchants/schemas/merchant.schema';
import {
    DriverProfile,
    DriverProfileDocument,
} from 'src/modules/drivers/schemas/driver-profile.schema';
import { User, UserDocument } from 'src/modules/users/schemas/user.schema';

@Injectable()
export class OrderTrackingQueryService {
    constructor(
        @InjectModel(Order.name)
        private readonly orderModel: Model<OrderDocument>,
        @InjectModel(Merchant.name)
        private readonly merchantModel: Model<MerchantDocument>,
        @InjectModel(DriverProfile.name)
        private readonly driverProfileModel: Model<DriverProfileDocument>,
        @InjectModel(User.name)
        private readonly userModel: Model<UserDocument>,
    ) { }

    private oid(id: string, name = 'id') {
        if (!Types.ObjectId.isValid(id)) {
            throw new BadRequestException(`Invalid ${name}`);
        }
        return new Types.ObjectId(id);
    }

    private extractLatLng(location: any): { lat: number | null; lng: number | null } {
        const coords = location?.coordinates;
        if (!Array.isArray(coords) || coords.length !== 2) {
            return { lat: null, lng: null };
        }

        return {
            lng: Number(coords[0]),
            lat: Number(coords[1]),
        };
    }

    private computeEta(order: any) {
        const etaAt = order?.estimated_delivery_time
            ? new Date(order.estimated_delivery_time)
            : null;

        if (!etaAt) {
            return {
                eta_at: null,
                eta_min: null,
            };
        }

        const diffMs = etaAt.getTime() - Date.now();
        const etaMin = Math.max(0, Math.ceil(diffMs / 60000));

        return {
            eta_at: etaAt.toISOString(),
            eta_min: etaMin,
        };
    }

    async getCustomerTracking(userId: string, orderId: string) {
        const order = await this.orderModel.findById(this.oid(orderId, 'orderId')).lean();
        if (!order) {
            throw new NotFoundException('Order not found');
        }

        if (String(order.customer_id) !== String(userId)) {
            throw new NotFoundException('Order not found');
        }

        const merchant = await this.merchantModel
            .findById(order.merchant_id)
            .select('_id name address location')
            .lean();

        if (!merchant) {
            throw new NotFoundException('Merchant not found');
        }

        const merchantLatLng = this.extractLatLng(merchant.location);
        const deliveryLatLng = this.extractLatLng(order.delivery_address?.location);

        let driverUser: any = null;
        let driverProfile: any = null;

        if (order.driver_id) {
            driverUser = await this.userModel
                .findById(order.driver_id)
                .select('_id full_name phone avatar_url')
                .lean();

            driverProfile = await this.driverProfileModel
                .findOne({ user_id: order.driver_id })
                .select('current_location last_location_update')
                .lean();
        }

        const driverLatLng = this.extractLatLng(driverProfile?.current_location);
        const eta = this.computeEta(order);
        const isDineIn = order.order_type === 'dine_in';

        return {
            order_id: String(order._id),
            order_number: order.order_number,
            status: order.status,
            order_type: order.order_type,
            driver_assigned: isDineIn ? false : Boolean(order.driver_id),

            eta_at: eta.eta_at,
            eta_min: eta.eta_min,

            merchant: {
                id: String(merchant._id),
                name: merchant.name ?? '',
                address: merchant.address ?? null,
                lat: merchantLatLng.lat,
                lng: merchantLatLng.lng,
            },

            driver: !driverUser
                ? null
                : {
                    id: String(driverUser._id),
                    name: driverUser.full_name ?? '',
                    phone: driverUser.phone ?? null,
                    address: null,
                    lat: driverLatLng.lat,
                    lng: driverLatLng.lng,
                    last_location_update: driverProfile?.last_location_update
                        ? new Date(driverProfile.last_location_update).toISOString()
                        : null,
                    avatar_url: driverUser.avatar_url ?? null,
                },

            customer_delivery: isDineIn
                ? null
                : {
                    address: order.delivery_address?.address ?? null,
                    lat: deliveryLatLng.lat,
                    lng: deliveryLatLng.lng,
                },

            payment: {
                method: order.payment_method,
                status: order.payment_status,
            },

            summary: {
                total_amount: Number(order.total_amount ?? 0),
                delivery_fee: Number(order.delivery_fee ?? 0),
                subtotal: Number(order.subtotal ?? 0),
            },

            proof_of_delivery_images: order.proof_of_delivery_images ?? [],
            created_at: order.created_at ? new Date(order.created_at).toISOString() : null,
            updated_at: order.updated_at ? new Date(order.updated_at).toISOString() : null,
        };
    }
}
