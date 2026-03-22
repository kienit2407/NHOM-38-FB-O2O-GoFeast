import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import {
    DriverProfile,
    DriverProfileDocument,
    DriverVerificationStatus,
} from '../schemas/driver-profile.schema';
import { OrderLifecycleService } from 'src/modules/orders/services/order-lifecycle.service';
import { DriverLocationRelayService } from './driver-location-relay.service';
import { User, UserDocument } from 'src/modules/users/schemas/user.schema';
import { UpdateDriverProfileDto } from '../dtos/update-driver-profile.dto';

type UpsertDriverProfilePatch = Partial<Pick<
    DriverProfile,
    | 'id_card_number'
    | 'id_card_front_url'
    | 'id_card_back_url'
    | 'license_number'
    | 'license_type'
    | 'license_image_url'
    | 'license_expiry'
    | 'vehicle_brand'
    | 'vehicle_model'
    | 'vehicle_plate'
    | 'vehicle_image_url'
>>;

@Injectable()
export class DriverProfilesService {
    constructor(
        @InjectModel(DriverProfile.name) private readonly model: Model<DriverProfileDocument>,
        private readonly driverLocationRelayService: DriverLocationRelayService,
        @InjectModel(User.name)
        private readonly userModel: Model<UserDocument>,
    ) { }
    private async getUserOrThrow(userId: string) {
        const uid = new Types.ObjectId(userId);

        const user = await this.userModel.findOne({
            _id: uid,
            role: 'driver',
            deleted_at: null,
        });

        if (!user) throw new NotFoundException('Driver user not found');
        return user;
    }

    private async getDriverProfileOrThrow(userId: string) {
        const uid = new Types.ObjectId(userId);

        const profile = await this.model.findOne({ user_id: uid });
        if (!profile) throw new NotFoundException('Driver profile not found');
        return profile;
    }
    async getMyProfile(userId: string) {
        const user = await this.getUserOrThrow(userId);
        const profile = await this.ensureForUser(userId);
        return this.toProfileResponse(user, profile);
    }
    async updateMyProfile(userId: string, dto: UpdateDriverProfileDto) {
        const uid = new Types.ObjectId(userId);

        await this.getUserOrThrow(userId);
        await this.ensureForUser(userId);

        const userPatch: Record<string, any> = {};
        const driverPatch: Record<string, any> = {};

        if (dto.fullName !== undefined) {
            userPatch.full_name = dto.fullName;
        }

        if (dto.phone !== undefined) {
            if (dto.phone) {
                const existed = await this.userModel.findOne({
                    _id: { $ne: uid },
                    phone: dto.phone,
                    deleted_at: null,
                });

                if (existed) {
                    throw new ConflictException('Phone already in use');
                }
            }

            userPatch.phone = dto.phone;
        }

        if (dto.gender !== undefined) {
            userPatch.gender = dto.gender;
        }

        if (dto.dateOfBirth !== undefined) {
            userPatch.date_of_birth = dto.dateOfBirth
                ? new Date(dto.dateOfBirth)
                : null;
        }

        if (dto.avatarUrl !== undefined) {
            userPatch.avatar_url = dto.avatarUrl;
        }

        if (dto.bankName !== undefined) {
            driverPatch.bank_name = dto.bankName;
        }

        if (dto.bankAccountName !== undefined) {
            driverPatch.bank_account_name = dto.bankAccountName;
        }

        if (dto.bankAccountNumber !== undefined) {
            driverPatch.bank_account_number = dto.bankAccountNumber;
        }

        if (Object.keys(userPatch).length > 0) {
            await this.userModel.findByIdAndUpdate(uid, { $set: userPatch });
        }

        if (Object.keys(driverPatch).length > 0) {
            await this.model.findOneAndUpdate(
                { user_id: uid },
                { $set: driverPatch },
                { new: true, upsert: true },
            );
        }

        const updatedUser = await this.getUserOrThrow(userId);
        const updatedProfile = await this.getDriverProfileOrThrow(userId);

        return this.toProfileResponse(updatedUser, updatedProfile);
    }S
    private toProfileResponse(user: any, profile: any) {
        return {
            id: String(user._id),
            full_name: user.full_name ?? null,
            phone: user.phone ?? null,
            email: user.email ?? null,
            gender: user.gender ?? null,
            date_of_birth: user.date_of_birth ?? null,
            avatar_url: user.avatar_url ?? null,

            driver_profile: {
                verification_status: profile.verification_status ?? null,
                is_verified:
                    profile.verification_status === DriverVerificationStatus.APPROVED,
                accept_food_orders: profile.accept_food_orders ?? false,

                bank_name: profile.bank_name ?? null,
                bank_account_name: profile.bank_account_name ?? null,
                bank_account_number: profile.bank_account_number ?? null,

                current_location: profile.current_location ?? null,
                last_location_update: profile.last_location_update ?? null,
                updated_at: profile.updated_at ?? null,
            },
        };
    }
    async findByUserId(userId: string) {
        return this.model.findOne({ user_id: new Types.ObjectId(userId) });
    }
    async listForAdmin(params?: { scope?: 'list' | 'all'; limit?: number }) {
        const scope = params?.scope ?? 'list';
        const limit = params?.limit ?? 2000;

        const filter: any = {};
        if (scope === 'list') {
            filter.verification_status = { $ne: DriverVerificationStatus.DRAFT };
        }

        const rows = await this.model
            .find(filter)
            .sort({ submitted_at: -1, created_at: -1 })
            .limit(limit)
            .populate({
                path: 'user_id',
                select: 'email phone full_name status role avatar_url created_at updated_at',
                match: { role: 'driver', deleted_at: null },
            })
            .exec();

        return rows.filter((r: any) => r.user_id);
    }
    async ensureForUser(userId: string) {
        const uid = new Types.ObjectId(userId);
        return this.model.findOneAndUpdate(
            { user_id: uid },
            {
                $setOnInsert: {
                    user_id: uid,
                    verification_status: DriverVerificationStatus.DRAFT,
                    verification_reasons: [],
                    accept_food_orders: true,
                    total_deliveries: 0,
                    total_earnings: 0,
                    average_rating: 0,
                },
            },
            { upsert: true, new: true },
        );
    }

