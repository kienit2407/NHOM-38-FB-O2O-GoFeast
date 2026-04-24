/* eslint-disable @typescript-eslint/no-explicit-any */
import { useEffect } from "react";
import { merchantSocketService } from "@/service/merchant-socket.service";
import { useMerchantSocketStore } from "@/store/merchantSocketStore";
import { useMerchantAuth } from "@/store/authStore";
import { useMerchantOrderStore } from "@/store/merchantOrderStore";
import { useMerchantReviewsStore } from "@/store/merchantReviewsStore";
import { useTableStore } from "@/store/tableStore";

function resolveMerchantId(user: any, merchant: any): string | null {
    return (
        merchant?._id?.toString?.() ||
        merchant?.id?.toString?.() ||
        user?.merchant?._id?.toString?.() ||
        user?.merchant?.id?.toString?.() ||
        user?.merchant_id?.toString?.() ||
        user?.merchantId?.toString?.() ||
        null
    );
}

function buildNotification(input: {
    type:
    | "new_order"
    | "order_status"
    | "dispatch_expired"
    | "dispatch_cancelled"
    | "review_received"
    | "system";
    orderId: string;
    title: string;
    message: string;
    raw?: any;
}) {
    return {
        id: `${input.type}_${input.orderId}_${Date.now()}`,
        type: input.type,
        orderId: input.orderId,
        title: input.title,
        message: input.message,
        createdAt: Date.now(),
        read: false,
        raw: input.raw,
    };
}

