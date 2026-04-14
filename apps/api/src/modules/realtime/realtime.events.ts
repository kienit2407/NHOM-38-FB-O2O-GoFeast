export const RealtimeNamespace = '/realtime';

export const RealtimeEvents = {
    SOCKET_READY: 'socket:ready',
    SOCKET_ERROR: 'socket:error',

    CUSTOMER_DISPATCH_SEARCHING: 'customer:dispatch:searching',
    CUSTOMER_DISPATCH_EXPIRED: 'customer:dispatch:expired',
    CUSTOMER_ORDER_STATUS: 'customer:order:status',
    CUSTOMER_DRIVER_LOCATION: 'customer:driver:location',
    CUSTOMER_ORDER_CANCELLED: 'customer:order:cancelled',
    CUSTOMER_PROMOTION_PUSH: 'customer:promotion:push',
    CUSTOMER_NOTIFICATION_NEW: 'customer:notification:new',

    DRIVER_NEW_ORDER_OFFER: 'driver:new-order-offer',
    DRIVER_OFFER_ACCEPTED: 'driver:offer:accepted',
    DRIVER_OFFER_CANCELLED: 'driver:offer:cancelled',
    DRIVER_OFFER_EXPIRED: 'driver:offer:expired',
    DRIVER_ORDER_STATUS: 'driver:order:status',
    DRIVER_NOTIFICATION_NEW: 'driver:notification:new',

    MERCHANT_ORDER_NEW: 'merchant:order:new',
    MERCHANT_ORDER_STATUS: 'merchant:order:status',
    MERCHANT_DISPATCH_EXPIRED: 'merchant:dispatch:expired',
    MERCHANT_DISPATCH_CANCELLED: 'merchant:dispatch:cancelled',
    MERCHANT_NOTIFICATION_NEW: 'merchant:notification:new',

    ADMIN_ORDER_NEW: 'admin:order:new',
    ADMIN_ORDER_STATUS: 'admin:order:status',

    MERCHANT_ROOM_JOIN: 'merchant:room:join',
    ORDER_ROOM_JOIN: 'order:room:join',
    ORDER_ROOM_LEAVE: 'order:room:leave',
    DRIVER_OFFER_ACCEPT: 'driver:offer:accept',
    DRIVER_OFFER_REJECT: 'driver:offer:reject',
} as const;
