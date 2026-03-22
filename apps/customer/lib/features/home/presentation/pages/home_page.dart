import 'dart:async';
import 'dart:ui';

import 'package:customer/app/theme/app_color.dart';
import 'package:customer/core/di/providers.dart';
import 'package:customer/features/addresses/presentation/viewmodels/address_state.dart';
import 'package:customer/features/auth/presentation/viewmodels/auth_providers.dart';
import 'package:customer/features/home/presentation/widgets/home_feed_sections.dart';
import 'package:customer/features/home/presentation/widgets/home_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:lottie/lottie.dart';

bool _hasValidLatLng(double? lat, double? lng) {
  if (lat == null || lng == null) return false;
  if (lat == 0 && lng == 0) return false;
  return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Timer? _holdTimer;
  bool _allowShowHome = false;
  bool _didListen = false;
  static bool _sessionEnteredHome = false;

  bool _delayStarted = false; // ✅ để không start timer lặp
  @override
  void initState() {
    super.initState();

    final addr = ref.read(addressControllerProvider);
    final hasLoc = addr.current != null;
    final hasErrorNoLoc = addr.error != null && !hasLoc;

    // ✅ Nếu đã có location cache hoặc đã lỗi nhưng vẫn cho vào home
    if (hasLoc || hasErrorNoLoc) {
      _allowShowHome = true;
      _delayStarted = true;
      _sessionEnteredHome = true;
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void onTapFavorite() {
    final auth = ref.read(authViewModelProvider); // đúng provider của bạn
    final user = auth.valueOrNull;

    if (user == null) {
      context.push('/signin');
      return;
    }
    context.push('/favorites');
  }

  Widget _locationScreen(AddressState addr) {
    final addressText = addr.current?.address;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Đang tìm vị trí...',
                style: TextStyle(fontSize: 20, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 300,
                height: 300,
                child: Lottie.asset(
                  'assets/icons/location_seeking.json',
                  delegates: LottieDelegates(
                    values: [
                      ValueDelegate.color(const ['**']),
                    ],
                  ),
                ),
              ),
              if (addressText != null && addressText.trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    addressText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeReal(AddressState addr) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topInset = MediaQuery.paddingOf(context).top;
    final bannerSt = ref.watch(bannerControllerProvider);
    final showCarousel = bannerSt.isLoading || bannerSt.items.isNotEmpty;
    final feedSt = ref.watch(feedControllerProvider);

    final feedLoc = addr.deviceLocation ?? addr.current;
    final lat = feedLoc?.lat;
    final lng = feedLoc?.lng;

    if (_hasValidLatLng(lat, lng)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(feedControllerProvider.notifier)
            .ensureForLocation(lat: lat!, lng: lng!);
      });
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      body: Stack(
        children: [
          //  base background
          const Positioned.fill(child: ColoredBox(color: Color(0xFFF6F6F6))),

          //  scroll nằm trên gradient
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _HomeHeaderDelegate(
                  onTapFavorite: onTapFavorite,
                  locationError: addr.current == null && addr.error != null,
                  topPadding: topInset,
                  addressText: addr.current?.address?.trim(),

                  onTapSearch: () {
                    context.push('/search');
                  },
                  onTapAddress: () {
                    context.push('/address');
                  },
                ),
              ),

              SliverToBoxAdapter(
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 180, // 10 hơi mỏng; 14-18 nhìn mượt hơn
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [0.0, 0.20, 0.45, 1.0],
                                colors: [
                                  Color(0xFFD26D38),
                                  Color(0x99EE4D2D), // 60%
                                  Color(0x1AEE4D2D), // 10%
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          //  nếu có data (hoặc đang loading) thì show carousel
                          if (showCarousel) const HomeCarousel(height: 120),
                          if (showCarousel) const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SliverToBoxAdapter(
                child: HomeFeedSections(
                  userLat: lat,
                  userLng: lng,
                  sections: feedSt.data?.sections ?? const [],
                  isLoading: feedSt.isLoading,
                  error: feedSt.error,
                  onRetry: () {
                    final c = addr.current;
                    if (c?.lat != null && c?.lng != null) {
                      ref
                          .read(feedControllerProvider.notifier)
                          .ensureForLocation(
                            lat: c!.lat,
                            lng: c.lng,
                            force: true,
                          );
                    }
                  },
                ),
              ),

              SliverPadding(
                padding: EdgeInsets.fromLTRB(0, 0, 0, 24 + bottomInset + 88),
                sliver: const SliverToBoxAdapter(child: SizedBox(height: 1)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final addr = ref.watch(addressControllerProvider);

    final hasLoc = addr.current != null;
    final hasErrorNoLoc = addr.error != null && !hasLoc;

    // ✅ Nếu session này đã vào home rồi => KHÔNG BAO GIỜ show màn tìm vị trí nữa
    // (logout/login, switch tab, rebuild... đều không show)
    if (_sessionEnteredHome) {
      return _homeReal(addr);
    }

    // ====== Chỉ còn áp dụng cho lần đầu mở app trong session ======

    // Đang fetch và chưa có location => show màn tìm vị trí
    if (addr.isFetching && !hasLoc) {
      return _locationScreen(addr);
    }

    // Lỗi (GPS off / permission) => vào home luôn, và đánh dấu session đã vào home
    if (hasErrorNoLoc) {
      _sessionEnteredHome = true;
      return _homeReal(addr);
    }

    // Có location => giữ 2s rồi vào home (chỉ 1 lần duy nhất)
    if (hasLoc && !_allowShowHome) {
      if (!_delayStarted) {
        _delayStarted = true;
        _holdTimer?.cancel();
        _holdTimer = Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          setState(() {
            _allowShowHome = true;
            _sessionEnteredHome = true;
          });
        });
      }
      return _locationScreen(addr); // trong 2s vẫn show
    }

    // Nếu đã qua 2s
    if (hasLoc && _allowShowHome) {
      _sessionEnteredHome = true;
      return _homeReal(addr);
    }

    // fallback
    return _locationScreen(addr);
  }
}

class _HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  _HomeHeaderDelegate({
    required this.locationError,
    required this.topPadding,
    required this.addressText,
    required this.onTapSearch,
    required this.onTapAddress,
    required this.onTapFavorite,
    this.hintText = 'Siêu Deal Đầu Năm, Giảm Tới 50%',
  });
  final VoidCallback onTapFavorite; // ✅
  final double topPadding;
  final String? addressText;
  final VoidCallback onTapSearch;
  final VoidCallback onTapAddress;
  final String hintText;
  final bool locationError;
  static const double _padX = 16;
  static const double _searchH = 44;
  static const double _addressRowH = 44;
  static const double _gap = 10;
  static const double _bottomPadExpanded = 16;
  static const double _bottomPadCollapsed = 12;

  double get maxExtent =>
      topPadding + 6 + _addressRowH + 6 + _searchH + 10; // nhỏ hơn

  @override
  double get minExtent => topPadding + 4 + _searchH + 8; // nhỏ hơn
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = (maxExtent - minExtent);
    final t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);

    final addressOpacity = (1.0 - t * 1.4).clamp(0.0, 1.0);
    final addressDy = lerpDouble(0, -12, t)!;

    final searchTopExpanded = topPadding + 12 + _addressRowH + _gap;
    final searchTopCollapsed = topPadding + 6;
    final searchTop = lerpDouble(searchTopExpanded, searchTopCollapsed, t)!;

    final shownAddress = (addressText != null && addressText!.trim().isNotEmpty)
        ? addressText!.trim()
        : (locationError
              ? 'Chưa bật vị trí (bấm để chọn địa chỉ)'
              : 'Đang lấy địa chỉ giao đến...');

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Gradient CHÉO (ngang/chéo) như header bạn muốn
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xFFD26E36),
                  Color(0xFFD06134),
                  Color(0xFFCE5533),
                ],
              ),
            ),
          ),

          // highlight mềm góc phải trên
          Positioned(
            right: 20,
            top: 20,
            child: SizedBox(
              height: 100,
              child: Opacity(
                opacity: .1,
                child: Image.asset('assets/images/cover_header.png'),
              ),
            ),
          ),

          //  overlay khi collapsed: GIẢM NHIỀU để không làm “body bị mờ”
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5A1F).withOpacity(t * 0.10),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padX),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: topPadding + 8 + addressDy,
                  child: Opacity(
                    opacity: addressOpacity,
                    child: InkWell(
                      onTap: onTapAddress,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Giao đến:',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    shownAddress,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  top: searchTop,
                  child: Row(
                    children: [
                      Expanded(
                        // <--- Thêm Expanded ở đây
                        child: _SearchPill(
                          height: _searchH,
                          hintText: hintText,
                          onTap: onTapSearch,
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: onTapFavorite,
                        icon: Icon(Iconsax.heart, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (t > 0.85 || overlapsContent)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 1,
                color: Colors.black.withOpacity(0.10),
              ),
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HomeHeaderDelegate oldDelegate) {
    return oldDelegate.topPadding != topPadding ||
        oldDelegate.addressText != addressText ||
        oldDelegate.hintText != hintText ||
        oldDelegate.onTapSearch != onTapSearch ||
        oldDelegate.onTapAddress != onTapAddress;
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({
    required this.height,
    required this.hintText,
    required this.onTap,
  });

  final double height;
  final String hintText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 35,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Iconsax.search_normal_1_copy,
              color: Color(0xFFFF4D2D),
              size: 16,
            ),
            const SizedBox(width: 5),
            const Expanded(
              child: _SearchHintTyper(
                hints: [
                  'Săn deal 0đ hôm nay',
                  'Deal giảm tới 30%',
                  'Săn deal hời',
                  'Combo cơm trưa 35k',
                  'Khai tiệc giảm 50%',
                  'Deal cú đêm, Freeship 20.000Đ',
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchHintTyper extends StatefulWidget {
  const _SearchHintTyper({
    required this.hints,
    this.textStyle,
    this.typingSpeed = const Duration(milliseconds: 120),
    this.pauseDuration = const Duration(milliseconds: 1200),
  });

  final List<String> hints;
  final TextStyle? textStyle;
  final Duration typingSpeed;
  final Duration pauseDuration;

  @override
  State<_SearchHintTyper> createState() => _SearchHintTyperState();
}

class _SearchHintTyperState extends State<_SearchHintTyper> {
  late String _currentHint;
  int _hintIndex = 0;
  int _charIndex = 0;
  bool _isDeleting = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentHint = widget.hints[_hintIndex];
    _startTyping();
  }

  void _startTyping() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.typingSpeed, (timer) {
      setState(() {
        if (!_isDeleting) {
          // Đang gõ
          if (_charIndex < _currentHint.length) {
            _charIndex++;
          } else {
            // Gõ xong -> pause rồi bắt đầu xoá
            _isDeleting = true;
            _timer?.cancel();
            _timer = Timer(widget.pauseDuration, _startTyping);
          }
        } else {
          // Đang xoá
          if (_charIndex > 0) {
            _charIndex--;
          } else {
            // Xoá xong -> chuyển sang hint tiếp theo
            _isDeleting = false;
            _hintIndex = (_hintIndex + 1) % widget.hints.length;
            _currentHint = widget.hints[_hintIndex];
            _timer?.cancel();
            _timer = Timer(const Duration(milliseconds: 300), _startTyping);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _currentHint.substring(0, _charIndex);
    return Text(
      text.isEmpty ? 'Tìm kiếm' : text, // fallback khi mới vào
      style:
          widget.textStyle ??
          const TextStyle(
            color: AppColor.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
      overflow: TextOverflow.ellipsis,
    );
  }
}
