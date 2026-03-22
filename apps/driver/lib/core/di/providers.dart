import 'package:dio/dio.dart';
import 'package:driver/core/network/dio_client.dart';
import 'package:driver/core/push/fcm_service.dart';
import 'package:driver/core/push/local_notification_service.dart';
import 'package:driver/core/realtime/socket_bootstrap_controller.dart';
import 'package:driver/core/realtime/socket_provider.dart';
import 'package:driver/core/services/location_service.dart';
import 'package:driver/core/shared/contants/url_config.dart';
import 'package:driver/core/storage/device_id_storage.dart';
import 'package:driver/core/storage/token_storage.dart';
import 'package:driver/features/auth/data/repository/driver_auth_repository.dart';
import 'package:driver/features/auth/presentation/viewmodels/driver_auth_controller.dart';
import 'package:driver/features/auth/presentation/viewmodels/driver_auth_state.dart';
import 'package:driver/features/drivers/data/repository/driver_live_repository.dart';
import 'package:driver/features/drivers/data/repository/driver_order_repository.dart';
import 'package:driver/features/drivers/presentation/viewmodels/driver_delivery_tracking_controller.dart';
import 'package:driver/features/drivers/presentation/viewmodels/driver_live_controller.dart';
import 'package:driver/features/drivers/presentation/viewmodels/driver_live_state.dart';
import 'package:driver/features/drivers/presentation/viewmodels/driver_offer_controller.dart';
import 'package:driver/features/earnings/data/repository/driver_earnings_repository.dart';
import 'package:driver/features/earnings/presentation/viewmodels/driver_earnings_controller.dart';
import 'package:driver/features/earnings/presentation/viewmodels/driver_earnings_state.dart';
import 'package:driver/features/notifications/data/repository/driver_notification_repository.dart';
import 'package:driver/features/notifications/presentation/viewmodels/driver_notification_controller.dart';
import 'package:driver/features/notifications/presentation/viewmodels/driver_notification_state.dart';
import 'package:driver/features/profile/data/repository/driver_profile_repository.dart';
import 'package:driver/features/profile/presentation/viewmodels/driver_profile_controller.dart';
import 'package:driver/features/profile/presentation/viewmodels/driver_profile_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// =======================
/// CORE PROVIDERS
/// =======================
final dioClientProvider = Provider<DioClient>((ref) {
  throw UnimplementedError('dioClientProvider chưa được override');
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  throw UnimplementedError('tokenStorageProvider chưa được override');
});

final fcmServiceProvider = Provider((ref) => FcmService());

/// =======================
/// AUTH PROVIDERS
/// Giữ chung 1 file như bạn muốn
/// =======================
final driverAuthRepositoryProvider = Provider<DriverAuthRepository>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return DriverAuthRepository(dio);
});

final driverAuthControllerProvider =
    StateNotifierProvider<DriverAuthController, DriverAuthState>((ref) {
      final repo = ref.read(driverAuthRepositoryProvider);
      final tokenStorage = ref.read(tokenStorageProvider);
      return DriverAuthController(repo: repo, tokenStorage: tokenStorage);
    });

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});
final driverLiveRepositoryProvider = Provider<DriverLiveRepository>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return DriverLiveRepository(dio);
});

final driverLiveControllerProvider =
    StateNotifierProvider<DriverLiveController, DriverLiveState>((ref) {
      final repo = ref.read(driverLiveRepositoryProvider);
      final locationService = ref.read(locationServiceProvider);

      return DriverLiveController(repo: repo, locationService: locationService);
    });
final localNotificationServiceProvider = Provider<LocalNotificationService>((
  ref,
) {
  return LocalNotificationService();
});

