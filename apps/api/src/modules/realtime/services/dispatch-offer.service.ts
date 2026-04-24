import { Injectable } from '@nestjs/common';
import { RealtimeEvents } from '../realtime.events';

type OfferStatus = 'pending' | 'accepted' | 'expired' | 'cancelled';

export interface StartDispatchOfferInput {
    orderId: string;
    customerUserId: string;
    merchantId: string;
    candidateDriverIds: string[];
    payload?: Record<string, any>;
}

export interface DispatchOfferLifecycleHandler {
    onDriverAcceptedOffer(params: {
        orderId: string;
        driverId: string;
        offer?: any;
    }): Promise<void>;

    onDispatchOfferExpired?(params: {
        orderId: string;
        reason: string;
        offer?: any;
    }): Promise<{
        willRetry: boolean;
    } | void>;
}

interface ActiveDispatchOffer {
    orderId: string;
    customerUserId: string;
    merchantId: string;
    driverIds: string[];
    status: OfferStatus;
    acceptedDriverId?: string;
    createdAt: number;
    expiresAt: number;
    timeout?: NodeJS.Timeout;
    rejectedDriverIds: Set<string>;
    payload?: Record<string, any>;
}

@Injectable()
export class DispatchOfferService {
    private readonly OFFER_TTL_MS = 20_000;

    private gateway: any;
    private lifecycleHandler?: DispatchOfferLifecycleHandler;
    private readonly offers = new Map<string, ActiveDispatchOffer>();

    attachGateway(gateway: any) {
        this.gateway = gateway;
    }

    attachLifecycleHandler(handler: DispatchOfferLifecycleHandler) {
        this.lifecycleHandler = handler;
    }

    getOffer(orderId: string) {
        return this.offers.get(orderId) ?? null;
    }

    startOffer(input: StartDispatchOfferInput) {
        const existing = this.offers.get(input.orderId);
        if (existing?.timeout) {
            clearTimeout(existing.timeout);
        }

        const now = Date.now();
        const expiresAt = now + this.OFFER_TTL_MS;

        const offer: ActiveDispatchOffer = {
            orderId: input.orderId,
            customerUserId: input.customerUserId,
            merchantId: input.merchantId,
            driverIds: [...new Set(input.candidateDriverIds)],
            status: 'pending',
            createdAt: now,
            expiresAt,
            rejectedDriverIds: new Set<string>(),
            payload: input.payload ?? {},
        };

        offer.timeout = setTimeout(() => {
            void this.expireOffer(input.orderId);
        }, this.OFFER_TTL_MS);

        this.offers.set(input.orderId, offer);

        const nowIso = new Date().toISOString();
        const offerExpiresAt = new Date(expiresAt).toISOString();

        this.gateway?.emitToCustomer(
            offer.customerUserId,
            RealtimeEvents.CUSTOMER_DISPATCH_SEARCHING,
            {
                orderId: offer.orderId,
                status: 'searching_driver',
                candidateCount: offer.driverIds.length,
                offerExpiresAt,
                message: 'Hệ thống đang tìm tài xế gần quán cho đơn của bạn',
                updatedAt: nowIso,
            },
        );

        const wave = Number(offer.payload?.wave ?? 1);

        this.gateway?.emitToMerchant(
            offer.merchantId,
            RealtimeEvents.MERCHANT_ORDER_STATUS,
            {
                orderId: offer.orderId,
                status: wave === 1 ? 'dispatch_searching' : 'dispatch_retrying',
                message:
                    wave === 1
                        ? 'Hệ thống đang tìm tài xế cho đơn này'
                        : `Đang thử tìm tài xế ở đợt ${wave}`,
                updatedAt: nowIso,
                ...offer.payload,
            },
        );
        for (const driverId of offer.driverIds) {
            this.gateway?.emitToDriver(driverId, RealtimeEvents.DRIVER_NEW_ORDER_OFFER, {
                orderId: offer.orderId,
                offerExpiresAt,
                message: 'Bạn vừa nhận được một đề nghị đơn hàng mới',
                updatedAt: nowIso,
                ...offer.payload,
            });
        }

        return {
            ok: true,
            orderId: offer.orderId,
            expiresAt: offer.expiresAt,
        };
    }

    async acceptOffer(params: { orderId: string; driverId: string }) {
        const offer = this.offers.get(params.orderId);
        if (!offer) {
            return { ok: false, reason: 'offer_not_found' as const };
        }

        if (offer.status !== 'pending') {
            return { ok: false, reason: 'offer_not_pending' as const };
        }

        if (!offer.driverIds.includes(params.driverId)) {
            return { ok: false, reason: 'driver_not_candidate' as const };
        }

        try {
            await this.lifecycleHandler?.onDriverAcceptedOffer({
                orderId: offer.orderId,
                driverId: params.driverId,
                offer,
            });
        } catch (e: any) {
            return {
                ok: false,
                reason: 'accept_failed' as const,
                message: e?.message ?? 'Driver accept failed',
            };
        }

        offer.status = 'accepted';
        offer.acceptedDriverId = params.driverId;

        if (offer.timeout) {
            clearTimeout(offer.timeout);
            offer.timeout = undefined;
        }

        const otherDriverIds = offer.driverIds.filter((x) => x !== params.driverId);
        const nowIso = new Date().toISOString();

        this.gateway?.emitToDriver(
            params.driverId,
            RealtimeEvents.DRIVER_OFFER_ACCEPTED,
            {
                orderId: offer.orderId,
                status: 'driver_assigned',
                message: 'Bạn đã nhận đơn thành công',
                updatedAt: nowIso,
            },
        );

        this.gateway?.emitToDrivers(
            otherDriverIds,
            RealtimeEvents.DRIVER_OFFER_CANCELLED,
            {
                orderId: offer.orderId,
                reason: 'accepted_by_other_driver',
                message: 'Đơn đã được tài xế khác nhận',
                updatedAt: nowIso,
            },
        );

        this.gateway?.emitToCustomer(
            offer.customerUserId,
            RealtimeEvents.CUSTOMER_ORDER_STATUS,
            {
                orderId: offer.orderId,
                status: 'driver_assigned',
                driverId: params.driverId,
                merchantId: offer.merchantId,
                message: 'Đơn hàng của bạn đã có tài xế nhận',
                updatedAt: nowIso,
            },
        );

        this.gateway?.emitToMerchant(
            offer.merchantId,
            RealtimeEvents.MERCHANT_ORDER_STATUS,
            {
                orderId: offer.orderId,
                status: 'driver_assigned',
                driverId: params.driverId,
                message: 'Đơn đã có tài xế nhận',
                updatedAt: nowIso,
            },
        );

        this.offers.delete(params.orderId);

        return {
            ok: true,
            orderId: offer.orderId,
            driverId: params.driverId,
        };
    }

