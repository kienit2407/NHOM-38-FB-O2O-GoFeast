/* eslint-disable @typescript-eslint/no-explicit-any */
import { create } from "zustand";
import {
    merchantOrderService,
    MerchantConfirmDineInCashResponse,
    MerchantInitiateDineInPaymentResponse,
    MerchantOrderStatus,
    MerchantOrderType,
    MerchantOrderView,
} from "@/service/merchant-order.service";

type TabStatus = MerchantOrderStatus | "all";
type TypeFilter = MerchantOrderType | "all";

interface MerchantOrderState {
    items: MerchantOrderView[];
    total: number;
    page: number;
    limit: number;

    loading: boolean;
    loadingDetail: boolean;
    acting: boolean;
    error: string | null;

    selectedTab: TabStatus;
    selectedType: TypeFilter;
    selectedOrder: MerchantOrderView | null;

    setTab: (tab: TabStatus) => void;
    setType: (type: TypeFilter) => void;
    setSelectedOrder: (order: MerchantOrderView | null) => void;

    fetchOrders: () => Promise<void>;
    fetchOrderDetail: (orderId: string) => Promise<void>;
    refreshOne: (orderId: string) => Promise<void>;

    confirmOrder: (orderId: string, note?: string) => Promise<MerchantOrderView | null>;
    rejectOrder: (orderId: string, reason?: string) => Promise<MerchantOrderView | null>;
    preparingOrder: (orderId: string, note?: string) => Promise<MerchantOrderView | null>;
    readyForPickupOrder: (orderId: string, note?: string) => Promise<MerchantOrderView | null>;
    retryDispatchOrder: (orderId: string, note?: string) => Promise<MerchantOrderView | null>;
    initiateDineInPayment: (
        orderId: string,
        paymentMethod: "vnpay" | "momo",
    ) => Promise<MerchantInitiateDineInPaymentResponse | null>;
    confirmDineInCashPayment: (
        orderId: string,
        receivedAmount: number,
        note?: string,
    ) => Promise<MerchantConfirmDineInCashResponse | null>;

    upsertOrder: (order: MerchantOrderView) => void;
    reset: () => void;
}

function upsert(items: MerchantOrderView[], next: MerchantOrderView) {
    const found = items.find((x) => x.id === next.id);
    if (!found) return [next, ...items];

    return items.map((x) => (x.id === next.id ? next : x));
}

