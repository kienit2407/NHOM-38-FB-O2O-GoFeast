import 'package:customer/core/services/location_service.dart';
import 'package:customer/features/addresses/data/models/saved_address_models.dart';
import 'package:customer/features/addresses/data/repository/address_repository.dart';
import 'package:customer/features/orders/data/models/checkout_delivery_draft.dart';
import 'package:customer/features/orders/presentation/pages/checkout_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'address_state.dart';

class AddressController extends StateNotifier<AddressState> {
  AddressController({
    required AddressRepository repo,
    required LocationService loc,
    required Future<bool> Function() isLoggedIn,
  }) : _repo = repo,
       _loc = loc,
       _isLoggedIn = isLoggedIn,
       super(const AddressState.initial()) {
    load();
  }

  final AddressRepository _repo;
  final LocationService _loc;
  final Future<bool> Function() _isLoggedIn;
  int _loadVersion = 0;
  //  RAM cache theo session (kill app là mất)
  static CurrentLocation? _sessionCurrent;

  Future<void> load({bool force = false}) async {
    final requestVersion = ++_loadVersion;

    if (!force && state.current != null) {
      state = state.copyWith(isFetching: false, didLoad: true, error: null);
      await _syncSavedOnly();
      return;
    }

    if (!force && _sessionCurrent != null) {
      state = state.copyWith(
        isFetching: false,
        didLoad: true,
        current: _sessionCurrent,
        error: null,
      );
      await _syncSavedOnly();
      return;
    }

    state = state.copyWith(isFetching: true, error: null);

    try {
      final pos = await _loc.getCurrentLocation();
      final addr = await _repo
          .reversePublic(lat: pos.lat, lng: pos.lng)
          .catchError((_) => null);

      if (requestVersion != _loadVersion) return;

      final gpsCurrent = CurrentLocation(
        lat: pos.lat,
        lng: pos.lng,
        address: addr,
      );

      _sessionCurrent ??= gpsCurrent;

      if (await _isLoggedIn()) {
        await _repo
            .updateMyLocation(lat: pos.lat, lng: pos.lng, address: addr)
            .catchError((_) {});
      }

      List<SavedAddress> saved = const [];
      if (await _isLoggedIn()) {
        saved = await _repo.listMySavedAddresses();
      }

      if (requestVersion != _loadVersion) return;

      state = state.copyWith(
        isFetching: false,
        didLoad: true,
        current: _sessionCurrent ?? gpsCurrent,
        deviceLocation: gpsCurrent,
        saved: saved,
      );
    } catch (e) {
      if (requestVersion != _loadVersion) return;

      state = state.copyWith(
        isFetching: false,
        didLoad: true,
        error: e.toString(),
      );
    }
  }

  Future<void> setCurrentManual({
    required String address,
    required double lat,
    required double lng,
    String? receiverName,
    String? receiverPhone,
    String? deliveryNote,
    bool syncBackend = true,
  }) async {
    _loadVersion++;

    final cur = CurrentLocation(
      lat: lat,
      lng: lng,
      address: address,
      receiverName: receiverName,
      receiverPhone: receiverPhone,
      deliveryNote: deliveryNote,
    );

    _sessionCurrent = cur;
    state = state.copyWith(current: cur);

    if (syncBackend && await _isLoggedIn()) {
      await _repo
          .updateMyLocation(
            lat: lat,
            lng: lng,
            address: address,
            receiverName: receiverName,
            receiverPhone: receiverPhone,
            deliveryNote: deliveryNote,
          )
          .catchError((_) {});
    }
  }

  Future<void> setCurrentFromCheckoutDraft(CheckoutDeliveryDraft draft) async {
    _loadVersion++;

    final cur = CurrentLocation(
      address: draft.address,
      lat: draft.lat,
      lng: draft.lng,
      receiverName: draft.receiverName,
      receiverPhone: draft.receiverPhone,
      deliveryNote: draft.addressNote,
    );

    _sessionCurrent = cur;
    state = state.copyWith(current: cur);
  }

  //  chỉ sync saved, không đụng GPS
  Future<void> _syncSavedOnly() async {
    final loggedIn = await _isLoggedIn();
    if (!loggedIn) {
      // logout -> clear saved tránh dính data cũ
      if (state.saved.isNotEmpty) {
        state = state.copyWith(saved: const []);
      }
      return;
    }
    await reloadSaved();
  }

  Future<void> reloadSaved() async {
    if (!await _isLoggedIn()) return;
    try {
      final saved = await _repo.listMySavedAddresses();
      state = state.copyWith(saved: saved);
    } catch (_) {}
  }

  Future<void> createSaved({
    required String address,
    double? lat,
    double? lng,
    String? receiverName,
    String? receiverPhone,
    String? deliveryNote,
  }) async {
    if (!await _isLoggedIn()) return;

    await _repo.createMySavedAddress(
      address: address,
      lat: lat,
      lng: lng,
      receiverName: receiverName,
      receiverPhone: receiverPhone,
      deliveryNote: deliveryNote,
    );

    await reloadSaved();
  }

  Future<void> useSavedAsCurrent(SavedAddress a) async {
    if (!await _isLoggedIn()) return;

    await _repo.useSavedAsCurrent(a.id);

    final cur = CurrentLocation(
      lat: a.lat ?? (state.current?.lat ?? 0),
      lng: a.lng ?? (state.current?.lng ?? 0),
      address: a.address,
      receiverName: a.receiverName,
      receiverPhone: a.receiverPhone,
      deliveryNote: a.deliveryNote,
    );

    //  update state + RAM cache
    _sessionCurrent = cur;
    state = state.copyWith(current: cur);
  }

  Future<void> updateSaved(
    String id, {
    String? address,
    double? lat,
    double? lng,
    String? receiverName,
    String? receiverPhone,
    String? deliveryNote,
  }) async {
    if (!await _isLoggedIn()) return;

    await _repo.updateMySavedAddress(
      id,
      address: address,
      lat: lat,
      lng: lng,
      receiverName: receiverName,
      receiverPhone: receiverPhone,
      deliveryNote: deliveryNote,
    );

    await reloadSaved();
  }

  Future<void> deleteSaved(String id) async {
    if (!await _isLoggedIn()) return;

    await _repo.deleteMySavedAddress(id);
    await reloadSaved();
  }

  // /// Tap 1 địa chỉ đã lưu => set current_location ở BE + cập nhật UI current rồi pop về Home
  // Future<void> useSavedAsCurrent(SavedAddress a) async {
  //   if (!await _isLoggedIn()) return;

  //   await _repo.useSavedAsCurrent(a.id);

  //   // Update UI ngay (khỏi đợi load lại)
  //   state = state.copyWith(
  //     current: CurrentLocation(
  //       lat: a.lat ?? (state.current?.lat ?? 0),
  //       lng: a.lng ?? (state.current?.lng ?? 0),
  //       address: a.address,
  //     ),
  //   );
  // }
}
