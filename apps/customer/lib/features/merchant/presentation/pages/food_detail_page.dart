import 'package:customer/app/theme/app_color.dart';
import 'package:customer/core/di/providers.dart';
import 'package:customer/core/utils/checkout_delivery_draft_mapper.dart';
import 'package:customer/core/utils/checkout_error_ui.dart';
import 'package:customer/core/utils/formatters.dart';
import 'package:customer/features/auth/presentation/viewmodels/auth_providers.dart';
import 'package:customer/features/cart/data/repositories/cart_repository.dart';
import 'package:customer/features/cart/presentation/widgets/cart_bottom_sheet.dart';
import 'package:customer/features/dinein/data/models/dine_in_models.dart';
import 'package:customer/features/merchant/data/models/merchant_detail_model.dart';
import 'package:customer/features/merchant/data/models/product_config_model.dart';
import 'package:customer/features/merchant/data/models/product_reviews_model.dart';
import 'package:customer/features/merchant/presentation/viewmodels/food_detail_controller.dart';
import 'package:customer/features/merchant/presentation/viewmodels/product_review_submit_controller.dart';
import 'package:customer/features/merchant/presentation/widgets/food_detail_page_skeleton.dart';
import 'package:customer/features/merchant/presentation/widgets/food_detail_reviews_skeleton.dart';
import 'package:customer/features/merchant/presentation/widgets/product_option_bottom_sheet.dart';
import 'package:customer/features/merchant/presentation/widgets/review_editor_dialog.dart';
import 'package:customer/features/merchant/presentation/widgets/review_media_strip.dart';
import 'package:customer/features/orders/data/models/checkout_delivery_draft.dart';
import 'package:customer/features/orders/data/models/checkout_models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

enum FoodDetailViewMode { delivery, dineIn }

class FoodDetailPage extends ConsumerStatefulWidget {
  const FoodDetailPage.delivery({
    super.key,
    required this.productId,
    this.lat,
    this.lng,
    this.merchantId,
  }) : mode = FoodDetailViewMode.delivery,
       dineInContext = null;

  const FoodDetailPage.dineIn({
    super.key,
    required this.productId,
    required this.dineInContext,
    this.merchantId,
  }) : mode = FoodDetailViewMode.dineIn,
       lat = null,
       lng = null;

  final String productId;
  final double? lat;
  final double? lng;
  final String? merchantId;

  final FoodDetailViewMode mode;
  final DineInContext? dineInContext;

  @override
  ConsumerState<FoodDetailPage> createState() => _FoodDetailPageState();
}

class _FoodDetailPageState extends ConsumerState<FoodDetailPage> {
  late final FoodDetailParams _params;
  late final PageController _pageCtrl;
  late final ScrollController _scrollCtrl;
  late String? _cartMerchantId;
  ProviderSubscription? _detailSub;
  bool _openingCheckout = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();

    _params = FoodDetailParams(
      productId: widget.productId,
      lat: widget.lat,
      lng: widget.lng,
      reviewLimit: 10,
    );

    _cartMerchantId = widget.merchantId;
    _pageCtrl = PageController();
    _scrollCtrl = ScrollController()..addListener(_onScrollLoadMore);

    if (widget.mode == FoodDetailViewMode.dineIn) {
      ref.read(
        cartProvider(
          CartParams.dineIn(
            tableSessionId: widget.dineInContext!.tableSessionId,
          ),
        ).notifier,
      );
    } else if (_cartMerchantId != null && _cartMerchantId!.isNotEmpty) {
      final p = CartParams.delivery(merchantId: _cartMerchantId!);
      ref.read(cartProvider(p).notifier);
    }