export const useMerchantOrderStore = create<MerchantOrderState>((set, get) => ({
    items: [],
    total: 0,
    page: 1,
    limit: 20,

    loading: false,
    loadingDetail: false,
    acting: false,
    error: null,

    selectedTab: "all",
    selectedType: "all",
    selectedOrder: null,

    setTab: (tab) => set({ selectedTab: tab }),
    setType: (type) => set({ selectedType: type }),
    setSelectedOrder: (order) => set({ selectedOrder: order }),

    fetchOrders: async () => {
        set({ loading: true, error: null });

        try {
            const { selectedTab, selectedType, page, limit } = get();

            const data = await merchantOrderService.list({
                status: selectedTab === "all" ? undefined : selectedTab,
                orderType: selectedType === "all" ? undefined : selectedType,
                page,
                limit,
            });

            set({
                loading: false,
                items: data.items,
                total: data.total,
                page: data.page,
                limit: data.limit,
            });
        } catch (e: any) {
            set({
                loading: false,
                error: e?.message ?? "Không tải được danh sách đơn hàng",
            });
        }
    },

    fetchOrderDetail: async (orderId: string) => {
        set({ loadingDetail: true, error: null });

        try {
            const data = await merchantOrderService.detail(orderId);
            set((state) => ({
                loadingDetail: false,
                selectedOrder: data,
                items: upsert(state.items, data),
            }));
        } catch (e: any) {
            set({
                loadingDetail: false,
                error: e?.message ?? "Không tải được chi tiết đơn hàng",
            });
        }
    },

    refreshOne: async (orderId: string) => {
        try {
            const data = await merchantOrderService.detail(orderId);
            set((state) => ({
                items: upsert(state.items, data),
                selectedOrder:
                    state.selectedOrder?.id === orderId ? data : state.selectedOrder,
            }));
        } catch (_) { 
            //
        }
    },

    confirmOrder: async (orderId: string, note?: string) => {
        set({ acting: true, error: null });
        try {
            const data = await merchantOrderService.confirm(orderId, note);
            set((state) => ({
                acting: false,
                items: upsert(state.items, data),
                selectedOrder:
                    state.selectedOrder?.id === orderId ? data : state.selectedOrder,
            }));
            return data;
        } catch (e: any) {
            set({ acting: false, error: e?.message ?? "Xác nhận đơn thất bại" });
            return null;
        }
    },

    rejectOrder: async (orderId: string, reason?: string) => {
        set({ acting: true, error: null });
        try {
            const data = await merchantOrderService.reject(orderId, reason);
            set((state) => ({
                acting: false,
                items: upsert(state.items, data),
                selectedOrder:
                    state.selectedOrder?.id === orderId ? data : state.selectedOrder,
            }));
            return data;
        } catch (e: any) {
            set({ acting: false, error: e?.message ?? "Từ chối đơn thất bại" });
            return null;
        }
    },

    preparingOrder: async (orderId: string, note?: string) => {
        set({ acting: true, error: null });
        try {
            const data = await merchantOrderService.preparing(orderId, note);
            set((state) => ({
                acting: false,
                items: upsert(state.items, data),
                selectedOrder:
                    state.selectedOrder?.id === orderId ? data : state.selectedOrder,
            }));
            return data;
        } catch (e: any) {
            set({ acting: false, error: e?.message ?? "Cập nhật preparing thất bại" });
            return null;
        }
    },

    readyForPickupOrder: async (orderId: string, note?: string) => {
        set({ acting: true, error: null });
        try {
            const data = await merchantOrderService.readyForPickup(orderId, note);
            set((state) => ({
                acting: false,
                items: upsert(state.items, data),
                selectedOrder:
                    state.selectedOrder?.id === orderId ? data : state.selectedOrder,
            }));
            return data;
        } catch (e: any) {
            set({
                acting: false,
                error: e?.message ?? "Cập nhật ready_for_pickup thất bại",
            });
            return null;
        }
    },

    retryDispatchOrder: async (orderId: string, note?: string) => {
        set({ acting: true, error: null });
        try {
            const data = await merchantOrderService.retryDispatch(orderId, note);
            set((state) => ({
                acting: false,
                items: upsert(state.items, data),
                selectedOrder:
                    state.selectedOrder?.id === orderId ? data : state.selectedOrder,
            }));
            return data;
        } catch (e: any) {
            set({
                acting: false,
                error: e?.message ?? "Tìm tài xế thủ công thất bại",
            });
            return null;
        }
    },

    initiateDineInPayment: async (
        orderId: string,
        paymentMethod: "vnpay" | "momo",
    ) => {
        set({ acting: true, error: null });
        try {
            const data = await merchantOrderService.initiateDineInPayment(
                orderId,
                paymentMethod,
            );
            set((state) => ({
                acting: false,
                items: upsert(state.items, data.order),
                selectedOrder:
                    state.selectedOrder?.id === orderId ? data.order : state.selectedOrder,
            }));
            return data;
        } catch (e: any) {
            set({
                acting: false,
                error: e?.message ?? "Khởi tạo thanh toán dine-in thất bại",
            });
            return null;
        }
    },

    confirmDineInCashPayment: async (
        orderId: string,
        receivedAmount: number,
        note?: string,
    ) => {
        set({ acting: true, error: null });
        try {
            const data = await merchantOrderService.confirmDineInCashPayment(
                orderId,
                receivedAmount,
                note,
            );
            set((state) => ({
                acting: false,
                items: upsert(state.items, data.order),
                selectedOrder:
                    state.selectedOrder?.id === orderId ? data.order : state.selectedOrder,
            }));
            return data;
        } catch (e: any) {
            set({
                acting: false,
                error: e?.message ?? "Xác nhận thanh toán tiền mặt thất bại",
            });
            return null;
        }
    },

    upsertOrder: (order) =>
        set((state) => ({
            items: upsert(state.items, order),
            selectedOrder:
                state.selectedOrder?.id === order.id ? order : state.selectedOrder,
        })),

    reset: () =>
        set({
            items: [],
            total: 0,
            page: 1,
            limit: 20,
            loading: false,
            loadingDetail: false,
            acting: false,
            error: null,
            selectedTab: "all",
            selectedType: "all",
            selectedOrder: null,
        }),
}));
