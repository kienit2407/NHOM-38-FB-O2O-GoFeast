import 'package:driver/features/profile/data/repository/driver_profile_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'driver_profile_state.dart';

class DriverProfileController extends StateNotifier<DriverProfileState> {
  DriverProfileController(this._repo)
    : super(const DriverProfileState.initial());

  final DriverProfileRepository _repo;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final profile = await _repo.getMyProfile();
      state = state.copyWith(isLoading: false, profile: profile, error: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    try {
      final profile = await _repo.getMyProfile();
      state = state.copyWith(profile: profile, error: null);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> updateProfile({
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
    state = state.copyWith(isBusy: true, error: null);

    try {
      final profile = await _repo.updateProfile(
        fullName: fullName,
        phone: phone,
        gender: gender,
        dateOfBirth: dateOfBirth,
        avatarUrl: avatarUrl,
        bankName: bankName,
        bankAccountName: bankAccountName,
        bankAccountNumber: bankAccountNumber,
        clearGender: clearGender,
        clearDateOfBirth: clearDateOfBirth,
        clearAvatar: clearAvatar,
        clearBankName: clearBankName,
        clearBankAccountName: clearBankAccountName,
        clearBankAccountNumber: clearBankAccountNumber,
      );

      state = state.copyWith(isBusy: false, profile: profile, error: null);
    } catch (e) {
      state = state.copyWith(isBusy: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> uploadAvatar(String filePath) async {
    state = state.copyWith(isBusy: true, error: null);

    try {
      final url = await _repo.uploadAvatar(filePath);
      final profile = await _repo.updateProfile(avatarUrl: url);

      state = state.copyWith(isBusy: false, profile: profile, error: null);
    } catch (e) {
      state = state.copyWith(isBusy: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> removeAvatar() async {
    await updateProfile(clearAvatar: true);
  }
}