final driverSocketServiceProvider = Provider<DriverSocketService>((ref) {
  final tokenStorage = ref.read(tokenStorageProvider);
  final service = DriverSocketService(tokenStorage);

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});
final driverSocketBootstrapControllerProvider =
    Provider<SocketBootstrapController>((ref) {
      final socketService = ref.read(driverSocketServiceProvider);
      final notificationService = ref.read(localNotificationServiceProvider);

      return SocketBootstrapController(
        ref: ref,
        socketService: socketService,
        notificationService: notificationService,
      );
    });
final driverOrderRepositoryProvider = Provider<DriverOrderRepository>((ref) {
  final dio = ref.read(dioClientProvider);
  return DriverOrderRepository(dio);
});

final driverOfferControllerProvider =
    StateNotifierProvider<DriverOfferController, DriverOfferState>((ref) {
      final socketService = ref.read(driverSocketServiceProvider);
      return DriverOfferController(socketService);
    });

final driverDeliveryTrackingControllerProvider =
    StateNotifierProvider<
      DriverDeliveryTrackingController,
      DriverDeliveryTrackingState
    >((ref) {
      final repo = ref.read(driverOrderRepositoryProvider);
      final socket = ref.read(driverSocketServiceProvider);

      return DriverDeliveryTrackingController(
        orderRepository: repo,
        socketService: socket,
      );
    });
final driverEarningsRepositoryProvider = Provider<DriverEarningsRepository>((
  ref,
) {
  final dio = ref.read(dioClientProvider).dio;
  return DriverEarningsRepository(dio);
});

final driverEarningsControllerProvider =
    StateNotifierProvider<DriverEarningsController, DriverEarningsState>((ref) {
      final repo = ref.read(driverEarningsRepositoryProvider);
      return DriverEarningsController(repo: repo);
    });

final driverNotificationRepositoryProvider =
    Provider<DriverNotificationRepository>((ref) {
      final dio = ref.read(dioClientProvider);
      return DriverNotificationRepository(dio);
    });

final driverNotificationControllerProvider =
    StateNotifierProvider<
      DriverNotificationController,
      DriverNotificationState
    >((ref) {
      final repo = ref.read(driverNotificationRepositoryProvider);
      return DriverNotificationController(repo);
    });
final driverProfileRepositoryProvider = Provider<DriverProfileRepository>((ref) {
  return DriverProfileRepository(ref.read(dioClientProvider));
});

final driverProfileControllerProvider =
    StateNotifierProvider<DriverProfileController, DriverProfileState>((ref) {
  return DriverProfileController(
    ref.read(driverProfileRepositoryProvider),
  );
});
/// =======================
/// BOOTSTRAP
/// =======================
Future<List<Override>> bootstrapOverrides() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ),
  );

  await Hive.initFlutter();

  final tokenStorage = TokenStorage();
  await tokenStorage.init();
  final localNotificationService = LocalNotificationService();
  await localNotificationService.init();
  await localNotificationService.requestPermission();
  final deviceId = await DeviceIdStorage().getDeviceId();

  late final DioClient dioClient;

  Future<(String accessToken, String refreshToken)> refreshTokensFromApi(
    String refreshToken,
  ) async {
    final res = await dioClient.post<Map<String, dynamic>>(
      UrlConfig.refreshToken,
      data: {'refreshToken': refreshToken},
      options: Options(
        extra: const {'__skipAuth': true, '__skipAuthRefresh': true},
      ),
    );

    final body = res.data ?? {};
    final payload = (body['data'] as Map).cast<String, dynamic>();
    final access = payload['accessToken'] as String;
    final refresh = payload['refreshToken'] as String;
    return (access, refresh);
  }

  dioClient = await DioClient.create(
    tokenStorage: tokenStorage,
    baseUrl: UrlConfig.backendBaseUrl,
    deviceId: deviceId,
    refreshTokens: refreshTokensFromApi,
  );

  return [
    tokenStorageProvider.overrideWithValue(tokenStorage),
    dioClientProvider.overrideWithValue(dioClient),
    localNotificationServiceProvider.overrideWithValue(
      localNotificationService,
    ),
  ];
}