    _detailSub = ref.listenManual(foodDetailProvider(_params), (prev, next) {
      final mid = next.detail?.product.merchantId;
      final prevMid = prev?.detail?.product.merchantId;

      if (mid == null || mid.isEmpty) return;
      if (prevMid == mid) return;
      if (!mounted) return;

      if (_cartMerchantId != mid) {
        setState(() => _cartMerchantId = mid);
      }

      ref.read(cartProvider(CartParams.delivery(merchantId: mid)).notifier);
    });
  }

  void _onScrollLoadMore() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent <= 0) return;

    final nearBottom = pos.pixels >= (pos.maxScrollExtent - 240);
    if (!nearBottom) return;

    ref.read(foodDetailProvider(_params).notifier).loadMore();
  }

  @override
  void dispose() {
    _detailSub?.close();
    _scrollCtrl.removeListener(_onScrollLoadMore);
    _scrollCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  CartParams get _cartParams {
    if (widget.mode == FoodDetailViewMode.dineIn) {
      return CartParams.dineIn(
        tableSessionId: widget.dineInContext!.tableSessionId,
      );
    }

    final merchantId = (_cartMerchantId ?? widget.merchantId ?? '').trim();
    return CartParams.delivery(merchantId: merchantId);
  }

  Future<void> _leaveTable() async {
    if (widget.mode != FoodDetailViewMode.dineIn) return;

    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Rời bàn'),
        content: const Text(
          'Bạn có chắc muốn rời khỏi bàn hiện tại không? Ngữ cảnh dine-in trên thiết bị này sẽ được xoá.',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Ở lại',
              style: TextStyle(color: CupertinoColors.activeBlue),
            ),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Rời bàn',
              style: TextStyle(color: CupertinoColors.destructiveRed),
            ),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      ref.invalidate(cartProvider(_cartParams));
      await ref.read(dineInSessionProvider.notifier).clearContext();
      await ref.read(customerSocketServiceProvider).reconnectWithFreshToken();

      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mapCheckoutErrorMessage(e))));
    }
  }

  Future<bool> _ensureLoggedIn() async {
    final auth = ref.read(authViewModelProvider);
    final user = auth.valueOrNull;
    if (user == null) {
      if (!mounted) return false;
      context.push('/signin');
      return false;
    }
    return true;
  }

  Future<void> _goToCheckout() async {
    if (_openingCheckout) return;

    if (widget.mode == FoodDetailViewMode.dineIn) {
      final ctx = widget.dineInContext;
      if (ctx == null) return;

      setState(() => _openingCheckout = true);

      try {
        final repo = ref.read(checkoutRepositoryProvider);

        await repo.previewDineIn(
          tableSessionId: ctx.tableSessionId,
          voucherCode: null,
        );

        if (!mounted) return;

        await context.push(
          '/checkout/dine-in',
          extra: {'tableSessionId': ctx.tableSessionId, 'dineInContext': ctx},
        );

        if (!mounted) return;
        await ref
            .read(cartProvider(_cartParams).notifier)
            .loadSummary(silent: true);
      } catch (e) {
        if (!mounted) return;
        await showCheckoutErrorDialog(
          context,
          message: mapCheckoutErrorMessage(e),
        );
      } finally {
        if (mounted) {
          setState(() => _openingCheckout = false);
        }
      }
      return;
    }

    final merchantId = _cartMerchantId;
    if (merchantId == null || merchantId.isEmpty) return;

    if (!await _ensureLoggedIn()) return;
    if (!mounted) return;

    final user = ref.read(authViewModelProvider).valueOrNull;
    var draft =
        checkoutDraftFromAuth(user) ??
        const CheckoutDeliveryDraft(
          lat: 0,
          lng: 0,
          address: '',
          receiverName: '',
          receiverPhone: '',
          addressNote: '',
        );

    var addrState = ref.read(addressControllerProvider);
    if (addrState.current == null && !addrState.didLoad) {
      await ref.read(addressControllerProvider.notifier).load();
      if (!mounted) return;
      addrState = ref.read(addressControllerProvider);
    }

    if (draft.address.trim().isEmpty || draft.lat == 0 || draft.lng == 0) {
      final current = addrState.current ?? addrState.deviceLocation;
      if (current != null) {
        draft = CheckoutDeliveryDraft(
          lat: current.lat,
          lng: current.lng,
          address: (current.address ?? '').trim(),
          receiverName: (current.receiverName ?? user?.fullName ?? '').trim(),
          receiverPhone: (current.receiverPhone ?? user?.phone ?? '').trim(),
          addressNote: (current.deliveryNote ?? '').trim(),
        );
      }
    }

    if (draft.address.trim().isEmpty || draft.lat == 0 || draft.lng == 0) {
      await showCheckoutErrorDialog(
        context,
        message:
            'Bạn chưa có địa chỉ giao hàng hợp lệ. Vui lòng cập nhật địa chỉ trước.',
      );
      return;
    }

    setState(() => _openingCheckout = true);

    try {
      final repo = ref.read(checkoutRepositoryProvider);

      await repo.previewDelivery(
        merchantId: merchantId,
        lat: draft.lat,
        lng: draft.lng,
        address: draft.address,
        receiverName: draft.receiverName,
        receiverPhone: draft.receiverPhone,
        addressNote: draft.addressNote,
        paymentMethod: CheckoutPaymentMethod.cash,
        voucherCode: null,
      );

      if (!mounted) return;

      await context.push(
        '/checkout/delivery',
        extra: {'merchantId': merchantId, 'draft': draft},
      );

      if (!mounted) return;
      await ref
          .read(
            cartProvider(CartParams.delivery(merchantId: merchantId)).notifier,
          )
          .loadSummary(silent: true);
    } catch (e) {
      if (!mounted) return;
      await showCheckoutErrorDialog(
        context,
        message: mapCheckoutErrorMessage(e),
      );
    } finally {
      if (mounted) {
        setState(() => _openingCheckout = false);
      }
    }
  }

  Future<void> _onAddPressed() async {
    final st = ref.read(foodDetailProvider(_params));
    final detail = st.detail;
    if (detail == null) return;

    final merchantId = detail.product.merchantId;

    if (widget.mode == FoodDetailViewMode.delivery &&
        !await _ensureLoggedIn()) {
      return;
    }

    final cartParams = _cartParams;
    final cartCtrl = ref.read(cartProvider(cartParams).notifier);

    if (!detail.product.hasOptions) {
      await cartCtrl.addProduct(
        productId: detail.product.id,
        quantity: 1,
        selectedOptions: const [],
        selectedToppings: const [],
        note: '',
      );

      final err = ref.read(cartProvider(cartParams)).error;
      if (err != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(err)));
      } else {
        HapticFeedback.lightImpact();
      }
      return;
    }

    final mdProduct = MerchantDetailProductItem(
      id: detail.product.id,
      name: detail.product.name,
      description: detail.product.description,
      imageUrls: detail.product.images
          .map((x) => x.url)
          .where((s) => s.isNotEmpty)
          .toList(),
      price: detail.product.finalPrice,
      basePrice: (detail.product.basePrice > detail.product.finalPrice)
          ? detail.product.basePrice
          : null,
      sold: detail.product.totalSold,
      isAvailable: detail.product.isAvailable,
      rating: detail.product.averageRating,
      reviews: detail.product.totalReviews,
      hasOptions: true,
    );

    final draft = await showModalBottomSheet<CartItemDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ProductOptionBottomSheet(
          merchantId: merchantId,
          product: mdProduct,
        ),
      ),
    );

    if (draft == null) return;

    final selectedOptions = draft.selectedOptions
        .map<Map<String, String>>(
          (x) => {
            'option_id': x.optionId.toString(),
            'choice_id': x.choiceId.toString(),
          },
        )
        .toList();

    final selectedToppings = draft.selectedToppings
        .map<Map<String, dynamic>>(
          (x) => {'topping_id': x.toppingId.toString(), 'quantity': x.quantity},
        )
        .toList();

    await cartCtrl.addProduct(
      productId: detail.product.id,
      quantity: draft.quantity,
      selectedOptions: selectedOptions,
      selectedToppings: selectedToppings,
      note: draft.note ?? '',
    );

    final err = ref.read(cartProvider(cartParams)).error;
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _openProductReviewEditor({ProductReviewItem? existing}) async {
    final firstState = ref.read(foodDetailProvider(_params));
    final detail = firstState.detail;
    if (detail == null) return;

    final changed = await ReviewEditorDialog.show(
      context,
      title: existing != null ? 'Sửa đánh giá món ăn' : 'Đánh giá món ăn',
      initialRating: existing?.rating ?? 5,
      initialComment: existing?.comment ?? '',
      initialImageUrls: existing?.images.map((e) => e.url).toList() ?? const [],
      initialVideoUrl: existing?.videoUrl,
      submitText: existing != null ? 'Cập nhật' : 'Gửi đánh giá',
      onSubmit: (result) async {
        final foodState = ref.read(foodDetailProvider(_params));
        final currentDetail = foodState.detail;
        if (currentDetail == null) {
          return 'Không tải được thông tin sản phẩm';
        }

        final submitCtrl = ref.read(
          productReviewSubmitControllerProvider(widget.productId).notifier,
        );

        bool ok = false;

        if (existing != null) {
          ok = await submitCtrl.updateReview(
            reviewId: existing.id,
            rating: result.rating,
            comment: result.comment,
            keptRemoteImageUrls: result.keptRemoteImageUrls,
            keptRemoteVideoUrl: result.keptRemoteVideoUrl,
            newImages: result.newImages,
            newVideo: result.newVideo,
          );
        } else {
          final createOrderId = foodState.createOrderId;
          if (createOrderId == null || createOrderId.isEmpty) {
            return 'Không tìm thấy order đủ điều kiện để đánh giá';
          }

          ok = await submitCtrl.createReview(
            orderId: createOrderId,
            merchantId: currentDetail.product.merchantId,
            productId: currentDetail.product.id,
            rating: result.rating,
            comment: result.comment,
            newImages: result.newImages,
            newVideo: result.newVideo,
          );
        }

        final submitState = ref.read(
          productReviewSubmitControllerProvider(widget.productId),
        );

        if (!ok) {
          return submitState.error ?? 'Thao tác thất bại';
        }

        return null;
      },
    );

    if (!mounted || changed != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing != null ? 'Đã cập nhật đánh giá' : 'Đã gửi đánh giá',
        ),
      ),
    );

    await ref.read(foodDetailProvider(_params).notifier).refresh();
  }

  ProductReviewItem? _findEffectiveMyReview(
    List<ProductReviewItem> reviews,
    dynamic authUser,
    ProductReviewItem? myReviewFromApi,
  ) {
    if (myReviewFromApi != null) return myReviewFromApi;

    final viewerId =
        (authUser?.id ?? authUser?.userId ?? authUser?._id)?.toString() ?? '';

    if (viewerId.isEmpty) return null;

    for (final review in reviews) {
      final uid = (review.user?.id ?? '').trim();
      if (uid == viewerId) return review;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(foodDetailProvider(_params));
    final ctrl = ref.read(foodDetailProvider(_params).notifier);
    final authUser = ref.watch(authViewModelProvider).valueOrNull;
    final isLoggedIn = authUser != null;

    final myReview = _findEffectiveMyReview(st.reviews, authUser, st.myReview);

    // Viết đánh giá thì mới cần check auth
    final canWriteReview = isLoggedIn && st.canCreateReview && myReview == null;

    // Sửa đánh giá thì chỉ cần server đã trả đúng myReview là đủ
    final canEditReview = myReview != null;

    final displayReviews = <ProductReviewItem>[
      if (myReview != null) myReview,
      ...st.reviews.where((e) => e.id != myReview?.id),
    ];
    if (st.isLoading && st.detail == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const FoodDetailPageSkeleton(),
      );
    }
    final detail = st.detail;
    final reviews = st.reviews;
    final images =
        detail?.product.images.map((x) => x.url).toList() ?? const <String>[];

    final p = detail?.product;
    final m = detail?.merchant;

    final price = p?.finalPrice ?? 0;
    final basePrice = p?.basePrice ?? 0;
    final hasDiscount = basePrice > price;
    final showCartBar =
        widget.mode == FoodDetailViewMode.dineIn ||
        (_cartMerchantId != null && _cartMerchantId!.isNotEmpty);
    return Scaffold(
      bottomNavigationBar: !showCartBar
          ? null
          : _FoodCartBar(
              params: _cartParams,
              mode: widget.mode,
              dineInContext: widget.dineInContext,
              onCheckout: _goToCheckout,
              onLeaveTable: widget.mode == FoodDetailViewMode.dineIn
                  ? _leaveTable
                  : null,
              loading: _openingCheckout,
            ),
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: ctrl.refresh,
        child: CustomScrollView(
          controller: _scrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _TopGallery(
                imageUrls: images,
                pageCtrl: _pageCtrl,
                page: _page,
                onPageChanged: (i) => setState(() => _page = i),
                onBack: () => Navigator.of(context).maybePop(),
                onShare: () {},
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -24),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (detail == null && st.error != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Lỗi: ${st.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        )
                      else if (detail != null) ...[
                        _PriceTitleSection(
                          price: price,
                          originalPrice: hasDiscount ? basePrice : null,
                          savingText: hasDiscount
                              ? 'Tiết kiệm ${_money(basePrice - price)}'
                              : null,
                          title: p!.name,
                          subtitle: (m?.name ?? '').trim().isEmpty
                              ? ' '
                              : (m?.name ?? ''),
                          soldCount: p.totalSold,
                          reviewsCount: p.totalReviews,
                          limitText: '1 phần/đơn',
                          onAddPressed: _onAddPressed,
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: Colors.black12),
                        _StoreInfoSection(
                          merchantId: detail.product.merchantId,
                          userLat: widget.lat,
                          userLng: widget.lng,
                          merchantName: m?.name ?? '',
                          merchantLogoUrl: m?.logoUrl,
                          merchantRating: m?.averageRating ?? 0,
                          distanceKm: m?.distanceKm ?? 0,
                          etaMin: m?.etaMin ?? 0,
                          deliveryAddress: m?.address ?? '',
                          mode: widget.mode,
                          dineInContext: widget.dineInContext,
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1, color: Colors.black12),
                        _ReviewsHeader(
                          count: st.totalReviews,
                          isRefreshing: st.isRefreshing,
                          actionText: canEditReview
                              ? 'Sửa đánh giá'
                              : (canWriteReview ? 'Viết đánh giá' : null),
                          onActionTap: canEditReview
                              ? () =>
                                    _openProductReviewEditor(existing: myReview)
                              : (canWriteReview
                                    ? () => _openProductReviewEditor()
                                    : null),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (detail != null && st.isLoading && displayReviews.isEmpty)
              const SliverToBoxAdapter(child: FoodDetailReviewsSkeleton())
            else if (detail != null && displayReviews.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Center(
                    child: Text(
                      'Chưa có đánh giá nào',
                      style: TextStyle(color: Colors.black45),
                    ),
                  ),
                ),
              )
            else if (detail != null)
              SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  if (i == displayReviews.length) {
                    if (st.isLoadingMore) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!st.hasMore) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Text(
                            'Hết bình luận',
                            style: TextStyle(color: Colors.black45),
                          ),
                        ),
                      );
                    }
                    return const SizedBox(height: 18);
                  }

                  final r = displayReviews[i];
                  return Column(
                    children: [
                      _ReviewTile(
                        userName: r.user?.name ?? 'Ẩn danh',
                        userAvatarUrl: r.user?.avatarUrl,
                        stars: r.rating,
                        content: r.comment,
                        images: r.images,
                        videoUrl: r.videoUrl,
                        timeText: _formatTime(r.createdAt),
                        merchantReply: r.merchantReply?.content,
                        isEdited: r.isEdited,
                      ),
                      const Divider(height: 1, color: Colors.black12),
                    ],
                  );
                }, childCount: displayReviews.length + 1),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.userName,
    required this.userAvatarUrl,
    required this.stars,
    required this.content,
    required this.timeText,
    required this.images,
    this.videoUrl,
    this.merchantReply,
    this.isEdited = false,
  });

  final String userName;
  final String? userAvatarUrl;
  final int stars;
  final String content;
  final List<ReviewImage> images;
  final String? videoUrl;
  final String timeText;
  final String? merchantReply;
  final bool isEdited;

  @override
  Widget build(BuildContext context) {
    final hasMedia =
        images.isNotEmpty || (videoUrl != null && videoUrl!.trim().isNotEmpty);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ReviewAvatar(name: userName, avatarUrl: userAvatarUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColor.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _StarsRow(stars: stars),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(height: 1.4, color: AppColor.textPrimary),
          ),
          if (hasMedia) ...[
            const SizedBox(height: 12),
            ReviewMediaStrip(images: images, videoUrl: videoUrl),
          ],
          if (merchantReply != null && merchantReply!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColor.surfaceWarm,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColor.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Phản hồi từ quán',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColor.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    merchantReply!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: AppColor.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                timeText,
                style: const TextStyle(color: AppColor.textMuted, fontSize: 12),
              ),
              if (isEdited) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColor.surfaceWarm,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColor.border),
                  ),
                  child: const Text(
                    'Đã chỉnh sửa',
                    style: TextStyle(
                      color: AppColor.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewAvatar extends StatelessWidget {
  const _ReviewAvatar({required this.name, required this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final first = name.trim().isEmpty ? 'A' : name.trim()[0].toUpperCase();

    return ClipOval(
      child: Container(
        width: 32,
        height: 32,
        color: AppColor.surfaceWarm,
        child: (avatarUrl != null && avatarUrl!.trim().isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Center(
                  child: Text(
                    first,
                    style: const TextStyle(
                      color: AppColor.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  first,
                  style: const TextStyle(
                    color: AppColor.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }
}

class _FoodCartBar extends ConsumerWidget {
  const _FoodCartBar({
    required this.params,
    required this.mode,
    required this.onCheckout,
    required this.loading,
    this.dineInContext,
    this.onLeaveTable,
  });

  final CartParams params;
  final FoodDetailViewMode mode;
  final DineInContext? dineInContext;
  final Future<void> Function() onCheckout;
  final Future<void> Function()? onLeaveTable;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(cartProvider(params));
    final s = st.summary;
    final paddingBottom = MediaQuery.paddingOf(context).bottom;

    final visible = s.itemCount > 0;
    final hasDiscount = s.discountEstimated > 0;

    Future<void> openCartSheet() async {
      final cartCtrl = ref.read(cartProvider(params).notifier);
      await cartCtrl.ensureCurrentLoaded();
      if (!context.mounted) return;

      final bottomGap = 53 + MediaQuery.paddingOf(context).bottom;

      showModalBottomSheet(
        context: context,
        useRootNavigator: false,
        isScrollControlled: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.transparent,
        builder: (_) {
          return Padding(
            padding: EdgeInsets.only(bottom: bottomGap),
            child: CartBottomSheet(
              params: params,
              title: mode == FoodDetailViewMode.dineIn
                  ? 'Giỏ hàng tại bàn'
                  : 'Giỏ hàng',
              dineInLabel:
                  mode == FoodDetailViewMode.dineIn && dineInContext != null
                  ? 'Bàn ${dineInContext!.tableNumber}'
                  : null,
              onLeaveTable: onLeaveTable,
            ),
          );
        },
      );
    }

    Widget bar() {
      return Material(
        key: const ValueKey('bar'),
        color: Colors.white,
        elevation: 10,
        child: InkWell(
          onTap: loading ? null : openCartSheet,
          child: Stack(
            children: [
              loading
                  ? const LinearProgressIndicator(color: AppColor.primary)
                  : const SizedBox.shrink(),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.10),
                      blurRadius: 18,
                      offset: const Offset(0, -6),
                    ),
                  ],
                  border: Border(
                    top: BorderSide(
                      color: Colors.black.withOpacity(0.06),
                      width: 1,
                    ),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(14, 10, 14, paddingBottom),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(
                          Iconsax.bag,
                          size: 26,
                          color: Color(0xFFEE4D2D),
                        ),
                        Positioned(
                          right: -13,
                          top: -13,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEE4D2D),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              s.itemCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (hasDiscount)
                              Text(
                                _money(s.originalEstimated.round()),
                                style: const TextStyle(
                                  color: Colors.black38,
                                  decoration: TextDecoration.lineThrough,
                                  fontWeight: FontWeight.w400,
                                  fontSize: 12,
                                ),
                              ),
                            Text(
                              _money(s.totalEstimated.round()),
                              style: const TextStyle(
                                color: Color(0xFFEE4D2D),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEE4D2D),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                            ),
                            onPressed: loading
                                ? null
                                : () async {
                                    await onCheckout();
                                  },
                            child: loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CupertinoActivityIndicator(),
                                  )
                                : Text(
                                    mode == FoodDetailViewMode.dineIn
                                        ? 'Gọi món'
                                        : 'Giao hàng',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));

        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);

        return ClipRect(
          child: SizeTransition(
            sizeFactor: anim,
            axisAlignment: 1.0,
            child: SlideTransition(
              position: slide,
              child: FadeTransition(opacity: fade, child: child),
            ),
          ),
        );
      },
      child: visible ? bar() : const SizedBox(key: ValueKey('empty')),
    );
  }
}

class _TopGallery extends StatelessWidget {
  const _TopGallery({
    required this.imageUrls,
    required this.pageCtrl,
    required this.page,
    required this.onPageChanged,
    required this.onBack,
    required this.onShare,
  });

  final List<String> imageUrls;
  final PageController pageCtrl;
  final int page;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onBack;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.46;
    final count = imageUrls.isEmpty ? 1 : imageUrls.length;

    return SizedBox(
      height: h,
      child: Stack(
        children: [
          PageView.builder(
            controller: pageCtrl,
            itemCount: count,
            onPageChanged: onPageChanged,
            itemBuilder: (_, i) {
              if (imageUrls.isEmpty) {
                return Container(
                  color: Colors.black12,
                  child: const Center(
                    child: Icon(Icons.image_not_supported_outlined),
                  ),
                );
              }
              return CachedNetworkImage(
                imageUrl: imageUrls[i],
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.black12),
                errorWidget: (_, __, ___) => Container(color: Colors.black12),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.30), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _CircleIcon(icon: Iconsax.arrow_left_copy, onTap: onBack),
                  const Spacer(),
                  _CircleIcon(icon: Iconsax.export_copy, onTap: onShare),
                ],
              ),
            ),
          ),
          if (imageUrls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  imageUrls.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == page ? const Color(0xFFEE4D2D) : Colors.white,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PriceTitleSection extends StatelessWidget {
  const _PriceTitleSection({
    required this.price,
    required this.originalPrice,
    required this.savingText,
    required this.title,
    required this.subtitle,
    required this.soldCount,
    required this.reviewsCount,
    required this.limitText,
    required this.onAddPressed,
  });

  final int price;
  final int? originalPrice;
  final String? savingText;
  final String title;
  final String subtitle;
  final int soldCount;
  final int reviewsCount;
  final String limitText;
  final VoidCallback? onAddPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _money(price),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFEE4D2D),
                ),
              ),
              const SizedBox(width: 10),
              if (savingText != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEE4D2D),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    savingText!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 8,
                    ),
                  ),
                ),
              const Spacer(),
              _AddSquareButton(onTap: onAddPressed),
            ],
          ),
          if (originalPrice != null)
            Text(
              _money(originalPrice!),
              style: const TextStyle(
                decoration: TextDecoration.lineThrough,
                color: Colors.black38,
                fontSize: 13,
              ),
            ),
          const SizedBox(height: 10),
          Text(
            title.toUpperCase(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.black54, height: 1.25),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${_compactNumber(soldCount)} đã bán',
                style: const TextStyle(color: Colors.black45),
              ),
              const SizedBox(width: 10),
              const Text('|', style: TextStyle(color: Colors.black26)),
              const SizedBox(width: 10),
              Text(
                '$reviewsCount đánh giá',
                style: const TextStyle(color: Colors.black45),
              ),
              const Spacer(),
              Text(
                limitText,
                style: const TextStyle(
                  color: Color(0xFFEE4D2D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StoreInfoSection extends StatelessWidget {
  const _StoreInfoSection({
    required this.merchantId,
    required this.userLat,
    required this.userLng,
    required this.deliveryAddress,
    required this.merchantName,
    required this.merchantRating,
    required this.distanceKm,
    required this.etaMin,
    required this.merchantLogoUrl,
    required this.mode,
    this.dineInContext,
  });

  final String merchantId;
  final double? userLat;
  final double? userLng;
  final String deliveryAddress;
  final String merchantName;
  final double merchantRating;
  final double distanceKm;
  final int etaMin;
  final String? merchantLogoUrl;
  final FoodDetailViewMode mode;
  final DineInContext? dineInContext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Thông tin cửa hàng',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => context.push('/address'),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: Color(0xFFEE4D2D),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Địa chỉ: $deliveryAddress',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w400,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.black45,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: .4, color: Colors.black12),
          const SizedBox(height: 12),
          InkWell(
            onTap: () {
              if (mode == FoodDetailViewMode.dineIn && dineInContext != null) {
                context.push(
                  '/merchant/$merchantId',
                  extra: {'mode': 'dine_in', 'dineInContext': dineInContext},
                );
                return;
              }

              context.push(
                '/merchant/$merchantId',
                extra: {'lat': userLat, 'lng': userLng},
              );
            },
            child: Row(
              children: [
                _StoreLogo(url: merchantLogoUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchantName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFF5A623),
                            size: 14,
                          ),
                          Text(
                            '${merchantRating.toStringAsFixed(1)}  |  ${formatDistance(distanceKm)}  |  $etaMin phút',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewsHeader extends StatelessWidget {
  const _ReviewsHeader({
    required this.count,
    required this.isRefreshing,
    this.actionText,
    this.onActionTap,
  });

  final int count;
  final bool isRefreshing;
  final String? actionText;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          const Text(
            'Bình luận',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          Text(
            '($count)',
            style: const TextStyle(color: Colors.black45, fontSize: 13),
          ),
          const Spacer(),
          if (isRefreshing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (actionText != null && onActionTap != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: onActionTap,
              style: TextButton.styleFrom(
                foregroundColor: AppColor.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionText!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black12,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppColor.border),
        ),
      ),
    );
  }
}

class _AddSquareButton extends StatelessWidget {
  const _AddSquareButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEE4D2D),
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: const SizedBox(
          width: 25,
          height: 25,
          child: Icon(Icons.add, color: Colors.white, size: 14),
        ),
      ),
    );
  }
}

class _StarsRow extends StatelessWidget {
  const _StarsRow({required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) {
    final s = stars.clamp(0, 5);
    return Row(
      children: List.generate(
        5,
        (i) => Icon(
          i < s ? Icons.star_rounded : Icons.star_border_rounded,
          color: const Color(0xFFF5A623),
          size: 18,
        ),
      ),
    );
  }
}

class _StoreLogo extends StatelessWidget {
  const _StoreLogo({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final w = 42.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: w,
        height: w,
        color: Colors.black.withOpacity(0.06),
        child: (url == null || url!.trim().isEmpty)
            ? const Icon(Icons.storefront_rounded, color: Colors.black54)
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.storefront_rounded, color: Colors.black54),
              ),
      ),
    );
  }
}

String _money(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final pos = s.length - i;
    buf.write(s[i]);
    if (pos > 1 && pos % 3 == 1) buf.write('.');
  }
  return '${buf}đ';
}

String _compactNumber(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M+';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K+';
  return '$n';
}

String _formatTime(DateTime? dt) {
  if (dt == null) return '';
  final d = dt.toLocal();
  String two(int x) => x < 10 ? '0$x' : '$x';
  return '${two(d.day)}-${two(d.month)}-${d.year} ${two(d.hour)}:${two(d.minute)}';
}
