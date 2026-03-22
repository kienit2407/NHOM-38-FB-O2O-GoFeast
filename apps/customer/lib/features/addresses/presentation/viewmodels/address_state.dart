import 'package:customer/features/addresses/data/models/saved_address_models.dart';

class AddressState {
  final bool isFetching;
  final bool didLoad;
  final String? error;
  final CurrentLocation? current;
  final CurrentLocation? deviceLocation;
  final List<SavedAddress> saved;

  const AddressState({
    this.isFetching = false,
    this.didLoad = false,
    this.error,
    this.current,
    this.deviceLocation,
    this.saved = const [],
  });

  const AddressState.initial()
    : isFetching = false,
      didLoad = false,
      error = null,
      current = null,
      deviceLocation = null,
      saved = const [];

  AddressState copyWith({
    bool? isFetching,
    bool? didLoad,
    String? error,
    CurrentLocation? current,
    CurrentLocation? deviceLocation,
    List<SavedAddress>? saved,
  }) {
    return AddressState(
      isFetching: isFetching ?? this.isFetching,
      didLoad: didLoad ?? this.didLoad,
      error: error,
      current: current ?? this.current,
      deviceLocation: deviceLocation ?? this.deviceLocation,
      saved: saved ?? this.saved,
    );
  }
}
