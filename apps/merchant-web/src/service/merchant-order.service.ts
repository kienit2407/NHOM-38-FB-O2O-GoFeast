/* eslint-disable @typescript-eslint/no-explicit-any */
import { API } from "@/lib/api";

export type MerchantOrderStatus =
    | "pending"
    | "confirmed"
    | "preparing"
    | "ready_for_pickup"
    | "driver_assigned"
    | "driver_arrived"
    | "picked_up"
    | "delivering"
    | "delivered"
    | "completed"
    | "cancelled"
    | "served";

export type MerchantOrderType = "delivery" | "dine_in";

export interface MerchantOrderItem {
    id: string;
    item_type: string;
    name: string;
    product_name: string;
    topping_name: string | null;
    quantity: number;
    unit_price: number;
    base_price: number | null;
    item_total: number;
    selected_options: Array<{
        option_name: string;
        choice_name: string;
        price_modifier: number;
    }>;
    selected_toppings: Array<{
        topping_id: string | null;
        topping_name: string;
        quantity: number;
        unit_price: number;
    }>;
    note: string;
}

export interface MerchantOrderView {
    id: string;
    order_id: string;
    order_number: string;
    order_type: MerchantOrderType;
    status: MerchantOrderStatus;
    display_status?: string;
    display_status_label?: string | null;

    customer: {
        id: string | null;
        full_name: string;
        phone: string | null;
    };

    driver: null | {
        id: string;
        full_name: string;
        phone: string | null;
        avatar_url: string | null;
    };

    delivery_address: null | {
        address: string | null;
        receiver_name: string | null;
        receiver_phone: string | null;
        note: string | null;
    };

    table_session_id: string | null;

    items: MerchantOrderItem[];

    subtotal: number;
    delivery_fee: number;
    platform_fee: number;
    total_amount: number;

    payment_method: string | null;
    payment_status: string | null;

    order_note: string;
    cancel_reason: string | null;
    cancelled_by: string | null;

    driver_assigned_at: string | null;
    estimated_delivery_time: string | null;

    created_at: string | null;
    updated_at: string | null;

    actions: {
        can_confirm: boolean;
        can_reject: boolean;
        can_preparing: boolean;
        can_ready_for_pickup: boolean;
        can_manual_dispatch: boolean;
        can_settle_payment: boolean;
    };
}

export interface MerchantOrderPaymentResult {
    payment_id: string;
    status: string;
    method: string;
    amount: number;
}

export interface MerchantOrderPaymentAction {
    type: string;
    url: string;
}

export interface MerchantInitiateDineInPaymentResponse {
    order: MerchantOrderView;
    payment: MerchantOrderPaymentResult | null;
    payment_action: MerchantOrderPaymentAction | null;
    already_paid: boolean;
}

export interface MerchantConfirmDineInCashResponse {
    order: MerchantOrderView;
    payment: MerchantOrderPaymentResult | null;
    received_amount: number;
    change_amount: number;
}

export interface MerchantOrderListResponse {
    items: MerchantOrderView[];
    total: number;
    page: number;
    limit: number;
}

export const merchantOrderService = {
    async list(params?: {
        status?: string;
        orderType?: string;
        page?: number;
        limit?: number;
    }): Promise<MerchantOrderListResponse> {
        const res = await API.get("/merchant/orders", {
            params: {
                status: params?.status,
                order_type: params?.orderType,
                page: params?.page ?? 1,
                limit: params?.limit ?? 20,
            },
        });

        return res.data.data;
    },

    async detail(orderId: string): Promise<MerchantOrderView> {
        const res = await API.get(`/merchant/orders/${orderId}`);
        return res.data.data;
    },

    async confirm(orderId: string, note?: string): Promise<MerchantOrderView> {
        const res = await API.patch(`/merchant/orders/${orderId}/confirm`, { note });
        return res.data.data;
    },

    async reject(orderId: string, reason?: string): Promise<MerchantOrderView> {
        const res = await API.patch(`/merchant/orders/${orderId}/reject`, { reason });
        return res.data.data;
    },

    async preparing(orderId: string, note?: string): Promise<MerchantOrderView> {
        const res = await API.patch(`/merchant/orders/${orderId}/preparing`, { note });
        return res.data.data;
    },

    async readyForPickup(orderId: string, note?: string): Promise<MerchantOrderView> {
        const res = await API.patch(`/merchant/orders/${orderId}/ready-for-pickup`, { note });
        return res.data.data;
    },

    async retryDispatch(orderId: string, note?: string): Promise<MerchantOrderView> {
        const res = await API.patch(`/merchant/orders/${orderId}/dispatch/retry`, { note });
        return res.data.data;
    },

    async initiateDineInPayment(
        orderId: string,
        paymentMethod: "vnpay" | "momo",
    ): Promise<MerchantInitiateDineInPaymentResponse> {
        const res = await API.patch(`/merchant/orders/${orderId}/payments/initiate`, {
            payment_method: paymentMethod,
        });
        return res.data.data;
    },

    async confirmDineInCashPayment(
        orderId: string,
        receivedAmount: number,
        note?: string,
    ): Promise<MerchantConfirmDineInCashResponse> {
        const res = await API.patch(`/merchant/orders/${orderId}/payments/cash/confirm`, {
            received_amount: receivedAmount,
            note,
        });
        return res.data.data;
    },
};
