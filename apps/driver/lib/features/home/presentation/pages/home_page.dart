import 'dart:io';
import 'dart:math' as math;

import 'package:driver/app/theme/app_color.dart';
import 'package:driver/core/di/providers.dart';
import 'package:driver/features/drivers/presentation/viewmodels/driver_delivery_tracking_controller.dart';
import 'package:driver/features/drivers/presentation/viewmodels/driver_offer_controller.dart';
import 'package:driver/features/drivers/presentation/widgets/driver_current_job_sheet.dart';
import 'package:driver/features/drivers/presentation/widgets/driver_offer_bottom_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  GoogleMapController? _mapController;

  LatLng? _fallbackLocation;
  bool _loadingLocation = true;
  bool _movingCamera = false;

  late final DriverDeliveryTrackingController _trackingCtrl;

  ProviderSubscription<DriverOfferState>? _offerSubscription;
  ProviderSubscription<dynamic>? _liveSubscription;
  ProviderSubscription<DriverDeliveryTrackingState>? _trackingSubscription;

  final ImagePicker _picker = ImagePicker();

  Set<Polyline> _routePolylines = {};
  LatLng? _merchantMarker;
  LatLng? _customerMarker;

  bool _isFetchingRoute = false;
  DateTime? _lastRouteFetchAt;
  LatLng? _lastRouteOrigin;
  String? _lastRouteTargetKey;

  static const LatLng _defaultCenter = LatLng(10.8231, 106.6297);

  @override
  void initState() {
    super.initState();

    _trackingCtrl = ref.read(driverDeliveryTrackingControllerProvider.notifier);

    _trackingSubscription = ref.listenManual<DriverDeliveryTrackingState>(
      driverDeliveryTrackingControllerProvider,
      (previous, next) async {
        final prevStatus = previous?.status ?? '';
        final nextStatus = next.status;

        if (next.error != null && next.error != previous?.error && mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(next.error!)));
        }

        if (next.hasOrder && prevStatus != nextStatus) {
          await _refreshRouteForCurrentOrder();
        }

        if (!next.hasOrder && mounted) {
          setState(() {
            _routePolylines = {};
            _merchantMarker = null;
            _customerMarker = null;
          });
        }
      },
    );

    _liveSubscription = ref.listenManual(driverLiveControllerProvider, (
      previous,
      next,
    ) async {
      final prevError = previous?.error;
      final nextError = next.error;

      if (nextError != null && nextError != prevError && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(nextError)));
      }

      if (next.lat != null && next.lng != null && mounted) {
        setState(() {
          _fallbackLocation = LatLng(next.lat!, next.lng!);
        });

        if (ref.read(driverOfferControllerProvider).hasCurrentOrder) {
          await _refreshRouteForCurrentOrder();
        }
      }
    });

    _offerSubscription = ref.listenManual<DriverOfferState>(
      driverOfferControllerProvider,
      (previous, next) async {
        final prevOrderId = previous?.currentOrderId ?? '';
        final nextOrderId = next.currentOrderId ?? '';

        if (next.error != null && next.error != previous?.error && mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(next.error!)));
        }

        if (nextOrderId.isNotEmpty && nextOrderId != prevOrderId) {
          final order = next.currentOrder!;
          _trackingCtrl.bindOrder(
            orderId: nextOrderId,
            orderNumber: order['orderNumber']?.toString(),
            initialStatus: order['status']?.toString(),
            merchantName: order['merchantName']?.toString(),
            merchantAddress: order['merchantAddress']?.toString(),
            customerName: order['customerName']?.toString(),
            customerPhone: order['customerPhone']?.toString(),
            customerAddress: order['customerAddress']?.toString(),
          );
          await _refreshRouteForCurrentOrder();
        }

        if (prevOrderId.isNotEmpty && nextOrderId.isEmpty) {
          _trackingCtrl.clear();
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _restoreCurrentOrderIfNeeded();
      await _loadMyLocation(moveCamera: true);

      if (ref.read(driverOfferControllerProvider).hasCurrentOrder) {
        await _refreshRouteForCurrentOrder();
      }
    });
  }

  @override
  void dispose() {
    _offerSubscription?.close();
    _liveSubscription?.close();
    _trackingSubscription?.close();
    _trackingCtrl.clear();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _restoreCurrentOrderIfNeeded() async {
    try {
      final current = await ref
          .read(driverOrderRepositoryProvider)
          .fetchCurrentOrder();
      if (current == null) return;

      ref
          .read(driverOfferControllerProvider.notifier)
          .restoreCurrentOrder(current);

      _trackingCtrl.bindOrder(
        orderId: current['orderId']?.toString() ?? '',
        orderNumber: current['orderNumber']?.toString(),
        initialStatus: current['status']?.toString(),
        merchantName: current['merchantName']?.toString(),
        merchantAddress: current['merchantAddress']?.toString(),
        customerName: current['customerName']?.toString(),
        customerPhone: current['customerPhone']?.toString(),
        customerAddress: current['customerAddress']?.toString(),
      );
    } catch (_) {}
  }

  Future<List<String>> _uploadProofFiles(List<File> files) async {
    try {
      return await ref
          .read(driverOrderRepositoryProvider)
          .uploadProofImages(files);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Upload ảnh thất bại: $e')));
      }
      return [];
    }
  }

  Future<void> _appendUploadedProofs(List<File> files) async {
    if (files.isEmpty) return;

    final urls = await _uploadProofFiles(files);
    if (urls.isEmpty) return;

    final current = ref
        .read(driverDeliveryTrackingControllerProvider)
        .proofImages;
    _trackingCtrl.setProofImages([...current, ...urls]);
  }

  Future<File?> _takePhotoFromCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<List<File>> _pickManyImagesFromLibrary() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return [];

    return result.paths.whereType<String>().map((path) => File(path)).toList();
  }

  Future<void> _takeFirstProofPhoto() async {
    final file = await _takePhotoFromCamera();
    if (file == null) return;
    await _appendUploadedProofs([file]);
  }

  Future<void> _addProofFromLibrary() async {
    final files = await _pickManyImagesFromLibrary();
    if (files.isEmpty) return;
    await _appendUploadedProofs(files);
  }

  Future<void> _showProofSourceSheet() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Chọn ảnh minh chứng',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColor.primaryLight,
                    child: const Icon(
                      Icons.photo_library_outlined,
                      color: AppColor.primary,
                    ),
                  ),
                  title: const Text(
                    'Chọn từ thư viện',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Dùng ảnh có sẵn để test luồng hoàn thành đơn',
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _addProofFromLibrary();
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColor.primaryLight,
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: AppColor.primary,
                    ),
                  ),
                  title: const Text(
                    'Chụp ảnh',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Mở camera để chụp ảnh minh chứng'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _takeFirstProofPhoto();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadMyLocation({bool moveCamera = true}) async {
    if (!mounted) return;

    setState(() {
      _loadingLocation = true;
    });

    try {
      final loc = await ref.read(locationServiceProvider).getCurrentLocation();
      final target = LatLng(loc.lat, loc.lng);

      if (!mounted) return;

      setState(() {
        _fallbackLocation = target;
      });

      if (moveCamera && _mapController != null) {
        await _animateTo(target);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không lấy được vị trí: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _loadingLocation = false;
        });
      }
    }
  }

  Future<void> _animateTo(LatLng target) async {
    if (_mapController == null) return;

    setState(() {
      _movingCamera = true;
    });

    try {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 17),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _movingCamera = false;
        });
      }
    }
  }

  Future<void> _confirmToggleOnline(bool isOnline) async {
    final turningOn = !isOnline;

    await showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: Text(turningOn ? 'Bật nhận chuyến?' : 'Tắt nhận chuyến?'),
          content: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              turningOn
                  ? 'Bạn có muốn bật trạng thái sẵn sàng nhận chuyến không?'
                  : 'Bạn có muốn tắt trạng thái nhận chuyến không?',
            ),
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text(
                'Huỷ',
                style: TextStyle(color: CupertinoColors.systemGrey),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            CupertinoDialogAction(
              isDestructiveAction: !turningOn,
              child: Text(
                turningOn ? 'Bật' : 'Tắt',
                style: TextStyle(
                  color: turningOn
                      ? CupertinoColors.activeGreen
                      : CupertinoColors.systemRed,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await ref
                    .read(driverLiveControllerProvider.notifier)
                    .setAvailability(turningOn);
              },
            ),
          ],
        );
      },
    );
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;

    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;

    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final aa =
        sinDLat * sinDLat + sinDLng * sinDLng * math.cos(lat1) * math.cos(lat2);
    final c = 2 * math.asin(math.sqrt(aa));
    return earthRadius * c;
  }

  Future<void> _refreshRouteForCurrentOrder({bool force = false}) async {
    if (_isFetchingRoute && !force) return;
    _isFetchingRoute = true;

    try {
      final order = ref.read(driverOfferControllerProvider).currentOrder;
      if (order == null) {
        if (mounted) {
          setState(() {
            _routePolylines = {};
            _merchantMarker = null;
            _customerMarker = null;
          });
        }
        return;
      }

      final live = ref.read(driverLiveControllerProvider);
      final driverLat = live.lat;
      final driverLng = live.lng;
      if (driverLat == null || driverLng == null) return;

      final status = ref.read(driverDeliveryTrackingControllerProvider).status;

      final merchantLat = (order['merchantLat'] as num?)?.toDouble();
      final merchantLng = (order['merchantLng'] as num?)?.toDouble();
      final customerLat = (order['customerLat'] as num?)?.toDouble();
      final customerLng = (order['customerLng'] as num?)?.toDouble();

      final goingToCustomer = [
        'picked_up',
        'delivering',
        'delivered',
      ].contains(status);

      final targetLat = goingToCustomer ? customerLat : merchantLat;
      final targetLng = goingToCustomer ? customerLng : merchantLng;

      if (targetLat == null || targetLng == null) return;

      final origin = LatLng(driverLat, driverLng);
      final target = LatLng(targetLat, targetLng);
      final targetKey = '${target.latitude},${target.longitude},$status';

      final now = DateTime.now();
      final recentlyFetched =
          _lastRouteFetchAt != null &&
          now.difference(_lastRouteFetchAt!) < const Duration(seconds: 12);

      final movedLittle =
          _lastRouteOrigin != null &&
          _distanceMeters(origin, _lastRouteOrigin!) < 40;

      if (!force &&
          recentlyFetched &&
          movedLittle &&
          _lastRouteTargetKey == targetKey) {
        return;
      }

      final res = await ref
          .read(driverOrderRepositoryProvider)
          .fetchRoute(
            originLat: driverLat,
            originLng: driverLng,
            destinationLat: targetLat,
            destinationLng: targetLng,
            mode: 'motorcycling',
          );

      if (res == null) return;

      List<LatLng> points = [];

      final polyline = res['polyline']?.toString();
      if (polyline != null && polyline.isNotEmpty) {
        points = _decodePolyline(polyline);
      } else {
        final rawPoints = res['route_points'];
        if (rawPoints is List) {
          points = rawPoints.whereType<List>().where((e) => e.length >= 2).map((
            e,
          ) {
            final lng = (e[0] as num).toDouble();
            final lat = (e[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();
        }
      }

      if (!mounted) return;

      setState(() {
        _merchantMarker = merchantLat != null && merchantLng != null
            ? LatLng(merchantLat, merchantLng)
            : null;

        _customerMarker = customerLat != null && customerLng != null
            ? LatLng(customerLat, customerLng)
            : null;

        _routePolylines = points.length >= 2
            ? {
                Polyline(
                  polylineId: const PolylineId('route_bg'),
                  points: points,
                  width: 10,
                  color: Colors.white,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                  jointType: JointType.round,
                  zIndex: 1,
                ),
                Polyline(
                  polylineId: const PolylineId('active_route'),
                  points: points,
                  width: 6,
                  color: AppColor.primary,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                  jointType: JointType.round,
                  zIndex: 2,
                ),
              }
            : {};
      });

      _lastRouteFetchAt = now;
      _lastRouteOrigin = origin;
      _lastRouteTargetKey = targetKey;
    } finally {
      _isFetchingRoute = false;
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> poly = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int b;
      int shift = 0;
      int result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      final dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      final dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return poly;
  }

  Set<Marker> _buildMarkers(LatLng? current, bool isOnline) {
    final markers = <Marker>{};

    if (current != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('my_location'),
          position: current,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isOnline ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: isOnline ? 'Bạn đang online' : 'Bạn đang tạm nghỉ',
          ),
        ),
      );
    }

    if (_merchantMarker != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('merchant_marker'),
          position: _merchantMarker!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Điểm lấy hàng'),
        ),
      );
    }

    if (_customerMarker != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('customer_marker'),
          position: _customerMarker!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Điểm giao hàng'),
        ),
      );
    }

    return markers;
  }

  Widget _buildAvatar(String? avatarUrl) {
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: AppColor.surface,
        backgroundImage: NetworkImage(avatarUrl),
      );
    }

    return const CircleAvatar(
      radius: 24,
      backgroundColor: AppColor.primaryLight,
      child: Icon(Icons.person, color: AppColor.primary),
    );
  }

  Widget _buildInfoChip({
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  Widget _buildStatusChip(bool isOnline) {
    final bg = isOnline
        ? AppColor.success.withOpacity(.12)
        : AppColor.warning.withOpacity(.12);
    final fg = isOnline ? AppColor.success : AppColor.warning;

    return _buildInfoChip(
      label: isOnline ? 'Đang nhận chuyến' : 'Tạm nghỉ',
      bg: bg,
      fg: fg,
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required VoidCallback? onTap,
    Color iconColor = AppColor.textPrimary,
    bool loading = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CupertinoActivityIndicator(),
                  )
                : Icon(icon, color: iconColor),
          ),
        ),
      ),
    );
  }

  void _openCurrentOrderDetail(Map<String, dynamic> order) {
    final orderId = order['orderId']?.toString() ?? '';
    if (orderId.isEmpty) return;

    context.push(
      '/current-order',
      extra: {
        'orderId': orderId,
        'orderNumber': order['orderNumber']?.toString(),
        'initialStatus': order['status']?.toString() ?? 'driver_assigned',
        'merchantName': order['merchantName']?.toString() ?? '',
        'merchantAddress': order['merchantAddress']?.toString() ?? '',
        'customerName': order['customerName']?.toString() ?? '',
        'customerPhone': order['customerPhone']?.toString() ?? '',
        'customerAddress': order['customerAddress']?.toString() ?? '',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(driverAuthControllerProvider);
    final live = ref.watch(driverLiveControllerProvider);
    final offerState = ref.watch(driverOfferControllerProvider);
    final trackingState = ref.watch(driverDeliveryTrackingControllerProvider);

    final me = auth.me;
    final isOnline = live.acceptFoodOrders;

    final displayName = (me?.fullName?.trim().isNotEmpty ?? false)
        ? me!.fullName!.trim()
        : 'Tài xế';

    final currentLocation = (live.lat != null && live.lng != null)
        ? LatLng(live.lat!, live.lng!)
        : _fallbackLocation;

    final bottomNavInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColor.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: currentLocation ?? _defaultCenter,
                zoom: currentLocation != null ? 17 : 13,
              ),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: true,
              mapToolbarEnabled: false,
              markers: _buildMarkers(currentLocation, isOnline),
              polylines: _routePolylines,
              onMapCreated: (controller) async {
                _mapController = controller;
                if (currentLocation != null) {
                  await _animateTo(currentLocation);
                }
              },
            ),
          ),

          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(.10),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(.04),
                    ],
                    stops: const [0, 0.18, 0.72, 1],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                            color: Colors.black.withOpacity(.08),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          _buildAvatar(me?.avatarUrl),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColor.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _buildStatusChip(isOnline),
                                    if (trackingState.hasOrder) ...[
                                      _buildInfoChip(
                                        label: 'Đang có chuyến',
                                        bg: AppColor.primaryLight,
                                        fg: AppColor.primary,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    children: [
                      _buildTopActionButton(
                        icon: isOnline
                            ? CupertinoIcons.power
                            : CupertinoIcons.play_fill,
                        iconColor: isOnline
                            ? AppColor.success
                            : AppColor.warning,
                        loading: live.isUpdatingAvailability,
                        onTap: live.isUpdatingAvailability
                            ? null
                            : () => _confirmToggleOnline(isOnline),
                      ),
                      const SizedBox(height: 10),
                      _buildTopActionButton(
                        icon: CupertinoIcons.location,
                        onTap: (_loadingLocation || _movingCamera)
                            ? null
                            : () async {
                                if (currentLocation != null) {
                                  await _animateTo(currentLocation);
                                } else {
                                  await _loadMyLocation(moveCamera: true);
                                }

                                if (isOnline) {
                                  await ref
                                      .read(
                                        driverLiveControllerProvider.notifier,
                                      )
                                      .sendCurrentLocationNow();
                                }
                              },
                      ),
                      const SizedBox(height: 10),
                      _buildTopActionButton(
                        icon: CupertinoIcons.refresh,
                        onTap: () async {
                          await _loadMyLocation(moveCamera: true);
                          if (isOnline) {
                            await ref
                                .read(driverLiveControllerProvider.notifier)
                                .sendCurrentLocationNow();
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildTopActionButton(
                        icon: CupertinoIcons.square_arrow_right,
                        iconColor: AppColor.danger,
                        onTap: () async {
                          await ref
                              .read(driverAuthControllerProvider.notifier)
                              .logout();
                          if (context.mounted) context.go('/signin');
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (_loadingLocation || _movingCamera)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 92,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                      color: Colors.black.withOpacity(.08),
                    ),
                  ],
                ),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CupertinoActivityIndicator(radius: 8),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Đang cập nhật vị trí...',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColor.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (offerState.hasCurrentOrder && !offerState.hasActiveOffer)
            Positioned.fill(
              bottom: bottomNavInset,
              child: DriverCurrentJobSheet(
                order: offerState.currentOrder!,
                onViewDetail: () {
                  _openCurrentOrderDetail(offerState.currentOrder!);
                },
                trackingState: trackingState,
                onArrived: () => _trackingCtrl.markArrived(),
                onPickedUp: () => _trackingCtrl.markPickedUp(),
                onStartDelivering: () => _trackingCtrl.markDelivering(),
                onDelivered: () => _trackingCtrl.markDelivered(),
                onTakeProofPhoto: _showProofSourceSheet,
                onAddProofFromLibrary: _addProofFromLibrary,
                onComplete: () => _trackingCtrl.completeOrder(),
              ),
            ),

          if (offerState.hasActiveOffer)
            Positioned.fill(
              bottom: bottomNavInset,
              child: DriverOfferBottomSheet(
                state: offerState,
                onAccept: () async {
                  await ref
                      .read(driverOfferControllerProvider.notifier)
                      .acceptCurrentOffer();
                },
                onReject: () async {
                  await ref
                      .read(driverOfferControllerProvider.notifier)
                      .rejectCurrentOffer();
                },
              ),
            ),
        ],
      ),
    );
  }
}
