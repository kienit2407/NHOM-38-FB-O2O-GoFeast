import 'package:customer/core/network/dio_client.dart';
import 'package:customer/features/addresses/data/models/reverse_suggest_models.dart';
import 'package:customer/features/addresses/data/models/search_place_models.dart';
import 'package:customer/features/addresses/presentation/pages/search_address_page.dart';
import 'package:customer/features/auth/data/models/auth_user_model.dart';
import 'package:dio/dio.dart';

import '../models/saved_address_models.dart';

class AddressRepository {
  final DioClient dio;
  AddressRepository(this.dio);

  // =========================
  // CURRENT LOCATION (PATCH)
  // =========================
  Future<CustomerProfileModel> updateMyLocation({
    required double lat,
    required double lng,
    String? address, // optional
    String? receiverName,
    String? receiverPhone,
    String? deliveryNote,
  }) async {
    final res = await dio.patch<Map<String, dynamic>>(
      '/customers/me/location',
      data: {
        'lat': lat,
        'lng': lng,
        if (address != null) 'address': address,
        if (receiverName != null) 'receiver_name': receiverName,
        if (receiverPhone != null) 'receiver_phone': receiverPhone,
        if (deliveryNote != null) 'delivery_note': deliveryNote,
      },
    );

    return CustomerProfileModel.fromJson(
      Map<String, dynamic>.from(res.data ?? {}),
    );
  }

  // =========================
  // SAVED ADDRESSES CRUD
  // =========================