    async submit(userId: string, patch: UpsertDriverProfilePatch) {
        const uid = new Types.ObjectId(userId);
        return this.model.findOneAndUpdate(
            { user_id: uid },
            {
                $set: {
                    ...patch,
                    verification_status: DriverVerificationStatus.PENDING,
                    submitted_at: new Date(),
                    verification_reasons: [],
                    verification_note: null,
                    verified_at: null,
                    verified_by: null,
                },
            },
            { upsert: true, new: true },
        );
    }

    async adminSetVerification(params: {
        userId: string;
        status: DriverVerificationStatus.PENDING | DriverVerificationStatus.APPROVED | DriverVerificationStatus.REJECTED;
        reasons?: string[];
        note?: string | null;
        verifiedBy: string;
    }) {
        const uid = new Types.ObjectId(params.userId);

        return this.model.findOneAndUpdate(
            { user_id: uid },
            {
                $set: {
                    verification_status: params.status,
                    verification_reasons: params.reasons ?? [],
                    verification_note: params.note ?? null,
                    verified_at: new Date(),
                    verified_by: new Types.ObjectId(params.verifiedBy),
                },
            },
            { new: true },
        );
    }

    async listPending(limit = 50) {
        return this.model
            .find({ verification_status: DriverVerificationStatus.PENDING })
            .sort({ submitted_at: -1 })
            .limit(limit)
            .populate('user_id');
    }
    async setAvailability(userId: string, acceptFoodOrders: boolean) {
        const uid = new Types.ObjectId(userId);

        const profile = await this.model.findOne({ user_id: uid });
        if (!profile) {
            throw new NotFoundException('Driver profile not found');
        }

        if (profile.verification_status !== DriverVerificationStatus.APPROVED) {
            throw new ForbiddenException('Driver is not approved');
        }

        return this.model.findOneAndUpdate(
            { user_id: uid },
            {
                $set: {
                    accept_food_orders: acceptFoodOrders,
                },
            },
            { new: true },
        );
    }

    async updateCurrentLocation(params: {
        userId: string;
        lat: number;
        lng: number;
    }) {
        const uid = new Types.ObjectId(params.userId);

        const profile = await this.model.findOne({ user_id: uid });
        if (!profile) {
            throw new NotFoundException('Driver profile not found');
        }

        if (profile.verification_status !== DriverVerificationStatus.APPROVED) {
            throw new ForbiddenException('Driver is not approved');
        }

        const updated = await this.model.findOneAndUpdate(
            { user_id: uid },
            {
                $set: {
                    current_location: {
                        type: 'Point',
                        coordinates: [params.lng, params.lat],
                    },
                    last_location_update: new Date(),
                },
            },
            { new: true },
        );

        await this.driverLocationRelayService.relayActiveOrderLocation({
            driverUserId: params.userId,
            lat: params.lat,
            lng: params.lng,
        });

        return updated;
    }
    async getLiveState(userId: string) {
        const uid = new Types.ObjectId(userId);

        const profile = await this.model
            .findOne({ user_id: uid })
            .select(
                'user_id verification_status accept_food_orders current_location last_location_update updated_at',
            )
            .lean();

        if (!profile) {
            throw new NotFoundException('Driver profile not found');
        }

        return profile;
    }

    async findNearbyAvailableApproved(params: {
        lat: number;
        lng: number;
        radiusMeters?: number;
        limit?: number;
    }) {
        const radiusMeters = params.radiusMeters ?? 5000;
        const limit = params.limit ?? 20;

        return this.model
            .find({
                verification_status: DriverVerificationStatus.APPROVED,
                accept_food_orders: true,
                current_location: {
                    $near: {
                        $geometry: {
                            type: 'Point',
                            coordinates: [params.lng, params.lat],
                        },
                        $maxDistance: radiusMeters,
                    },
                },
            })
            .limit(limit)
            .select(
                'user_id current_location last_location_update accept_food_orders verification_status',
            )
            .lean();
    }
}