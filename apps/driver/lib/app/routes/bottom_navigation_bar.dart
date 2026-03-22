// lib/main_shell.dart
import 'dart:ui';

import 'package:driver/app/theme/app_color.dart';
import 'package:driver/core/di/providers.dart';
import 'package:driver/features/auth/presentation/pages/signin_page.dart';
import 'package:driver/features/earnings/presentation/pages/driver_earnings_page.dart';
import 'package:driver/features/home/presentation/pages/home_page.dart';
import 'package:driver/features/notifications/presentation/pages/driver_notifications_page.dart';
import 'package:driver/features/profile/presentation/pages/driver_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _isVisible = true;

  // đúng 5 tab
  final List<bool> _built = [true, false, false, false];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref
          .read(driverNotificationControllerProvider.notifier)
          .loadUnreadOnly();

      await ref.read(driverSocketBootstrapControllerProvider).start();
    });
  }

  Future<void> _openSignin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SigninPage(),
        fullscreenDialog: true,
      ),
    );
  }

  // đúng 5 page theo số destination
  late final List<Widget> _pages = const [
    HomePage(),
    DriverEarningsPage(),
    DriverNotificationsPage(),
    DriverProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    // final double bottomPadding = MediaQuery.of(context).padding.bottom;
    const double navBarHeight = 55.0;

    final authState = ref.watch(driverAuthControllerProvider);
    final user = authState;

    final notifState = ref.watch(driverNotificationControllerProvider);
    final notifBadge = notifState.unreadCount;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: List.generate(_pages.length, (i) {
          if (!_built[i]) return const SizedBox.shrink();
          return _pages[i];
        }),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColor.iconInactive, width: .2),
            ),
            color: Colors.white,
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const IconThemeData(color: AppColor.primary);
                }
                return const IconThemeData(color: Color(0xff6C757D));
              }),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const TextStyle(
                    color: AppColor.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  );
                }
                return const TextStyle(
                  color: Color(0xff6C757D),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                );
              }),
            ),
            child: NavigationBar(
              height: navBarHeight,
              labelPadding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              indicatorColor: Colors.transparent,
              selectedIndex: _index,
              onDestinationSelected: (i) async {
                final auth = ref.read(driverAuthControllerProvider);
                final isLoggedIn = auth.me != null;

                final protectedTab = i == 1 || i == 2 || i == 3;

                if (protectedTab && !isLoggedIn) {
                  await _openSignin();
                  return;
                }

                if (!mounted) return;

                setState(() {
                  _index = i;
                  _built[i] = true;
                  _isVisible = true;
                });
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Iconsax.truck_copy),
                  selectedIcon: Icon(Iconsax.truck),
                  label: 'Home',
                ),
                const NavigationDestination(
                  icon: Icon(Iconsax.usd_coin_usdc_copy),
                  selectedIcon: Icon(Iconsax.usd_coin_usdc),
                  label: 'Thu nhập',
                ),
                NavigationDestination(
                  icon: _NavIconWithBadge(
                    icon: const Icon(Iconsax.notification_copy),
                    badge: notifBadge,
                  ),
                  selectedIcon: _NavIconWithBadge(
                    icon: const Icon(Iconsax.notification),
                    badge: notifBadge,
                  ),
                  label: 'Thông báo',
                ),
                NavigationDestination(
                  icon:
                      (user.me?.avatarUrl != null &&
                          user.me!.avatarUrl!.isNotEmpty)
                      ? CircleAvatar(
                          radius: 12,
                          backgroundImage: NetworkImage(user.me!.avatarUrl!),
                          backgroundColor: Colors.transparent,
                        )
                      : const Icon(Iconsax.user_copy),
                  selectedIcon:
                      (user.me?.avatarUrl != null &&
                          user.me!.avatarUrl!.isNotEmpty)
                      ? Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColor.primary,
                              width: 1.5,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 12,
                            backgroundImage: NetworkImage(user.me!.avatarUrl!),
                            backgroundColor: Colors.transparent,
                          ),
                        )
                      : const Icon(Iconsax.user),
                  label: 'Tài khoản',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavIconWithBadge extends StatelessWidget {
  const _NavIconWithBadge({required this.icon, required this.badge});

  final Widget icon;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        if (badge > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badge > 99 ? '99+' : '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  final String title;

  const _PlaceholderPage({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
