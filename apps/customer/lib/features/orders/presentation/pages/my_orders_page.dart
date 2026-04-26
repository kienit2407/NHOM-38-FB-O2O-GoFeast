import 'package:cached_network_image/cached_network_image.dart';
import 'package:customer/app/theme/app_color.dart';
import 'package:customer/core/di/providers.dart';
import 'package:customer/features/auth/presentation/viewmodels/auth_providers.dart';
import 'package:customer/features/orders/data/models/my_order_models.dart';
import 'package:customer/features/orders/presentation/viewmodels/my_orders_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class MyOrdersPage extends ConsumerStatefulWidget {
  const MyOrdersPage({super.key});

  @override
  ConsumerState<MyOrdersPage> createState() => _MyOrdersPageState();
}

class _MyOrdersPageState extends ConsumerState<MyOrdersPage> {
  final _scrollCtrl = ScrollController();
  bool _bootstrapped = false;
  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      final user = ref.read(authViewModelProvider).valueOrNull;
      if (user == null) return;

      _bootstrapped = true;
      ref.read(myOrdersControllerProvider.notifier).bootstrap();
    });

    _scrollCtrl.addListener(() {
      if (!_scrollCtrl.hasClients) return;

      final pos = _scrollCtrl.position;
      if (pos.maxScrollExtent <= 0) return; // tránh list ngắn vẫn auto loadMore
      if (pos.pixels < pos.maxScrollExtent - 200) return;

      final st = ref.read(myOrdersControllerProvider);

      if (st.loadingMore ||
          st.loadingCounts ||
          st.loadingActive ||
          st.loadingHistory ||
          st.loadingReviews ||
          st.loadingDrafts) {
        return;
      }

      ref.read(myOrdersControllerProvider.notifier).loadMoreCurrent();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(myOrdersControllerProvider);
    final ctrl = ref.read(myOrdersControllerProvider.notifier);
    final auth = ref.watch(authViewModelProvider);
    final user = auth.valueOrNull;

    if (auth.isLoading && user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    if (user == null) {
      _bootstrapped = false;

      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'Đơn hàng',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  size: 88,
                  color: AppColor.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Đăng nhập để xem đơn hàng',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Bạn cần đăng nhập để theo dõi đơn đang giao, lịch sử đơn hàng, đánh giá và đơn nháp.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => context.push('/signin'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColor.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Đăng nhập',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_bootstrapped) {
      _bootstrapped = true;
      Future.microtask(() {
        ref.read(myOrdersControllerProvider.notifier).bootstrap();
      });
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Đơn hàng',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            child: Row(
              children: [
                _TabButton(
                  title: 'Đang đến',
                  count: st.counts.activeCount,
                  selected: st.tab == MyOrderTab.active,
                  onTap: () => ctrl.changeTab(MyOrderTab.active),
                ),
                _TabButton(
                  title: 'Đánh giá',
                  count: st.counts.reviewCount,
                  selected: st.tab == MyOrderTab.reviews,
                  onTap: () => ctrl.changeTab(MyOrderTab.reviews),
                ),
                _TabButton(
                  title: 'Lịch sử',
                  count: st.counts.historyCount,
                  selected: st.tab == MyOrderTab.history,
                  onTap: () => ctrl.changeTab(MyOrderTab.history),
                ),
                _TabButton(
                  title: 'Đơn nháp',
                  count: st.counts.draftCount,
                  selected: st.tab == MyOrderTab.drafts,
                  onTap: () => ctrl.changeTab(MyOrderTab.drafts),
                ),
              ],
            ),
          ),
          if (st.error != null)
            Container(
              width: double.infinity,
              color: Colors.red.withOpacity(0.06),
              padding: const EdgeInsets.all(12),
              child: Text(st.error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: ctrl.refreshCurrent,
              child: Builder(
                builder: (_) {
                  switch (st.tab) {
                    case MyOrderTab.active:
                      return _buildActiveTab(st);
                    case MyOrderTab.reviews:
                      return _buildReviewsTab(st);
                    case MyOrderTab.history:
                      return _buildHistoryTab(st);
                    case MyOrderTab.drafts:
                      return _buildDraftsTab(st);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTab(MyOrdersState st) {
    if (st.loadingActive && st.activeItems.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (st.activeItems.isEmpty) {
      return const _EmptyView(
        title: 'Quên chưa đặt món rồi nè bạn ơi?',
        subtitle:
            'Bạn sẽ nhìn thấy các món đang được chuẩn bị hoặc giao đi tại đây để kiểm tra đơn hàng nhanh hơn!',
      );
    }

    return ListView.separated(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: st.activeItems.length + (st.loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i >= st.activeItems.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        final item = st.activeItems[i];
        return _OrderCard(
          item: item,
          onTap: () => context.push('/orders/${item.id}'),
        );
      },
    );
  }

  Widget _buildHistoryTab(MyOrdersState st) {
    if (st.loadingHistory && st.historyItems.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (st.historyItems.isEmpty) {
      return const _EmptyView(
        title:
            'Cùng ShopeeFood tạo thật nhiều kỷ niệm ăn uống tưng bừng bạn nhé!',
        subtitle:
            'Bạn sẽ nhìn thấy các món đã đặt tại đây để có thể thưởng thức lại món yêu thích bất cứ lúc nào!',
      );
    }

    return ListView.separated(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: st.historyItems.length + (st.loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i >= st.historyItems.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        final item = st.historyItems[i];
        return _OrderCard(
          item: item,
          onTap: () => context.push('/orders/${item.id}'),
        );
      },
    );
  }

  Widget _buildReviewsTab(MyOrdersState st) {
    if (st.loadingReviews && st.reviewItems.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (st.reviewItems.isEmpty) {
      return const _EmptyView(
        title: 'Bạn chưa có đánh giá nào',
        subtitle:
            'Sau khi hoàn thành đơn hàng, các đánh giá của bạn sẽ hiện ở đây.',
      );
    }

    return ListView.separated(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: st.reviewItems.length + (st.loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i >= st.reviewItems.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        final item = st.reviewItems[i];

        return _ReviewCard(
          item: item,
          onTapCard: () {
            if (item.entityType == 'product' &&
                item.product != null &&
                item.product!.id.isNotEmpty) {
              context.push(
                '/product/${item.product!.id}',
                extra: {
                  'lat': 0.0,
                  'lng': 0.0,
                  'merchantId': item.merchant?.id,
                },
              );
              return;
            }

            if (item.merchant != null && item.merchant!.id.isNotEmpty) {
              context.push(
                '/merchant/${item.merchant!.id}',
                extra: {'lat': 0.0, 'lng': 0.0},
              );
            }
          },
          onTapMerchant: item.merchant == null
              ? null
              : () {
                  context.push(
                    '/merchant/${item.merchant!.id}',
                    extra: {'lat': 0.0, 'lng': 0.0},
                  );
                },
          onTapProduct: item.product == null
              ? null
              : () {
                  context.push(
                    '/product/${item.product!.id}',
                    extra: {
                      'lat': 0.0,
                      'lng': 0.0,
                      'merchantId': item.merchant?.id,
                    },
                  );
                },
        );
      },
    );
  }

  Widget _buildDraftsTab(MyOrdersState st) {
    if (st.loadingDrafts && st.draftItems.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (st.draftItems.isEmpty) {
      return const _EmptyView(
        title: 'Bạn chưa có đơn nháp nào',
        subtitle:
            'Các giỏ hàng đang lưu dở của bạn sẽ hiển thị ở đây để vào đặt tiếp nhanh hơn.',
      );
    }

    return ListView.separated(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: st.draftItems.length + (st.loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i >= st.draftItems.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        final item = st.draftItems[i];
        return _DraftCartCard(
          item: item,
          onTap: () {
            context.push(
              '/merchant/${item.merchant.id}',
              extra: {'lat': 0.0, 'lng': 0.0},
            );
          },
        );
      },
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.title,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColor.primary : Colors.black87;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(top: 14, bottom: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColor.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColor.primary.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.item, required this.onTap});

  final MyOrderListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = item.itemsPreview.join(', ');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MerchantImage(url: item.merchant.logoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.merchant.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusChip(label: item.statusLabel),
                        _OrderTypeChip(orderType: item.orderType),
                        if (item.etaMin != null)
                          Text(
                            '${item.etaMin} phút',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      preview.isEmpty ? '${item.itemCount} món' : preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _money(item.totalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftCartCard extends StatelessWidget {
  const _DraftCartCard({required this.item, required this.onTap});

  final MyDraftCartItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = item.itemsPreview.join(', ');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MerchantImage(
                url: item.previewImageUrl ?? item.merchant.logoUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Đơn nháp',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.merchant.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    if (item.merchant.address.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.merchant.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          height: 1.25,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      preview.isEmpty ? '${item.itemCount} món' : preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_money(item.totalAmount)} (${item.itemCount} món)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.item,
    required this.onTapCard,
    required this.onTapMerchant,
    required this.onTapProduct,
  });

  final MyReviewListItem item;
  final VoidCallback onTapCard;
  final VoidCallback? onTapMerchant;
  final VoidCallback? onTapProduct;

  @override
  Widget build(BuildContext context) {
    final typeLabel = item.entityType == 'merchant'
        ? 'Đánh giá quán'
        : 'Đánh giá món ăn';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTapCard,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                typeLabel,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < item.rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: const Color(0xFFF5A623),
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (item.comment.trim().isNotEmpty)
                Text(item.comment, style: const TextStyle(height: 1.3)),
              if (item.merchant != null) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: onTapMerchant,
                  child: Text(
                    'Quán: ${item.merchant!.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColor.primary,
                    ),
                  ),
                ),
              ],
              if (item.product != null) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: onTapProduct,
                  child: Text(
                    'Sản phẩm: ${item.product!.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColor.primary,
                    ),
                  ),
                ),
              ],
              if (item.images.isNotEmpty ||
                  (item.videoUrl != null &&
                      item.videoUrl!.trim().isNotEmpty)) ...[
                const SizedBox(height: 12),
                _OrderReviewMediaStrip(
                  images: item.images,
                  videoUrl: item.videoUrl,
                  onTapImage: (initialIndex) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _OrderReviewImageViewerPage(
                          images: item.images,
                          initialIndex: initialIndex,
                        ),
                      ),
                    );
                  },
                ),
              ],
              if (item.merchantReply != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColor.accentOrange.withOpacity(.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Phản hồi từ quán:',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                      Text(
                        ' ${item.merchantReply!.content}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColor.headerGradEnd,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderReviewMediaStrip extends StatelessWidget {
  const _OrderReviewMediaStrip({
    required this.images,
    required this.videoUrl,
    required this.onTapImage,
  });

  final List<Map<String, dynamic>> images;
  final String? videoUrl;
  final void Function(int index) onTapImage;

  @override
  Widget build(BuildContext context) {
    final hasVideo = videoUrl != null && videoUrl!.trim().isNotEmpty;

    if (images.isEmpty && !hasVideo) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length + (hasVideo ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          if (index < images.length) {
            final url = (images[index]['url'] ?? '').toString();

            return GestureDetector(
              onTap: () => onTapImage(index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(width: 84, height: 84, color: Colors.black12),
                  errorWidget: (_, __, ___) => Container(
                    width: 84,
                    height: 84,
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            );
          }

          return Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.videocam_rounded),
          );
        },
      ),
    );
  }
}

class _OrderReviewImageViewerPage extends StatefulWidget {
  const _OrderReviewImageViewerPage({
    required this.images,
    required this.initialIndex,
  });

  final List<Map<String, dynamic>> images;
  final int initialIndex;

  @override
  State<_OrderReviewImageViewerPage> createState() =>
      _OrderReviewImageViewerPageState();
}

class _OrderReviewImageViewerPageState
    extends State<_OrderReviewImageViewerPage> {
  late final PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, index) {
                final url = (widget.images[index]['url'] ?? '').toString();

                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Iconsax.arrow_left_copy,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          '${_current + 1}/${widget.images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColor.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColor.primary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _OrderTypeChip extends StatelessWidget {
  const _OrderTypeChip({required this.orderType});

  final String orderType;

  @override
  Widget build(BuildContext context) {
    final isDineIn = orderType == 'dine_in';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDineIn
            ? AppColor.info.withOpacity(0.10)
            : AppColor.success.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isDineIn ? 'Tại quán' : 'Giao hàng',
        style: TextStyle(
          color: isDineIn ? AppColor.info : AppColor.success,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MerchantImage extends StatelessWidget {
  const _MerchantImage({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 72,
        height: 72,
        color: Colors.grey.withOpacity(0.12),
        child: (url == null || url!.isEmpty)
            ? const Icon(Icons.storefront_rounded, color: Colors.grey)
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.storefront_rounded, color: Colors.grey),
              ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 110),
        const Icon(
          Icons.receipt_long_outlined,
          size: 96,
          color: AppColor.primary,
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 15,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

String _money(num v) {
  final s = v.toInt().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => '.',
  );
  return '$s đ';
}
