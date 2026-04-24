import 'dart:async';

import 'package:driver/core/di/providers.dart';
import 'package:driver/core/push/local_notification_service.dart';
import 'package:driver/core/realtime/socket_provider.dart';
import 'package:driver/features/notifications/data/models/driver_notification_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SocketBootstrapController {
  SocketBootstrapController({
    required Ref ref,
    required DriverSocketService socketService,
    required LocalNotificationService notificationService,
  }) : _ref = ref,
       _socketService = socketService,
       _notificationService = notificationService;

  final Ref _ref;
  final DriverSocketService _socketService;
  final LocalNotificationService _notificationService;

  StreamSubscription? _newOrderOfferSub;
  StreamSubscription? _orderStatusSub;
  StreamSubscription? _notificationNewSub;

  Future<void> start() async {
    print('[DRIVER BOOTSTRAP] start');
    await _socketService.init();
    await _socketService.connect();

    _newOrderOfferSub ??= _socketService.newOrderOfferStream.listen((data) {
      print('[DRIVER BOOTSTRAP] newOrderOfferStream = $data');
    });

    _orderStatusSub ??= _socketService.orderStatusStream.listen((data) async {
      print('[DRIVER BOOTSTRAP] orderStatusStream = $data');
      final status = data['status']?.toString() ?? '';
      if (status != 'cancelled') {
        return;
      }

      final orderId = data['orderId']?.toString() ?? '';
      final body = data['message']?.toString() ?? 'Đơn hàng đã bị huỷ';

      await _notificationService.showOrderNotification(
        id: orderId.hashCode ^ 999,
        title: 'Đơn hàng đã bị huỷ',
        body: body,
        payload: 'order:$orderId',
      );
    });

    _notificationNewSub ??= _socketService.notificationNewStream.listen((
      data,
    ) async {
      final item = DriverNotificationItem.fromSocket(data);

      _ref
          .read(driverNotificationControllerProvider.notifier)
          .prependRealtime(item);

      await _notificationService.showOrderNotification(
        id: item.id.hashCode ^ 1234,
        title: item.title,
        body: item.body,
        payload: 'order:${item.data.orderId ?? ''}',
      );
    });
  }

  Future<void> stop() async {
    await _newOrderOfferSub?.cancel();
    await _orderStatusSub?.cancel();
    await _notificationNewSub?.cancel();

    _newOrderOfferSub = null;
    _orderStatusSub = null;
    _notificationNewSub = null;

    _socketService.disconnect();
  }
}
