import 'package:flutter/foundation.dart';

@immutable
class DriverAccountProfile {
  final String id;
  final String? fullName;
  final String? phone;
  final String? email;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? avatarUrl;
  final DriverProfileInfo driverProfile;

  const DriverAccountProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.gender,
    required this.dateOfBirth,
    required this.avatarUrl,
    required this.driverProfile,
  });

  bool get isVerified => driverProfile.verificationStatus == 'approved';

  factory DriverAccountProfile.fromJson(Map<String, dynamic> json) {
    return DriverAccountProfile(
      id: (json['id'] ?? '').toString(),
      fullName: json['full_name']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      gender: json['gender']?.toString(),
      dateOfBirth: _tryParseDate(json['date_of_birth']),
      avatarUrl: json['avatar_url']?.toString(),
      driverProfile: DriverProfileInfo.fromJson(
        Map<String, dynamic>.from((json['driver_profile'] as Map?) ?? const {}),
      ),
    );
  }

  DriverAccountProfile copyWith({
    String? id,
    String? fullName,
    String? phone,
    String? email,
    String? gender,
    DateTime? dateOfBirth,
    String? avatarUrl,
    DriverProfileInfo? driverProfile,
  }) {
    return DriverAccountProfile(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      driverProfile: driverProfile ?? this.driverProfile,
    );
  }

  static DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}

@immutable
class DriverProfileInfo {
  final String? verificationStatus;
  final bool isVerified;
  final bool acceptFoodOrders;
  final String? bankName;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final DateTime? updatedAt;

  const DriverProfileInfo({
    required this.verificationStatus,
    required this.isVerified,
    required this.acceptFoodOrders,
    required this.bankName,
    required this.bankAccountName,
    required this.bankAccountNumber,
    required this.updatedAt,
  });

  factory DriverProfileInfo.fromJson(Map<String, dynamic> json) {
    return DriverProfileInfo(
      verificationStatus: json['verification_status']?.toString(),
      isVerified: json['is_verified'] == true,
      acceptFoodOrders: json['accept_food_orders'] == true,
      bankName: json['bank_name']?.toString(),
      bankAccountName: json['bank_account_name']?.toString(),
      bankAccountNumber: json['bank_account_number']?.toString(),
      updatedAt: DriverAccountProfile._tryParseDate(json['updated_at']),
    );
  }

  DriverProfileInfo copyWith({
    String? verificationStatus,
    bool? isVerified,
    bool? acceptFoodOrders,
    String? bankName,
    String? bankAccountName,
    String? bankAccountNumber,
    DateTime? updatedAt,
  }) {
    return DriverProfileInfo(
      verificationStatus: verificationStatus ?? this.verificationStatus,
      isVerified: isVerified ?? this.isVerified,
      acceptFoodOrders: acceptFoodOrders ?? this.acceptFoodOrders,
      bankName: bankName ?? this.bankName,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
