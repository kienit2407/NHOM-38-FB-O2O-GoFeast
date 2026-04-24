import 'package:dio/dio.dart';

class TrackingParty {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final double? lat;
  final double? lng;

  const TrackingParty({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.lat,
    this.lng,
  });

  factory TrackingParty.fromJson(Map<String, dynamic> j) {
    return TrackingParty(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      phone: j['phone']?.toString(),
      address: j['address']?.toString(),
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
    );
  }
}

class TrackingDeliveryInfo {
  final String? address;
  final double? lat;
  final double? lng;

  const TrackingDeliveryInfo({this.address, this.lat, this.lng});

  factory TrackingDeliveryInfo.fromJson(Map<String, dynamic> j) {
    return TrackingDeliveryInfo(
      address: j['address']?.toString(),
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
    );
  }
}

class TrackingOrder {
  final String id;
  final String orderNumber;
  final String status;
  final String orderType;
  final bool driverAssigned;
  final int? etaMin;
  final String? etaAt;
  final TrackingParty merchant;
  final TrackingParty? driver;
  final TrackingDeliveryInfo delivery;

  const TrackingOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.orderType,
    required this.driverAssigned,
    required this.merchant,
    required this.delivery,
    this.driver,
    this.etaMin,
    this.etaAt,
  });

  bool get canCancel => status == 'pending' && !driverAssigned;
  bool get isDineIn => orderType == 'dine_in';

  factory TrackingOrder.fromJson(Map<String, dynamic> j) {
    return TrackingOrder(
      id: (j['order_id'] ?? j['id'] ?? '').toString(),
      orderNumber: (j['order_number'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      orderType: (j['order_type'] ?? 'delivery').toString(),
      driverAssigned: j['driver_assigned'] == true,
      etaMin: (j['eta_min'] as num?)?.toInt(),
      etaAt: j['eta_at']?.toString(),
      merchant: TrackingParty.fromJson(
        Map<String, dynamic>.from(j['merchant'] ?? const {}),
      ),
      driver: j['driver'] == null
          ? null
          : TrackingParty.fromJson(
              Map<String, dynamic>.from(j['driver'] as Map),
            ),
      delivery: TrackingDeliveryInfo.fromJson(
        Map<String, dynamic>.from(
          j['customer_delivery'] ?? const <String, dynamic>{},
        ),
      ),
    );
  }
}

class OrderTrackingRepository {
  OrderTrackingRepository(this._dio);

  final Dio _dio;

  Future<TrackingOrder> getTracking(String orderId) async {
    final res = await _dio.get('/orders/me/$orderId/tracking');
    final raw = res.data;
    final data = raw is Map && raw['data'] is Map
        ? Map<String, dynamic>.from(raw['data'] as Map)
        : Map<String, dynamic>.from(raw as Map);

    return TrackingOrder.fromJson(data);
  }

  Future<void> cancelOrder(String orderId, {String? reason}) async {
    await _dio.patch('/orders/me/$orderId/cancel', data: {'reason': reason});
  }
}
