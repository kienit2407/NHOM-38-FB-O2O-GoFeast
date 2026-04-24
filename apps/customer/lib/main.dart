import 'dart:math' as math;
import 'dart:ui';

import 'package:customer/app/routes/app_router.dart';
import 'package:customer/core/di/providers.dart';
import 'package:customer/firebase_options.dart';
import 'package:customer/features/dinein/presentation/widgets/active_session_overlay.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/adapters.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  final overrides = await bootstrapOverrides();
  await Hive.initFlutter();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('Firebase init OK');
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(ProviderScope(overrides: overrides, child: const MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  Offset? _overlayPosition;
  bool _draggingOverlay = false;
  GoRouter? _boundRouter;
  String _currentPath = '/';

  bool _isOrderingFlowPath(String path) {
    return path.startsWith('/merchant/') ||
        path.startsWith('/product/') ||
        path.startsWith('/checkout/') ||
        path.startsWith('/search');
  }

  bool _showOverlayOnPath(String path) {
    if (_isOrderingFlowPath(path)) return false;
    return path == '/';
  }

  String _readSafeRouterPath(GoRouter router) {
    try {
      final path = router.state.uri.path;
      if (path.isNotEmpty) return path;
    } catch (_) {}

    try {
      final path = router.routeInformationProvider.value.uri.path;
      if (path.isNotEmpty) return path;
    } catch (_) {}

    return _currentPath;
  }

  void _bindRouter(GoRouter router) {
    if (identical(_boundRouter, router)) return;

    _boundRouter?.routerDelegate.removeListener(_handleRouteChanged);
    _boundRouter = router;
    _currentPath = _readSafeRouterPath(router);
    _boundRouter?.routerDelegate.addListener(_handleRouteChanged);
  }

  void _handleRouteChanged() {
    final router = _boundRouter;
    if (!mounted || router == null) return;

    final nextPath = _readSafeRouterPath(router);
    if (nextPath == _currentPath) return;

    setState(() {
      _currentPath = nextPath;
    });
  }

  Offset _defaultOverlayPosition({required double maxX, required double maxY}) {
    return Offset(maxX, maxY);
  }

  Offset _clampOverlayPosition(
    Offset value, {
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
  }) {
    return Offset(
      value.dx.clamp(minX, maxX).toDouble(),
      value.dy.clamp(minY, maxY).toDouble(),
    );
  }

  Offset _snapToNearestEdge(
    Offset value, {
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
  }) {
    final distances = <String, double>{
      'left': (value.dx - minX).abs(),
      'right': (value.dx - maxX).abs(),
      'top': (value.dy - minY).abs(),
      'bottom': (value.dy - maxY).abs(),
    };

    final edge = distances.entries
        .reduce((a, b) => a.value <= b.value ? a : b)
        .key;

    switch (edge) {
      case 'left':
        return Offset(minX, value.dy);
      case 'right':
        return Offset(maxX, value.dy);
      case 'top':
        return Offset(value.dx, minY);
      case 'bottom':
      default:
        return Offset(value.dx, maxY);
    }
  }

  @override
  void dispose() {
    _boundRouter?.routerDelegate.removeListener(_handleRouteChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    _bindRouter(router);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) {
        final activeDineIn = ref.watch(dineInSessionProvider).context;
        final appChild = child ?? const SizedBox.shrink();
        if (activeDineIn == null) return appChild;

        if (!_showOverlayOnPath(_currentPath)) return appChild;

        final media = MediaQuery.of(context);
        final size = media.size;
        final safeTop = media.padding.top;
        final safeBottom = media.padding.bottom;

        final overlayWidth = math.min(240.0, size.width - 24);
        const overlayHeight = 56.0;
        const horizontalMargin = 12.0;
        const topMargin = 12.0;
        const bottomReserved = 84.0;

        final minX = horizontalMargin;
        final maxX = math.max(
          horizontalMargin,
          size.width - overlayWidth - horizontalMargin,
        );
        final minY = safeTop + topMargin;
        final maxY = math.max(
          minY,
          size.height - overlayHeight - safeBottom - bottomReserved,
        );

        final resolvedPosition = _clampOverlayPosition(
          _overlayPosition ?? _defaultOverlayPosition(maxX: maxX, maxY: maxY),
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
        );

        return Stack(
          children: [
            appChild,
            AnimatedPositioned(
              duration: _draggingOverlay
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              left: resolvedPosition.dx,
              top: resolvedPosition.dy,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) {
                  setState(() => _draggingOverlay = true);
                },
                onPanUpdate: (details) {
                  final base = _overlayPosition ?? resolvedPosition;
                  final moved = Offset(
                    base.dx + details.delta.dx,
                    base.dy + details.delta.dy,
                  );
                  setState(() {
                    _overlayPosition = _clampOverlayPosition(
                      moved,
                      minX: minX,
                      maxX: maxX,
                      minY: minY,
                      maxY: maxY,
                    );
                  });
                },
                onPanEnd: (_) {
                  final base = _overlayPosition ?? resolvedPosition;
                  setState(() {
                    _draggingOverlay = false;
                    _overlayPosition = _snapToNearestEdge(
                      _clampOverlayPosition(
                        base,
                        minX: minX,
                        maxX: maxX,
                        minY: minY,
                        maxY: maxY,
                      ),
                      minX: minX,
                      maxX: maxX,
                      minY: minY,
                      maxY: maxY,
                    );
                  });
                },
                onPanCancel: () {
                  setState(() => _draggingOverlay = false);
                },
                child: SizedBox(
                  width: overlayWidth,
                  child: ActiveDineInSessionOverlay(
                    session: activeDineIn,
                    onTap: () {
                      router.push(
                        '/merchant/${activeDineIn.merchantId}',
                        extra: {
                          'mode': 'dine_in',
                          'dineInContext': activeDineIn,
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
