import 'package:flutter/foundation.dart';
import '../../data/models/driver_profile_models.dart';

@immutable
class DriverProfileState {
  final bool isLoading;
  final bool isBusy;
  final String? error;
  final DriverAccountProfile? profile;

  const DriverProfileState({
    this.isLoading = false,
    this.isBusy = false,
    this.error,
    this.profile,
  });

  const DriverProfileState.initial() : this();

  DriverProfileState copyWith({
    bool? isLoading,
    bool? isBusy,
    String? error,
    DriverAccountProfile? profile,
  }) {
    return DriverProfileState(
      isLoading: isLoading ?? this.isLoading,
      isBusy: isBusy ?? this.isBusy,
      error: error,
      profile: profile ?? this.profile,
    );
  }
}
