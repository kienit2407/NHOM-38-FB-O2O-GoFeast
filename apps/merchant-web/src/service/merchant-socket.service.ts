/* eslint-disable @typescript-eslint/no-explicit-any */
import { io, Socket } from "socket.io-client";

export type MerchantSocketEvent =
    | "socket:ready"
    | "merchant:order:new"
    | "merchant:order:status"
    | "merchant:table:status"
    | "merchant:dispatch:expired"
    | "merchant:dispatch:cancelled"
    | "merchant:notification:new";
const API_BASE_URL =
  import.meta.env.VITE_API_BASE_URL || "http://localhost:4000";
class MerchantSocketService {
    private socket: Socket | null = null;

    connect(accessToken: string) {
        // nếu đã có socket thì chỉ update token và reconnect nếu cần
        if (this.socket) {
            this.socket.auth = { token: accessToken };

            if (!this.socket.connected) {
                this.socket.connect();
            }

            return this.socket;
        }

        this.socket = io(`${API_BASE_URL}/realtime`, {
            transports: ["websocket"],
            autoConnect: false,
            auth: {
                token: accessToken,
            },
            withCredentials: true,
            reconnection: true,
            reconnectionAttempts: Infinity,
            reconnectionDelay: 1000,
            reconnectionDelayMax: 5000,
        });

        this.socket.connect();
        return this.socket;
    }

    disconnect() {
        if (!this.socket) return;
        this.socket.disconnect();
        this.socket.removeAllListeners();
        this.socket = null;
    }

    getSocket() {
        return this.socket;
    }

    isConnected() {
        return this.socket?.connected === true;
    }

    reconnectWithFreshToken(accessToken: string) {
        if (!this.socket) {
            return this.connect(accessToken);
        }

        this.socket.auth = { token: accessToken };
        this.socket.disconnect();
        this.socket.connect();
        return this.socket;
    }

    on(event: MerchantSocketEvent, cb: (payload: any) => void) {
        this.socket?.on(event, cb);
    }

    off(event: MerchantSocketEvent, cb?: (payload: any) => void) {
        if (!this.socket) return;
        if (cb) this.socket.off(event, cb);
        else this.socket.off(event);
    }

    onConnect(cb: () => void) {
        this.socket?.on("connect", cb);
    }

    onDisconnect(cb: () => void) {
        this.socket?.on("disconnect", cb);
    }

    onConnectError(cb: (err: any) => void) {
        this.socket?.on("connect_error", cb);
    }

    emit(event: string, payload?: any) {
        this.socket?.emit(event, payload);
    }

    joinMerchantRoom(merchantId: string) {
        this.emit("merchant:room:join", { merchantId });
    }

    joinOrderRoom(orderId: string) {
        this.emit("order:room:join", { orderId });
    }

    leaveOrderRoom(orderId: string) {
        this.emit("order:room:leave", { orderId });
    }
}

export const merchantSocketService = new MerchantSocketService();