  Future<List<SavedAddress>> listMySavedAddresses() async {
    final res = await dio.get<dynamic>('/customers/me/addresses');

    // parse kiểu bạn đang làm: body['data']
    final raw = res.data;
    dynamic data = raw;
    if (raw is Map && raw['data'] != null) data = raw['data'];

    final list = (data is List) ? data : const [];
    return list
        .whereType<Map>()
        .map((e) => SavedAddress.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<SavedAddress> createMySavedAddress({
    required String address,
    double? lat,
    double? lng,
    String? receiverName,
    String? receiverPhone,
    String? deliveryNote,
  }) async {
    final res = await dio.post<dynamic>(
      '/customers/me/addresses',
      data: {
        'address': address.trim(),
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
        if (receiverName != null) 'receiver_name': receiverName.trim(),
        if (receiverPhone != null) 'receiver_phone': receiverPhone.trim(),
        if (deliveryNote != null) 'delivery_note': deliveryNote.trim(),
      },
    );

    final raw = res.data;
    dynamic data = raw;
    if (raw is Map && raw['data'] != null) data = raw['data'];

    return SavedAddress.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<SavedAddress> updateMySavedAddress(
    String id, {
    String? address,
    double? lat,
    double? lng,
    String? receiverName,
    String? receiverPhone,
    String? deliveryNote,
  }) async {
    final res = await dio.patch<dynamic>(
      '/customers/me/addresses/$id',
      data: {
        if (address != null) 'address': address.trim(),
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
        if (receiverName != null) 'receiver_name': receiverName.trim(),
        if (receiverPhone != null) 'receiver_phone': receiverPhone.trim(),
        if (deliveryNote != null) 'delivery_note': deliveryNote.trim(),
      },
    );

    final raw = res.data;
    dynamic data = raw;
    if (raw is Map && raw['data'] != null) data = raw['data'];

    // BE của bạn đang trả item updated (đúng theo code service bạn gửi)
    return SavedAddress.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> deleteMySavedAddress(String id) async {
    await dio.delete<dynamic>('/customers/me/addresses/$id');
  }

  /// Tap 1 địa chỉ đã lưu => copy snapshot sang current_location
  Future<void> useSavedAsCurrent(String id) async {
    await dio.post<dynamic>('/customers/me/addresses/$id/use');
  }

  Future<List<SearchPlaceItem>> autocompletePublic({
    required String input,
    double? lat,
    double? lng,
    int size = 8,
    CancelToken? cancelToken,
  }) async {
    final res = await dio.get<Map<String, dynamic>>(
      '/geo/autocomplete',
      queryParameters: {
        'input': input,
        'size': size,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
      },
      options: Options(
        extra: const {'__skipAuth': true, '__skipAuthRefresh': true},
      ),
      cancelToken: cancelToken,
    );

    final body = Map<String, dynamic>.from(res.data ?? {});
    final data = (body['data'] is Map)
        ? Map<String, dynamic>.from(body['data'] as Map)
        : <String, dynamic>{};

    final itemsRaw = (data['items'] is List)
        ? (data['items'] as List)
        : const [];

    return itemsRaw.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return SearchPlaceItem(
        placeId: m['placeId'] as String?,
        title: (m['title'] ?? '').toString(),
        subtitle: (m['subtitle'] ?? '').toString(),
        description: m['description'] as String?,
      );
    }).toList();
  }

  /// Resolve lat/lng cho item autocomplete bằng TextSearch (dùng description)
  Future<SearchPlaceItem?> resolveByTextSearchPublic({
    required String text,
    CancelToken? cancelToken,
  }) async {
    final res = await dio.get<Map<String, dynamic>>(
      '/geo/search',
      queryParameters: {'text': text},
      options: Options(
        extra: const {'__skipAuth': true, '__skipAuthRefresh': true},
      ),
      cancelToken: cancelToken,
    );

    final body = Map<String, dynamic>.from(res.data ?? {});
    final data = (body['data'] is Map)
        ? Map<String, dynamic>.from(body['data'] as Map)
        : <String, dynamic>{};

    final items = (data['items'] is List) ? (data['items'] as List) : const [];
    if (items.isEmpty) return null;

    final first = Map<String, dynamic>.from(items.first as Map);
    final label = (first['label'] ?? '').toString();

    // split label thành title/subtitle theo dấu phẩy đầu
    final idx = label.indexOf(',');
    final title = idx >= 0 ? label.substring(0, idx).trim() : label.trim();
    final subtitle = idx >= 0 ? label.substring(idx + 1).trim() : '';

    return SearchPlaceItem(
      title: title.isEmpty ? label : title,
      subtitle: subtitle,
      lat: (first['lat'] is num) ? (first['lat'] as num).toDouble() : null,
      lng: (first['lng'] is num) ? (first['lng'] as num).toDouble() : null,
      description: label,
    );
  }

  Future<List<ReverseSuggestItem>> nearbyPublic({
    required double lat,
    required double lng,
    int radius = 300,
    int size = 10,
    String? type, // vd: "restaurant|cafe|convenience_store"
    String? keyword, // tuỳ chọn
    CancelToken? cancelToken,
  }) async {
    final res = await dio.get<Map<String, dynamic>>(
      '/geo/nearby',
      queryParameters: {
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'size': size,
        if (type != null) 'type': type,
        if (keyword != null) 'keyword': keyword,
      },
      options: Options(
        extra: const {'__skipAuth': true, '__skipAuthRefresh': true},
      ),
      cancelToken: cancelToken,
    );

    final body = Map<String, dynamic>.from(res.data ?? {});
    final data = (body['data'] is Map)
        ? Map<String, dynamic>.from(body['data'] as Map)
        : <String, dynamic>{};

    final itemsRaw = (data['items'] is List)
        ? (data['items'] as List)
        : const [];
    return itemsRaw
        .whereType<Map>()
        .map((e) => ReverseSuggestItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<String?> reversePublic({
    required double lat,
    required double lng,
  }) async {
    final res = await dio.get<Map<String, dynamic>>(
      '/geo/reverse',
      queryParameters: {'lat': lat, 'lng': lng},
      options: Options(
        extra: const {'__skipAuth': true, '__skipAuthRefresh': true},
      ),
    );

    final body = Map<String, dynamic>.from(res.data ?? {});
    final data = (body['data'] is Map)
        ? Map<String, dynamic>.from(body['data'] as Map)
        : <String, dynamic>{};

    return data['address'] as String?;
  }

  Future<ReverseSuggestResponse> reverseSuggestPublic({
    required double lat,
    required double lng,
    int size = 5,
    int radius = 120,
    CancelToken? cancelToken,
  }) async {
    final res = await dio.get<Map<String, dynamic>>(
      '/geo/reverse',
      queryParameters: {
        'lat': lat,
        'lng': lng,
        'size': size,
        'radius': radius,
        'result_type': 'street_address',
      },
      options: Options(
        extra: const {'__skipAuth': true, '__skipAuthRefresh': true},
      ),
      cancelToken: cancelToken,
    );

    final body = Map<String, dynamic>.from(res.data ?? {});
    final data = (body['data'] is Map)
        ? Map<String, dynamic>.from(body['data'] as Map)
        : <String, dynamic>{};

    return ReverseSuggestResponse.fromJson(data);
  }

  /// Chỉ dùng khi user search địa chỉ để chọn
  Future<Map<String, dynamic>> geoSearch(String text) async {
    final res = await dio.get<Map<String, dynamic>>(
      '/geo/search',
      queryParameters: {'text': text},
      options: Options(
        extra: const {'__skipAuth': true, '__skipAuthRefresh': true},
      ),
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }
}
