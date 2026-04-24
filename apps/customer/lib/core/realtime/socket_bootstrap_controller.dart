import 'dart:async';

import 'package:customer/core/di/providers.dart';
import 'package:customer/core/push/local_notification_service.dart';
import 'package:customer/core/realtime/socket_provider.dart';
import 'package:customer/features/notifications/data/models/notification_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CustomerSocketBootstrapController {
  CustomerSocketBootstrapController({
    required Ref ref,
    required CustomerSocketService socketService,
    required LocalNotificationService notificationService,
  }) : _ref = ref,
       _socketService = socketService,
       _notificationService = notificationService;

  final Ref _ref;
  final CustomerSocketService _socketService;
  final LocalNotificationService _notificationService;

  StreamSubscription? _orderStatusSub;
  StreamSubscription? _dispatchSearchingSub;
  StreamSubscription? _dispatchExpiredSub;
  StreamSubscription? _orderCancelledSub;
  StreamSubscription? _promotionPushSub;
  StreamSubscription? _notificationNewSub;
  StreamSubscription? _dineInSessionSub;

  Future<void> _clearLocalDineInSessionIfMatched({
    required String tableSessionId,
  }) async {
    final current = _ref.read(dineInSessionProvider).context;
    if (current == null) return;
    if (tableSessionId.isEmpty) return;
    if (current.tableSessionId != tableSessionId) return;

    await _ref.read(dineInSessionProvider.notifier).clearOnlyLocal();
    await _socketService.reconnectWithFreshToken();
  }

  Future<void> start() async {
    await _socketService.init();
    await _socketService.connect();

    _orderStatusSub ??= _socketService.orderStatusStream.listen((data) async {
      final orderId = data['orderId']?.toString() ?? '';
      final status = data['status']?.toString() ?? 'updated';
      final orderType = data['orderType']?.toString();
      final tableSessionId = data['tableSessionId']?.toString() ?? '';

      final rawMessage = data['message']?.toString().trim() ?? '';
      final title = _orderStatusTitle(status, orderType: orderType);
      final body = rawMessage.isNotEmpty
          ? rawMessage
          : _orderStatusFallbackBody(status, orderType: orderType);

      await _notificationService.showNotification(
        id: orderId.hashCode,
        title: title,
        body: body,
        payload: 'order:$orderId',
      );

      if (orderId.isNotEmpty) {
        await _ref
            .read(myOrdersControllerProvider.notifier)
            .refreshOrderRealtime(orderId: orderId);
      }

      if (orderType == 'dine_in' && status == 'completed') {
        await _clearLocalDineInSessionIfMatched(tableSessionId: tableSessionId);
      }
    });

    _dispatchSearchingSub ??= _socketService.dispatchSearchingStream.listen((
      data,
    ) async {
      final orderId = data['orderId']?.toString() ?? '';
      final message =
          data['message']?.toString() ??
          'Hệ thống đang tìm tài xế phù hợp cho đơn của bạn';

      await _notificationService.showNotification(
        id: orderId.hashCode ^ 100,
        title: 'Đang tìm tài xế',
        body: message,
        payload: 'order:$orderId',
      );

      if (orderId.isNotEmpty) {
        await _ref
            .read(myOrdersControllerProvider.notifier)
            .refreshOrderRealtime(orderId: orderId);
      }
    });

    _dispatchExpiredSub ??= _socketService.dispatchExpiredStream.listen((
      data,
    ) async {
      final orderId = data['orderId']?.toString() ?? '';

      await _notificationService.showNotification(
        id: orderId.hashCode ^ 101,
        title: 'Chưa tìm được tài xế',
        body: 'Hệ thống chưa tìm được tài xế phù hợp cho đơn của bạn',
        payload: 'order:$orderId',
      );

      if (orderId.isNotEmpty) {
        await _ref
            .read(myOrdersControllerProvider.notifier)
            .refreshOrderRealtime(orderId: orderId);
      }
    });

    _orderCancelledSub ??= _socketService.orderCancelledStream.listen((
      data,
    ) async {
      final orderId = data['orderId']?.toString() ?? '';
      final message =
          data['message']?.toString() ?? 'Đơn hàng của bạn đã bị hủy';

      await _notificationService.showNotification(
        id: orderId.hashCode ^ 202,
        title: 'Đơn hàng đã bị hủy',
        body: message,
        payload: 'order:$orderId',
      );

      if (orderId.isNotEmpty) {
        await _ref
            .read(myOrdersControllerProvider.notifier)
            .refreshOrderRealtime(orderId: orderId);
      }
    });

    _promotionPushSub ??= _socketService.promotionPushStream.listen((
      data,
    ) async {
      final promotionId = data['promotionId']?.toString() ?? '';
      final title = data['title']?.toString() ?? 'Ưu đãi mới';
      final body = data['body']?.toString() ?? 'Bạn vừa nhận được ưu đãi mới';

      await _notificationService.showNotification(
        id: promotionId.hashCode ^ 303,
        title: title,
        body: body,
        payload: 'promotion:$promotionId',
      );
    });

    _notificationNewSub ??= _socketService.notificationNewStream.listen((
      data,
    ) async {
      final item = AppNotificationItem.fromSocket(data);

      _ref.read(notificationControllerProvider.notifier).prependRealtime(item);

      await _notificationService.showNotification(
        id: item.id.hashCode ^ 404,
        title: item.title,
        body: item.body,
        payload: item.type == AppNotificationType.promotion
            ? 'promotion:${item.data.promotionId ?? ''}'
            : 'order:${item.data.orderId ?? ''}',
      );
    });

    _dineInSessionSub ??= _socketService.dineInSessionStream.listen((
      data,
    ) async {
      final action = data['action']?.toString().trim() ?? '';
      final tableSessionId = data['tableSessionId']?.toString().trim() ?? '';
      if (action != 'closed' || tableSessionId.isEmpty) return;

      await _clearLocalDineInSessionIfMatched(tableSessionId: tableSessionId);
    });
  }

  Future<void> stop() async {
    await _orderStatusSub?.cancel();
    await _dispatchSearchingSub?.cancel();
    await _dispatchExpiredSub?.cancel();
    await _orderCancelledSub?.cancel();
    await _promotionPushSub?.cancel();
    await _notificationNewSub?.cancel();
    await _dineInSessionSub?.cancel();

    _orderStatusSub = null;
    _dispatchSearchingSub = null;
    _dispatchExpiredSub = null;
    _orderCancelledSub = null;
    _promotionPushSub = null;
    _notificationNewSub = null;
    _dineInSessionSub = null;

    _socketService.disconnect();
  }
}

