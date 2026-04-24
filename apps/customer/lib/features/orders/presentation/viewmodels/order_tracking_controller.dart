import 'dart:async';

import 'package:customer/core/realtime/socket_provider.dart';
import 'package:customer/features/orders/data/repository/order_tracking_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OrderTrackingState {
  final bool isLoading;
  final bool isCancelling;
  final TrackingOrder? order;
  final String? error;

  final String dispatchState;
  final double? driverLat;
  final double? driverLng;
  final int? etaMin;
  final String? etaAt;
  final String? latestMessage;

  const OrderTrackingState({
    this.isLoading = false,
    this.isCancelling = false,
    this.order,
    this.error,
    this.dispatchState = '',
    this.driverLat,
    this.driverLng,
    this.etaMin,
    this.etaAt,
    this.latestMessage,
  });

  bool get canCancel => order?.canCancel == true && !isCancelling;

  OrderTrackingState copyWith({
    bool? isLoading,
    bool? isCancelling,
    TrackingOrder? order,
    String? error,
    String? dispatchState,
    double? driverLat,
    double? driverLng,
    int? etaMin,
    String? etaAt,
    String? latestMessage,
    bool clearError = false,
  }) {
    return OrderTrackingState(
      isLoading: isLoading ?? this.isLoading,
      isCancelling: isCancelling ?? this.isCancelling,
      order: order ?? this.order,
      error: clearError ? null : (error ?? this.error),
      dispatchState: dispatchState ?? this.dispatchState,
      driverLat: driverLat ?? this.driverLat,
      driverLng: driverLng ?? this.driverLng,
      etaMin: etaMin ?? this.etaMin,
      etaAt: etaAt ?? this.etaAt,
      latestMessage: latestMessage ?? this.latestMessage,
    );
  }
}

class OrderTrackingController extends StateNotifier<OrderTrackingState> {
  OrderTrackingController({
    required OrderTrackingRepository repository,
    required CustomerSocketService socketService,
  }) : _repository = repository,
       _socketService = socketService,
       super(const OrderTrackingState());

  final OrderTrackingRepository _repository;
  final CustomerSocketService _socketService;

  StreamSubscription? _orderStatusSub;
  StreamSubscription? _driverLocationSub;
  StreamSubscription? _dispatchSearchingSub;
  StreamSubscription? _dispatchExpiredSub;
  StreamSubscription? _orderCancelledSub;

  String? _activeOrderId;
  bool _started = false;

  Future<void> start(String orderId) async {
    if (_started && _activeOrderId == orderId) return;
    _started = true;
    _activeOrderId = orderId;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await _socketService.init();
      await _socketService.connect();
      _socketService.joinOrderRoom(orderId);

      await _cancelSubs();
      _bindSocket(orderId);

      final order = await _repository.getTracking(orderId);

      state = state.copyWith(
        isLoading: false,
        order: order,
        etaMin: order.etaMin,
        etaAt: order.etaAt,
        driverLat: order.driver?.lat,
        driverLng: order.driver?.lng,
        dispatchState: order.isDineIn
            ? ''
            : (order.driverAssigned ? 'assigned' : 'searching'),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void _bindSocket(String orderId) {
    _orderStatusSub = _socketService.orderStatusStream.listen((data) {
      if (data['orderId']?.toString() != orderId) return;

      final nextStatus = data['status']?.toString() ?? '';
      final message = data['message']?.toString();

      final current = state.order;
      if (current != null) {
        state = state.copyWith(
          order: TrackingOrder(
            id: current.id,
            orderNumber: current.orderNumber,
            status: nextStatus.isEmpty ? current.status : nextStatus,
            orderType: current.orderType,
            driverAssigned: data['driverId'] != null || current.driverAssigned,
            merchant: current.merchant,
            driver: current.driver,
            delivery: current.delivery,
            etaMin: (data['etaMin'] as num?)?.toInt() ?? current.etaMin,
            etaAt: data['etaAt']?.toString() ?? current.etaAt,
          ),
          dispatchState: current.isDineIn
              ? ''
              : (data['driverId'] != null ? 'assigned' : state.dispatchState),
          etaMin: (data['etaMin'] as num?)?.toInt() ?? state.etaMin,
          etaAt: data['etaAt']?.toString() ?? state.etaAt,
          latestMessage: message,
        );
      }
    });

    _driverLocationSub = _socketService.driverLocationStream.listen((data) {
      if (data['orderId']?.toString() != orderId) return;

      state = state.copyWith(
        driverLat: (data['lat'] as num?)?.toDouble(),
        driverLng: (data['lng'] as num?)?.toDouble(),
        etaMin: (data['etaMin'] as num?)?.toInt() ?? state.etaMin,
        etaAt: data['etaAt']?.toString() ?? state.etaAt,
      );
    });

    _dispatchSearchingSub = _socketService.dispatchSearchingStream.listen((
      data,
    ) {
      if (data['orderId']?.toString() != orderId) return;

      state = state.copyWith(
        dispatchState: state.order?.isDineIn == true ? '' : 'searching',
        latestMessage: data['message']?.toString(),
      );
    });

    _dispatchExpiredSub = _socketService.dispatchExpiredStream.listen((data) {
      if (data['orderId']?.toString() != orderId) return;

      state = state.copyWith(
        dispatchState: state.order?.isDineIn == true ? '' : 'expired',
        latestMessage: data['message']?.toString(),
      );
    });

    _orderCancelledSub = _socketService.orderCancelledStream.listen((data) {
      if (data['orderId']?.toString() != orderId) return;

      final current = state.order;
      if (current != null) {
        state = state.copyWith(
          order: TrackingOrder(
            id: current.id,
            orderNumber: current.orderNumber,
            status: 'cancelled',
            orderType: current.orderType,
            driverAssigned: current.driverAssigned,
            merchant: current.merchant,
            driver: current.driver,
            delivery: current.delivery,
            etaMin: current.etaMin,
            etaAt: current.etaAt,
          ),
          latestMessage: data['message']?.toString(),
        );
      }
    });
  }

  Future<void> refresh() async {
    final id = _activeOrderId;
    if (id == null) return;

    try {
      final order = await _repository.getTracking(id);
      state = state.copyWith(
        order: order,
        etaMin: order.etaMin,
        etaAt: order.etaAt,
        driverLat: order.driver?.lat,
        driverLng: order.driver?.lng,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> cancelOrder({String? reason}) async {
    final id = _activeOrderId;
    if (id == null || !state.canCancel) return;

    state = state.copyWith(isCancelling: true, clearError: true);

    try {
      await _repository.cancelOrder(id, reason: reason);
      await refresh();
      state = state.copyWith(isCancelling: false);
    } catch (e) {
      state = state.copyWith(isCancelling: false, error: e.toString());
    }
  }

  Future<void> _cancelSubs() async {
    await _orderStatusSub?.cancel();
    await _driverLocationSub?.cancel();
    await _dispatchSearchingSub?.cancel();
    await _dispatchExpiredSub?.cancel();
    await _orderCancelledSub?.cancel();

    _orderStatusSub = null;
    _driverLocationSub = null;
    _dispatchSearchingSub = null;
    _dispatchExpiredSub = null;
    _orderCancelledSub = null;
  }

  @override
  void dispose() {
    final id = _activeOrderId;
    if (id != null && id.isNotEmpty) {
      _socketService.leaveOrderRoom(id);
    }
    _cancelSubs();
    super.dispose();
  }
}
