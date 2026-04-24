import 'dart:convert';

import 'package:customer/core/network/dio_client.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checkout_models.dart';

class CheckoutRepository {
  CheckoutRepository(this._dio);
  final DioClient _dio;

  Future<CheckoutPreviewResponse> previewDelivery({
    required String merchantId,
    required double lat,
    required double lng,
    required String address,
    required String receiverName,
    required String receiverPhone,
    String? addressNote,
    CheckoutPaymentMethod paymentMethod = CheckoutPaymentMethod.cash,
    String? voucherCode,
  }) async {
    final res = await _dio.get(
      '/checkout/delivery/preview',
      queryParameters: {
        'merchant_id': merchantId,
        'lat': lat,
        'lng': lng,
        'address': address,
        'receiver_name': receiverName,
        'receiver_phone': receiverPhone,
        if (addressNote != null && addressNote.isNotEmpty)
          'address_note': addressNote,
        'payment_method': checkoutPaymentMethodToApi(paymentMethod),
        if (voucherCode != null && voucherCode.trim().isNotEmpty)
          'voucher_code': voucherCode.trim(),
      },
    );

    final raw = ((res.data['data'] ?? res.data) as Map).cast<String, dynamic>();
    return CheckoutPreviewResponse.fromJson(raw);
  }

  Future<Options> _publicDineInOptions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('active_dine_in_context_v1');

    String? token;
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
        token = map['dine_in_token']?.toString();
      } catch (_) {}
    }

    return Options(
      headers: {
        if (token != null && token.isNotEmpty) 'X-Dine-In-Token': token,
      },
    );
  }

  Future<CheckoutPreviewResponse> previewDineIn({
    required String tableSessionId,
    String? voucherCode,
  }) async {
    final res = await _dio.get(
      '/checkout/dine-in/public/preview',
      queryParameters: {
        'table_session_id': tableSessionId,
        if (voucherCode != null && voucherCode.trim().isNotEmpty)
          'voucher_code': voucherCode.trim(),
      },
      options: await _publicDineInOptions(),
    );

    final raw = ((res.data['data'] ?? res.data) as Map).cast<String, dynamic>();
    return CheckoutPreviewResponse.fromJson(raw);
  }

  Future<PlaceOrderResponse> placeDeliveryOrder({
    required String merchantId,
    required double lat,
    required double lng,
    required String address,
    required String receiverName,
    required String receiverPhone,
    String? addressNote,
    String? orderNote,
    required CheckoutPaymentMethod paymentMethod,
    String? voucherCode,
  }) async {
    final res = await _dio.post(
      '/checkout/delivery/place-order',
      data: {
        'merchant_id': merchantId,
        'lat': lat,
        'lng': lng,
        'address': address,
        'receiver_name': receiverName,
        'receiver_phone': receiverPhone,
        if (addressNote != null && addressNote.isNotEmpty)
          'address_note': addressNote,
        if (orderNote != null && orderNote.isNotEmpty) 'order_note': orderNote,
        'payment_method': checkoutPaymentMethodToApi(paymentMethod),
        if (voucherCode != null && voucherCode.trim().isNotEmpty)
          'voucher_code': voucherCode.trim(),
      },
    );

    final raw = ((res.data['data'] ?? res.data) as Map).cast<String, dynamic>();
    return PlaceOrderResponse.fromJson(raw);
  }

  Future<PlaceOrderResponse> placeDineInOrder({
    required String tableSessionId,
    String? voucherCode,
    String? orderNote,
  }) async {
    final res = await _dio.post(
      '/checkout/dine-in/public/place-order',
      data: {
        'table_session_id': tableSessionId,
        if (voucherCode != null && voucherCode.trim().isNotEmpty)
          'voucher_code': voucherCode.trim(),
        if (orderNote != null && orderNote.isNotEmpty) 'order_note': orderNote,
      },
      options: await _publicDineInOptions(),
    );

    final raw = ((res.data['data'] ?? res.data) as Map).cast<String, dynamic>();
    return PlaceOrderResponse.fromJson(raw);
  }

  Future<CheckoutPreviewResponse> preview({
    required CheckoutParams params,
    double? lat,
    double? lng,
    String? address,
    String? receiverName,
    String? receiverPhone,
    String? addressNote,
    CheckoutPaymentMethod paymentMethod = CheckoutPaymentMethod.cash,
    String? voucherCode,
  }) async {
    if (params.mode == CheckoutMode.delivery) {
      return previewDelivery(
        merchantId: params.merchantId,
        lat: lat ?? 0,
        lng: lng ?? 0,
        address: address ?? '',
        receiverName: receiverName ?? '',
        receiverPhone: receiverPhone ?? '',
        addressNote: addressNote,
        paymentMethod: paymentMethod,
        voucherCode: voucherCode,
      );
    }

    return previewDineIn(
      tableSessionId: params.tableSessionId,
      voucherCode: voucherCode,
    );
  }

  Future<PlaceOrderResponse> placeOrder({
    required CheckoutParams params,
    double? lat,
    double? lng,
    String? address,
    String? receiverName,
    String? receiverPhone,
    String? addressNote,
    String? orderNote,
    required CheckoutPaymentMethod paymentMethod,
    String? voucherCode,
  }) async {
    if (params.mode == CheckoutMode.delivery) {
      return placeDeliveryOrder(
        merchantId: params.merchantId,
        lat: lat ?? 0,
        lng: lng ?? 0,
        address: address ?? '',
        receiverName: receiverName ?? '',
        receiverPhone: receiverPhone ?? '',
        addressNote: addressNote,
        orderNote: orderNote,
        paymentMethod: paymentMethod,
        voucherCode: voucherCode,
      );
    }

    return placeDineInOrder(
      tableSessionId: params.tableSessionId,
      voucherCode: voucherCode,
      orderNote: orderNote,
    );
  }
}
