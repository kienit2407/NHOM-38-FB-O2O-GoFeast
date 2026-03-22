import 'dart:io';

import 'package:dio/dio.dart';
import 'package:driver/core/network/dio_client.dart';
import '../models/driver_profile_models.dart';

class DriverProfileRepository {
  DriverProfileRepository(this.dio);

  final DioClient dio;

  Future<DriverAccountProfile> getMyProfile() async {
    final res = await dio.get<Map<String, dynamic>>('/drivers/me/profile');

    final body = Map<String, dynamic>.from(res.data ?? const {});
    final data = Map<String, dynamic>.from((body['data'] as Map?) ?? const {});

    return DriverAccountProfile.fromJson(data);
  }

  Future<DriverAccountProfile> updateProfile({
    String? fullName,
    String? phone,
    String? gender,
    DateTime? dateOfBirth,
    String? avatarUrl,
    String? bankName,
    String? bankAccountName,
    String? bankAccountNumber,
    bool clearGender = false,
    bool clearDateOfBirth = false,
    bool clearAvatar = false,
    bool clearBankName = false,
    bool clearBankAccountName = false,
    bool clearBankAccountNumber = false,
  }) async {
    final payload = <String, dynamic>{};

    if (fullName != null) payload['fullName'] = fullName;
    if (phone != null) payload['phone'] = phone;
    if (gender != null) payload['gender'] = gender;
    if (dateOfBirth != null) {
      payload['dateOfBirth'] = dateOfBirth.toUtc().toIso8601String();
    }
    if (avatarUrl != null) payload['avatarUrl'] = avatarUrl;
    if (bankName != null) payload['bankName'] = bankName;
    if (bankAccountName != null) payload['bankAccountName'] = bankAccountName;
    if (bankAccountNumber != null) {
      payload['bankAccountNumber'] = bankAccountNumber;
    }

    if (clearGender) payload['gender'] = null;
    if (clearDateOfBirth) payload['dateOfBirth'] = null;
    if (clearAvatar) payload['avatarUrl'] = null;
    if (clearBankName) payload['bankName'] = null;
    if (clearBankAccountName) payload['bankAccountName'] = null;
    if (clearBankAccountNumber) payload['bankAccountNumber'] = null;

    final res = await dio.patch<Map<String, dynamic>>(
      '/drivers/me/profile',
      data: payload,
    );

    final body = Map<String, dynamic>.from(res.data ?? const {});
    final data = Map<String, dynamic>.from((body['data'] as Map?) ?? const {});

    return DriverAccountProfile.fromJson(data);
  }

  Future<String> uploadAvatar(String filePath) async {
    final fileName = filePath.split(Platform.pathSeparator).last;

    final form = FormData.fromMap({
      'folder': 'avatar',
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });

    final res = await dio.post<Map<String, dynamic>>(
      '/auth/driver/upload',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );

    final body = Map<String, dynamic>.from(res.data ?? const {});
    final data = Map<String, dynamic>.from((body['data'] as Map?) ?? const {});

    final url = (data['url'] ?? '').toString().trim();
    if (url.isEmpty) {
      throw Exception('Upload avatar failed');
    }
    return url;
  }
}