export function useMerchantSocketBootstrap() {
    const user = useMerchantAuth((s) => s.user);
    const merchant = useMerchantAuth((s) => s.merchant);
    const accessToken = useMerchantAuth((s) => s.accessToken);
    const isAuthenticated = useMerchantAuth((s) => s.isAuthenticated());

    const setConnected = useMerchantSocketStore((s) => s.setConnected);
    const pushNotification = useMerchantSocketStore((s) => s.pushNotification);
    const upsertOrder = useMerchantSocketStore((s) => s.upsertOrder);
    const reset = useMerchantSocketStore((s) => s.reset);
    const refreshOne = useMerchantOrderStore((s) => s.refreshOne);
    const fetchTables = useTableStore((s) => s.fetchTables);

    useEffect(() => {
        if (!isAuthenticated || !user || !accessToken) {
            merchantSocketService.disconnect();
            reset();
            return;
        }

        const merchantId = resolveMerchantId(user, merchant);
        const socket = merchantSocketService.connect(accessToken);

        const handleConnect = () => {
            setConnected(true);
            if (merchantId) {
                merchantSocketService.joinMerchantRoom(merchantId);
            }
        };

        const handleDisconnect = () => {
            setConnected(false);
        };

        const handleConnectError = (err: any) => {
            console.error("merchant socket connect_error", err);
            setConnected(false);
        };

        const handleOrderNew = (data: any) => {
            const orderId = String(data?.orderId ?? "");
            if (!orderId) return;

            void refreshOne(orderId);

            upsertOrder({
                orderId,
                status: data?.status ?? "pending",
                type: data?.type ?? data?.orderType ?? data?.order_type,
                tableNumber: data?.tableNumber ?? data?.table_number ?? null,
                merchantId:
                    data?.merchantId ?? data?.merchant_id ?? merchantId ?? undefined,
                branchId: data?.branchId ?? data?.branch_id,
                updatedAt: Date.now(),
                raw: data,
            });

            const isDineIn =
                data?.type === "dine_in" ||
                data?.orderType === "dine_in" ||
                data?.order_type === "dine_in";

            pushNotification(
                buildNotification({
                    type: "new_order",
                    orderId,
                    title: isDineIn
                        ? `Đơn tại bàn ${data?.tableNumber ?? data?.table_number ?? "?"}`
                        : "Đơn giao hàng mới",
                    message: isDineIn
                        ? "Nhà hàng vừa nhận được đơn tại bàn mới"
                        : "Nhà hàng vừa nhận được đơn delivery mới, hệ thống đang tìm tài xế",
                    raw: data,
                }),
            );
        };

        const handleOrderStatus = (data: any) => {
            const orderId = String(data?.orderId ?? "");
            if (!orderId) return;

            void refreshOne(orderId);

            upsertOrder({
                orderId,
                status: data?.status,
                type: data?.type ?? data?.orderType ?? data?.order_type,
                tableNumber: data?.tableNumber ?? data?.table_number ?? null,
                merchantId:
                    data?.merchantId ?? data?.merchant_id ?? merchantId ?? undefined,
                branchId: data?.branchId ?? data?.branch_id,
                updatedAt: Date.now(),
                raw: data,
            });

            pushNotification(
                buildNotification({
                    type: "order_status",
                    orderId,
                    title: "Cập nhật đơn hàng",
                    message:
                        data?.message ??
                        `Đơn ${orderId} vừa cập nhật sang trạng thái ${data?.status ?? "mới"}`,
                    raw: data,
                }),
            );
        };

        const handleDispatchExpired = (data: any) => {
            const orderId = String(data?.orderId ?? "");
            if (!orderId) return;

            void refreshOne(orderId);

            pushNotification(
                buildNotification({
                    type: "dispatch_expired",
                    orderId,
                    title: "Chưa tìm được tài xế",
                    message:
                        data?.message ??
                        "Đơn delivery hiện chưa tìm được tài xế phù hợp",
                    raw: data,
                }),
            );
        };

        const handleDispatchCancelled = (data: any) => {
            const orderId = String(data?.orderId ?? "");
            if (!orderId) return;

            pushNotification(
                buildNotification({
                    type: "dispatch_cancelled",
                    orderId,
                    title: "Điều phối đã hủy",
                    message:
                        data?.message ?? "Quá trình điều phối tài xế cho đơn đã bị hủy",
                    raw: data,
                }),
            );
        };

        const handleTableStatus = (_data: any) => {
            void fetchTables();
        };

        const handleNotificationNew = (data: any) => {
            pushNotification({
                id: String(data?.id ?? `notif_${Date.now()}`),
                type: data?.type === "review_received" ? "review_received" : "system",
                orderId: String(data?.data?.order_id ?? ""),
                title: data?.title ?? "Thông báo mới",
                message: data?.body ?? "",
                createdAt: new Date(data?.created_at ?? Date.now()).getTime(),
                read: false,
                raw: data,
            });

            if (data?.type === "review_received") {
                void useMerchantReviewsStore.getState().fetchSummary();
                void useMerchantReviewsStore.getState().fetchFeed();
            }
        };

        merchantSocketService.onConnect(handleConnect);
        merchantSocketService.onDisconnect(handleDisconnect);
        merchantSocketService.onConnectError(handleConnectError);

        merchantSocketService.on("merchant:notification:new", handleNotificationNew);
        merchantSocketService.on("merchant:order:new", handleOrderNew);
        merchantSocketService.on("merchant:order:status", handleOrderStatus);
        merchantSocketService.on("merchant:table:status", handleTableStatus);
        merchantSocketService.on("merchant:dispatch:expired", handleDispatchExpired);
        merchantSocketService.on("merchant:dispatch:cancelled", handleDispatchCancelled);

        return () => {
            merchantSocketService.off("merchant:notification:new", handleNotificationNew);
            merchantSocketService.off("merchant:order:new", handleOrderNew);
            merchantSocketService.off("merchant:order:status", handleOrderStatus);
            merchantSocketService.off("merchant:table:status", handleTableStatus);
            merchantSocketService.off("merchant:dispatch:expired", handleDispatchExpired);
            merchantSocketService.off("merchant:dispatch:cancelled", handleDispatchCancelled);

            socket.off("connect", handleConnect);
            socket.off("disconnect", handleDisconnect);
            socket.off("connect_error", handleConnectError);

            merchantSocketService.disconnect();
            reset();
        };
    }, [
        accessToken,
        isAuthenticated,
        merchant,
        pushNotification,
        refreshOne,
        reset,
        setConnected,
        upsertOrder,
        fetchTables,
        user,
    ]);
}
