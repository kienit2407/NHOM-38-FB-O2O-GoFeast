import 'package:customer/app/routes/bottom_navigation_bar.dart';
import 'package:customer/core/di/providers.dart';
import 'package:customer/features/addresses/data/models/saved_address_models.dart';
import 'package:customer/features/addresses/presentation/pages/add_adress_page.dart';
import 'package:customer/features/addresses/presentation/pages/adress_page.dart';
import 'package:customer/features/addresses/presentation/pages/choose_address_page.dart';
import 'package:customer/features/addresses/presentation/pages/search_address_page.dart';
import 'package:customer/features/auth/domain/entities/auth_user.dart'
    show AuthUser;
import 'package:customer/features/auth/presentation/pages/enter_phone_page.dart';
import 'package:customer/features/dinein/data/models/dine_in_models.dart';
import 'package:customer/features/favorites/presentation/pages/my_favorite_merchant_page.dart';
import 'package:customer/features/home/presentation/pages/home_page.dart';
import 'package:customer/features/merchant/presentation/pages/food_detail_page.dart';
import 'package:customer/features/merchant/presentation/pages/merchant_detail_page.dart';
import 'package:customer/features/orders/data/models/checkout_delivery_draft.dart';
import 'package:customer/features/orders/data/models/checkout_models.dart';
import 'package:customer/features/orders/presentation/pages/checkout_page.dart';
import 'package:customer/features/orders/presentation/pages/my_orders_page.dart';
import 'package:customer/features/orders/presentation/pages/my_reviews_page.dart';
import 'package:customer/features/orders/presentation/pages/order_detail_page.dart';
import 'package:customer/features/orders/presentation/pages/result_page.dart';
import 'package:customer/features/profile/presentation/pages/my_vouchers_page.dart';
import 'package:customer/features/promotion/presentation/pages/promotion_detail_page.dart';
import 'package:customer/features/search/presentation/pages/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Pages
import 'package:customer/features/auth/presentation/pages/splash_page.dart';
import 'package:customer/features/auth/presentation/pages/signin_page.dart';

// // Auth
// import 'package:customer/features/auth/domain/entities/auth_user.dart';
import 'package:customer/features/auth/presentation/viewmodels/auth_providers.dart';

/// Router refresh khi auth đổi
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
    ref.listen<AsyncValue<AuthUser?>>(authViewModelProvider, (_, __) {
      notifyListeners();
    });
  }
}

