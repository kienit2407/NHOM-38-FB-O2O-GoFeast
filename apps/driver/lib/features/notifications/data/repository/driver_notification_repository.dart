import 'package:driver/core/network/dio_client.dart';
import '../models/driver_notification_models.dart';

class DriverNotificationRepository {
  DriverNotificationRepository(this._dio);

  final DioClient _dio;

  Future<DriverNotificationPage> listMine({
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _dio.dio.get(
      '/notifications/me',
      queryParameters: {
        'page': page,
        'limit': limit,
        'exclude_promotion': true,
      },
    );

    return DriverNotificationPage.fromJson(
      (res.data['data'] as Map).cast<String, dynamic>(),
    );
  }

  Future<void> markRead(String id) async {
    await _dio.dio.patch('/notifications/me/$id/read');
  }

  Future<void> markAllRead() async {
    await _dio.dio.patch('/notifications/me/read-all');
  }

  Future<void> deleteOne(String id) async {
    await _dio.dio.delete('/notifications/me/$id');
  }

  Future<int> unreadCount() async {
    final res = await _dio.dio.get(
      '/notifications/me/unread-count',
      queryParameters: {'exclude_promotion': true},
    );
    final data = (res.data['data'] as Map).cast<String, dynamic>();
    return (data['unread'] as num?)?.toInt() ?? 0;
  }

  Future<void> clearAll() async {
    await _dio.dio.delete('/notifications/me/clear-all');
  }
}
