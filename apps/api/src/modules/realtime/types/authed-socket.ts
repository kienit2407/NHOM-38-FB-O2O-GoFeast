import { Socket } from 'socket.io';

export type RealtimeRole =
    | 'customer'
    | 'driver'
    | 'merchant'
    | 'admin'
    | 'dine_in_guest';

export interface SocketAuthUser {
    userId: string;
    role: RealtimeRole;
    aud?: string;
    email?: string | null;
    tableSessionId?: string | null;
}

export type AuthedSocket = Socket & {
    user?: SocketAuthUser;
};