String _orderStatusTitle(String status, {String? orderType}) {
  final isDineIn = orderType == 'dine_in';

  switch (status) {
    case 'searching_driver':
    case 'dispatch_searching':
    case 'dispatch_retrying':
      return 'Đang tìm tài xế';
    case 'dispatch_expired':
      return 'Chưa tìm được tài xế';
    case 'confirmed':
      return isDineIn ? 'Quán đã xác nhận đơn' : 'Đơn đã được tiếp nhận';
    case 'preparing':
      return 'Quán đang chuẩn bị món';
    case 'ready_for_pickup':
      return isDineIn ? 'Món đã sẵn sàng phục vụ' : 'Món đã sẵn sàng';
    case 'driver_assigned':
      return isDineIn
          ? 'Đơn đang được phục vụ tại quán'
          : 'Đã có tài xế nhận đơn';
    case 'driver_arrived':
      return isDineIn ? 'Đơn đã được phục vụ' : 'Tài xế đã tới quán';
    case 'picked_up':
      return isDineIn ? 'Khách đã nhận món tại quán' : 'Tài xế đã lấy món';
    case 'delivering':
      return isDineIn
          ? 'Đơn đang được phục vụ tại quán'
          : 'Tài xế đang giao đơn';
    case 'delivered':
      return isDineIn ? 'Đơn đã phục vụ xong' : 'Đơn đã giao tới nơi';
    case 'completed':
      return 'Đơn hàng hoàn tất';
    case 'cancelled':
      return 'Đơn hàng đã bị hủy';
    default:
      return 'Cập nhật đơn hàng';
  }
}

String _orderStatusFallbackBody(String status, {String? orderType}) {
  final isDineIn = orderType == 'dine_in';

  switch (status) {
    case 'searching_driver':
    case 'dispatch_searching':
    case 'dispatch_retrying':
      return 'Hệ thống đang tìm tài xế phù hợp cho đơn của bạn.';
    case 'dispatch_expired':
      return 'Hệ thống chưa tìm được tài xế phù hợp cho đơn của bạn.';
    case 'confirmed':
      return isDineIn
          ? 'Quán đã xác nhận và bắt đầu xử lý đơn của bạn.'
          : 'Hệ thống đã tiếp nhận đơn và bắt đầu xử lý.';
    case 'preparing':
      return 'Quán đang chuẩn bị món cho đơn hàng của bạn.';
    case 'ready_for_pickup':
      return isDineIn
          ? 'Món đã sẵn sàng để phục vụ tại bàn.'
          : 'Món đã sẵn sàng để tài xế lấy.';
    case 'driver_assigned':
      return isDineIn
          ? 'Đơn hàng tại quán của bạn đang được phục vụ.'
          : 'Đơn hàng của bạn đã có tài xế nhận.';
    case 'driver_arrived':
      return isDineIn
          ? 'Đơn hàng tại quán của bạn đã được phục vụ.'
          : 'Tài xế đã tới quán để lấy món.';
    case 'picked_up':
      return isDineIn
          ? 'Khách đã nhận món tại quán.'
          : 'Tài xế đã lấy món và chuẩn bị giao cho bạn.';
    case 'delivering':
      return isDineIn
          ? 'Đơn hàng tại quán đang được phục vụ.'
          : 'Tài xế đang trên đường giao đơn cho bạn.';
    case 'delivered':
      return isDineIn
          ? 'Đơn hàng tại quán đã được phục vụ xong.'
          : 'Đơn hàng đã được giao tới nơi.';
    case 'completed':
      return 'Đơn hàng của bạn đã hoàn tất.';
    case 'cancelled':
      return 'Đơn hàng của bạn đã bị hủy.';
    default:
      return 'Đơn hàng của bạn vừa được cập nhật.';
  }
}
