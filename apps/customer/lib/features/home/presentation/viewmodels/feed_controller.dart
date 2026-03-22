import 'package:customer/features/home/data/repository/feed_repository.dart';
import 'package:customer/features/home/presentation/viewmodels/feed_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FeedController extends StateNotifier<FeedState> {
  FeedController({required FeedRepository repo})
    : _repo = repo,
      super(const FeedState.initial());

  final FeedRepository _repo;

  bool _isSameSpot(double lat, double lng) {
    final a = state.lastLat;
    final b = state.lastLng;
    if (a == null || b == null) return false;
    // ~50-100m threshold (tùy bạn)
    return (a - lat).abs() < 0.0007 && (b - lng).abs() < 0.0007;
  }

  bool _isValidCoord(double lat, double lng) {
    if (lat == 0 && lng == 0) return false;
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  Future<void> ensureForLocation({
    required double lat,
    required double lng,
    bool force = false,
  }) async {
    if (!_isValidCoord(lat, lng)) return;
    if (state.isLoading) return;
    if (!force && _isSameSpot(lat, lng) && state.data != null) return;
    await fetch(lat: lat, lng: lng, force: force);
  }

  Future<void> fetch({
    required double lat,
    required double lng,
    bool force = false,
  }) async {
    if (!_isValidCoord(lat, lng)) return;

    state = state.copyWith(
      isLoading: true,
      error: null,
      lastLat: lat,
      lastLng: lng,
    );

    try {
      final data = await _repo.getHomeFeed(lat: lat, lng: lng);
      state = state.copyWith(isLoading: false, data: data, error: null);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}