final routerRefreshProvider = Provider<RouterRefreshNotifier>((ref) {
  final n = RouterRefreshNotifier(ref);
  ref.onDispose(n.dispose);
  return n;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(routerRefreshProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authViewModelProvider);
      final loc = state.matchedLocation;

      final isBootstrapping = auth.isLoading && auth.valueOrNull == null;

      if (isBootstrapping) {
        return loc == '/splash' ? null : '/splash';
      }

      final user = auth.valueOrNull;
      final isAuthed = user != null;
      final needsPhone = isAuthed && ((user.phone ?? '').trim().isEmpty);

      final goingSplash = loc == '/splash';
      final goingEnterPhone = loc == '/enter-phone';
      final goingSignin = loc == '/signin';

      if (goingSplash) {
        return needsPhone ? '/enter-phone' : '/';
      }

      if (needsPhone) {
        return goingEnterPhone ? null : '/enter-phone';
      }

      if (isAuthed && goingEnterPhone) return '/';
      if (isAuthed && goingSignin) return '/';

      if (!isAuthed && goingEnterPhone) return '/signin';

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(
        path: '/signin',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            fullscreenDialog: true,
            transitionDuration: const Duration(milliseconds: 320),
            reverseTransitionDuration: const Duration(milliseconds: 260),
            child: const SigninPage(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  );

                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(curved),
                    child: FadeTransition(
                      opacity: Tween<double>(begin: 0, end: 1).animate(curved),
                      child: child,
                    ),
                  );
                },
          );
        },
      ),

      //  add route enter phone
      GoRoute(path: '/enter-phone', builder: (_, __) => const EnterPhonePage()),

      GoRoute(path: '/', builder: (_, __) => const MainShell()),
      GoRoute(
        path: '/address',
        builder: (context, state) {
          final extra = state.extra as Map?;
          final pickForCheckout = extra?['pickForCheckout'] == true;
          final checkoutDraft = extra?['draft'] as CheckoutDeliveryDraft?;
          final entryDraft = extra?['entryDraft'] as CheckoutDeliveryDraft?;

          return AddressPage(
            pickForCheckout: pickForCheckout,
            checkoutDraft: checkoutDraft,
            entryDraft: entryDraft,
          );
        },
      ),
      GoRoute(
        path: '/address/add',
        builder: (context, state) {
          final extra = state.extra;

          if (extra is SavedAddress) {
            return AddAddressPage(editing: extra);
          }

          if (extra is Map && extra['checkoutDraft'] is CheckoutDeliveryDraft) {
            return AddAddressPage.checkoutDraft(
              draft: extra['checkoutDraft'] as CheckoutDeliveryDraft,
            );
          }

          return const AddAddressPage();
        },
      ),
      GoRoute(
        path: '/address/choose',
        builder: (_, __) => const ChooseAddressPage(),
      ),

      GoRoute(
        path: '/address/search',
        builder: (_, __) => const SearchAddressPage(),
      ),
      GoRoute(
        path: '/merchant/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final extra = state.extra;

          if (extra is Map && extra['mode'] == 'dine_in') {
            final ctx = extra['dineInContext'] as DineInContext;
            return MerchantDetailPage.dineIn(
              merchantId: id,
              dineInContext: ctx,
            );
          }

          final lat =
              (extra is Map ? (extra['lat'] as num?) : null)?.toDouble() ?? 0;
          final lng =
              (extra is Map ? (extra['lng'] as num?) : null)?.toDouble() ?? 0;

          return MerchantDetailPage.delivery(
            merchantId: id,
            lat: lat,
            lng: lng,
          );
        },
      ),
      GoRoute(
        path: '/favorites',
        builder: (_, __) => const MyFavoriteMerchantPage(),
      ),

      GoRoute(
        path: '/product/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final extra = state.extra;

          if (extra is Map && extra['mode'] == 'dine_in') {
            final ctx = extra['dineInContext'] as DineInContext;
            final merchantId = extra['merchantId']?.toString();

            return FoodDetailPage.dineIn(
              productId: id,
              merchantId: merchantId,
              dineInContext: ctx,
            );
          }

          final lat = (extra is Map ? (extra['lat'] as num?) : null)
              ?.toDouble();
          final lng = (extra is Map ? (extra['lng'] as num?) : null)
              ?.toDouble();
          final merchantId = extra is Map
              ? extra['merchantId']?.toString()
              : null;

          return FoodDetailPage.delivery(
            productId: id,
            lat: lat,
            lng: lng,
            merchantId: merchantId,
          );
        },
      ),
      GoRoute(
        path: '/checkout/delivery',
        builder: (context, state) {
          final extra = (state.extra as Map?) ?? {};
          final merchantId = (extra['merchantId']?.toString() ?? '').trim();
          final draft = extra['draft'] as CheckoutDeliveryDraft?;

          return CheckoutPage.delivery(
            merchantId: merchantId,
            deliveryDraft:
                draft ??
                const CheckoutDeliveryDraft(
                  lat: 0,
                  lng: 0,
                  address: '',
                  receiverName: '',
                  receiverPhone: '',
                  addressNote: '',
                ),
            onEditDeliveryAddress: (currentDraft, entryDraft) async {
              final picked = await context.push<CheckoutDeliveryDraft>(
                '/address',
                extra: {
                  'pickForCheckout': true,
                  'draft': currentDraft,
                  'entryDraft': entryDraft,
                },
              );
              return picked;
            },
          );
        },
      ),
      GoRoute(
        path: '/checkout/result',
        builder: (context, state) {
          final args = state.extra as CheckoutResultArgs;
          return ResultPage(args: args);
        },
      ),
      GoRoute(path: '/orders', builder: (_, __) => const MyOrdersPage()),
      GoRoute(
        path: '/orders/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return OrderDetailPage(orderId: id);
        },
      ),
      GoRoute(path: '/my-reviews', builder: (_, __) => const MyReviewsPage()),
      GoRoute(
        path: '/checkout/dine-in',
        builder: (context, state) {
          final extra = (state.extra as Map?) ?? {};
          final tableSessionId = (extra['tableSessionId']?.toString() ?? '')
              .trim();

          return CheckoutPage.dineIn(tableSessionId: tableSessionId);
        },
      ),
      GoRoute(
        path: '/promotion/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PromotionDetailPage(promotionId: id);
        },
      ),
      GoRoute(path: '/my-vouchers', builder: (_, __) => const MyVouchersPage()),
      GoRoute(path: '/search', builder: (context, state) => const SearchPage()),
    ],
  );
});