    rejectOffer(params: { orderId: string; driverId: string }) {
        const offer = this.offers.get(params.orderId);
        if (!offer) {
            return { ok: false, reason: 'offer_not_found' as const };
        }

        if (offer.status !== 'pending') {
            return { ok: false, reason: 'offer_not_pending' as const };
        }

        if (!offer.driverIds.includes(params.driverId)) {
            return { ok: false, reason: 'driver_not_candidate' as const };
        }

        offer.rejectedDriverIds.add(params.driverId);

        this.gateway?.emitToDriver(
            params.driverId,
            RealtimeEvents.DRIVER_OFFER_CANCELLED,
            {
                orderId: offer.orderId,
                reason: 'rejected_by_driver',
                message: 'Bạn đã bỏ qua đơn này',
                updatedAt: new Date().toISOString(),
            },
        );

        const allRejected = offer.rejectedDriverIds.size >= offer.driverIds.length;
        if (allRejected) {
            void this.expireOffer(offer.orderId, 'all_rejected');
        }

        return { ok: true };
    }

    cancelOffer(orderId: string, reason = 'cancelled_by_system') {
        const offer = this.offers.get(orderId);
        if (!offer) return;

        if (offer.timeout) {
            clearTimeout(offer.timeout);
            offer.timeout = undefined;
        }

        offer.status = 'cancelled';
        const nowIso = new Date().toISOString();

        this.gateway?.emitToDrivers(
            offer.driverIds,
            RealtimeEvents.DRIVER_OFFER_CANCELLED,
            {
                orderId: offer.orderId,
                reason,
                message: 'Đề nghị đơn hàng đã bị hủy',
                updatedAt: nowIso,
            },
        );

        this.gateway?.emitToCustomer(
            offer.customerUserId,
            RealtimeEvents.CUSTOMER_ORDER_CANCELLED,
            {
                orderId: offer.orderId,
                status: 'cancelled',
                cancelledBy: 'system',
                reason,
                message: 'Đơn hàng đã bị hủy',
                updatedAt: nowIso,
            },
        );

        this.gateway?.emitToMerchant(
            offer.merchantId,
            RealtimeEvents.MERCHANT_DISPATCH_CANCELLED,
            {
                orderId: offer.orderId,
                status: 'dispatch_cancelled',
                reason,
                message: 'Quá trình điều phối đã bị hủy',
                updatedAt: nowIso,
            },
        );

        this.offers.delete(orderId);
    }

    async expireOffer(orderId: string, reason = 'offer_expired') {
        const offer = this.offers.get(orderId);
        if (!offer) return;

        if (offer.status !== 'pending') {
            this.offers.delete(orderId);
            return;
        }

        let lifecycleResult: { willRetry: boolean } | void = undefined;

        try {
            lifecycleResult = await this.lifecycleHandler?.onDispatchOfferExpired?.({
                orderId: offer.orderId,
                reason,
                offer,
            });
        } catch (e) { }

        offer.status = 'expired';

        // đang retry wave tiếp -> không emit expired cho customer/merchant
        if (lifecycleResult?.willRetry) {
            this.offers.delete(orderId);
            return;
        }

        const nowIso = new Date().toISOString();

        this.gateway?.emitToDrivers(
            offer.driverIds,
            RealtimeEvents.DRIVER_OFFER_EXPIRED,
            {
                orderId: offer.orderId,
                reason,
                message: 'Đề nghị đơn hàng đã hết hạn',
                updatedAt: nowIso,
            },
        );

        this.gateway?.emitToCustomer(
            offer.customerUserId,
            RealtimeEvents.CUSTOMER_DISPATCH_EXPIRED,
            {
                orderId: offer.orderId,
                status: 'dispatch_expired',
                reason,
                message: 'Hệ thống chưa tìm được tài xế phù hợp cho đơn của bạn',
                updatedAt: nowIso,
            },
        );

        this.gateway?.emitToMerchant(
            offer.merchantId,
            RealtimeEvents.MERCHANT_DISPATCH_EXPIRED,
            {
                orderId: offer.orderId,
                status: 'dispatch_expired',
                reason,
                message: 'Đơn hiện chưa tìm được tài xế phù hợp',
                updatedAt: nowIso,
            },
        );

        this.offers.delete(orderId);
    }
}
