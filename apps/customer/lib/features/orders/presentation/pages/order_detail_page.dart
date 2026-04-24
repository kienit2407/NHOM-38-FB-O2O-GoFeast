import 'package:cached_network_image/cached_network_image.dart';
import 'package:customer/app/theme/app_color.dart';
import 'package:customer/core/di/providers.dart';
import 'package:customer/features/orders/data/models/customer_order_detail_model.dart';
import 'package:customer/features/orders/data/models/customer_review_models.dart';
import 'package:customer/features/orders/presentation/viewmodels/customer_order_review_controller.dart';
import 'package:customer/features/orders/presentation/widgets/customer_review_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  bool _loading = true;
  bool _canceling = false;
  bool _timelineExpanded = false;
  String? _error;
  CustomerOrderDetail? _detail;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refreshPage);
  }

  Future<void> _refreshPage() async {
    await _load();
    await ref
        .read(customerOrderReviewControllerProvider(widget.orderId).notifier)
        .load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(myOrdersRepositoryProvider);
      final data = await repo.fetchCustomerOrderDetail(widget.orderId);
      if (!mounted) return;
      setState(() {
        _detail = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Không tải được chi tiết đơn hàng';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _cancelOrder() async {
    final detail = _detail;
    if (detail == null || !detail.actions.canCancel || _canceling) return;

    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Huỷ đơn hàng'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Bạn có chắc muốn huỷ đơn này không?',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Lý do huỷ (không bắt buộc)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Đóng'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Huỷ đơn'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    setState(() {
      _canceling = true;
    });

    try {
      final repo = ref.read(myOrdersRepositoryProvider);
      await repo.cancelPendingOrder(
        detail.id,
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã huỷ đơn hàng')));

      await _refreshPage();
      ref.invalidate(myOrdersControllerProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Huỷ đơn thất bại')));
    } finally {
      if (!mounted) return;
      setState(() {
        _canceling = false;
      });
    }
  }

  Future<void> _openMerchantReview() async {
    final detail = _detail;
    final merchantId = detail?.merchant?.id.trim();

    if (detail == null || merchantId == null || merchantId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy merchantId')),
      );
      return;
    }

    final changed = await showCustomerReviewDialog(
      context: context,
      ref: ref,
      orderId: widget.orderId,
      target: CustomerReviewTarget.merchant,
      reviewState: ref.read(
        customerOrderReviewControllerProvider(widget.orderId),
      ),
      merchantId: merchantId,
    );

    if (!mounted || changed != true) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshPage();
    });
  }

  Future<void> _openDriverReview() async {
    final detail = _detail;
    final driverUserId = detail?.driver?.id.trim();

    if (detail == null || driverUserId == null || driverUserId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy driverUserId')),
      );
      return;
    }

    final changed = await showCustomerReviewDialog(
      context: context,
      ref: ref,
      orderId: widget.orderId,
      target: CustomerReviewTarget.driver,
      reviewState: ref.read(
        customerOrderReviewControllerProvider(widget.orderId),
      ),
      driverUserId: driverUserId,
    );

    if (!mounted || changed != true) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshPage();
    });
  }

  Future<void> _openProductReviewPicker() async {
    final detail = _detail;
    if (detail == null) return;

    final items = detail.items
        .where((e) => (e.productId ?? '').isNotEmpty)
        .toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đơn này không có món để đánh giá')),
      );
      return;
    }

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
                    color: AppColor.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Chọn món để đánh giá',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColor.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _SquareImage(url: item.image, size: 52),
                        title: Text(
                          item.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColor.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '${item.quantity} x ${_formatMoneyStatic(item.unitPrice)}',
                          style: const TextStyle(
                            color: AppColor.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          context.push(
                            '/product/${item.productId}',
                            extra: {
                              'lat': 0.0,
                              'lng': 0.0,
                              'merchantId': detail.merchant?.id,
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColor.warning;
      case 'searching_driver':
      case 'merchant_notified':
      case 'dispatch_searching':
      case 'dispatch_retrying':
      case 'confirmed':
      case 'driver_assigned':
      case 'driver_arrived':
      case 'picked_up':
      case 'delivering':
        return AppColor.info;
      case 'preparing':
      case 'ready_for_pickup':
        return const Color(0xFF7C4DFF);
      case 'delivered':
      case 'completed':
        return AppColor.success;
      case 'cancelled':
        return AppColor.danger;
      case 'dispatch_expired':
        return AppColor.warning;
      default:
        return AppColor.textSecondary;
    }
  }

  String _statusTimelineLabel(String status, String orderType) {
    final isDineIn = orderType == 'dine_in';

    switch (status) {
      case 'pending':
        return 'Đã tạo đơn';
      case 'merchant_notified':
        return 'Đã báo quán';
      case 'dispatch_searching':
      case 'dispatch_retrying':
        return isDineIn ? 'Đang xử lý đơn tại quán' : 'Đang tìm tài xế';
      case 'dispatch_expired':
        return isDineIn ? 'Đang xử lý đơn tại quán' : 'Chưa tìm được tài xế';
      case 'confirmed':
        return isDineIn ? 'Quán đã xác nhận' : 'Đơn đã được tiếp nhận';
      case 'preparing':
        return 'Quán đang chuẩn bị';
      case 'ready_for_pickup':
        return isDineIn ? 'Sẵn sàng phục vụ tại quán' : 'Đơn sẵn sàng lấy';
      case 'driver_assigned':
        return isDineIn ? 'Đang phục vụ tại quán' : 'Đã có tài xế';
      case 'driver_arrived':
        return isDineIn ? 'Đơn đã được phục vụ' : 'Tài xế đã tới quán';
      case 'picked_up':
        return isDineIn ? 'Món đã được nhận tại quán' : 'Tài xế đã lấy món';
      case 'delivering':
        return isDineIn ? 'Đang phục vụ tại quán' : 'Tài xế đang giao';
      case 'delivered':
        return isDineIn ? 'Đã phục vụ khách tại quán' : 'Đã giao tới khách';
      case 'completed':
        return 'Đơn hoàn thành';
      case 'cancelled':
        return 'Đơn đã huỷ';
      default:
        return status;
    }
  }

  String _statusTimelineNote(String status, String? rawNote, String orderType) {
    final isDineIn = orderType == 'dine_in';

    switch (status) {
      case 'merchant_notified':
        return 'Hệ thống đã gửi thông báo đơn mới đến quán.';
      case 'dispatch_searching':
      case 'dispatch_retrying':
        return isDineIn
            ? 'Quán đang tiếp nhận và xử lý đơn tại bàn.'
            : 'Hệ thống đang tìm tài xế phù hợp cho đơn hàng.';
      case 'dispatch_expired':
        return isDineIn
            ? 'Quán đang xử lý đơn tại bàn.'
            : 'Hệ thống chưa tìm được tài xế phù hợp. Quán có thể thử tìm lại.';
      case 'driver_assigned':
        return isDineIn
            ? 'Đơn của bạn đã được quán tiếp nhận phục vụ.'
            : 'Một tài xế đã nhận đơn giao hàng của bạn.';
      case 'pending':
        return rawNote?.trim().isNotEmpty == true
            ? rawNote!.trim()
            : 'Đơn hàng của bạn đã được tạo thành công.';
      default:
        if ((rawNote ?? '').trim().isNotEmpty) return rawNote!.trim();
        return '';
    }
  }

  String _paymentMethodLabel(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
      case 'cod':
        return 'Tiền mặt';
      case 'vnpay':
        return 'VNPay';
      case 'momo':
        return 'MoMo';
      default:
        return method;
    }
  }

  String _paymentStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Chờ thanh toán';
      case 'paid':
      case 'success':
      case 'succeeded':
        return 'Đã thanh toán';
      case 'failed':
        return 'Thanh toán thất bại';
      case 'cancelled':
        return 'Đã huỷ';
      case 'refunded':
        return 'Đã hoàn tiền';
      default:
        return status;
    }
  }

  static String _formatMoneyStatic(num v) {
    return '${NumberFormat.decimalPattern('vi_VN').format(v.round())} đ';
  }

  String _formatMoney(num v) => _formatMoneyStatic(v);

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('dd/MM/yyyy • HH:mm').format(dt.toLocal());
  }

  void _onBackPressed() {
    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }
    context.go('/orders');
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final reviewState = ref.watch(
      customerOrderReviewControllerProvider(widget.orderId),
    );

    final canReviewProduct =
        detail != null &&
        detail.status == 'completed' &&
        detail.items.any((e) => (e.productId ?? '').isNotEmpty);

    final timelineItems = detail?.statusHistory ?? const [];
    final displayedTimeline = _timelineExpanded || timelineItems.length <= 3
        ? timelineItems
        : timelineItems.take(3).toList();

    return Scaffold(
      backgroundColor: AppColor.background,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: _onBackPressed,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: const Text(
          'Chi tiết đơn hàng',
          style: TextStyle(
            color: AppColor.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColor.textPrimary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _error != null || detail == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.receipt_long_rounded,
                      size: 72,
                      color: AppColor.textMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error ?? 'Không có dữ liệu',
                      style: const TextStyle(color: AppColor.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: _refreshPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColor.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              color: AppColor.primary,
              onRefresh: _refreshPage,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  _TopHeroCard(
                    orderNumber: detail.orderNumber,
                    statusLabel: detail.displayStatusLabel,
                    orderTypeLabel: detail.orderType == 'dine_in'
                        ? 'Tại quán'
                        : 'Giao hàng',
                    statusColor: _statusColor(detail.displayStatus),
                    createdAt: _formatDateTime(detail.createdAt),
                    totalAmount: _formatMoney(detail.totalAmount),
                  ),
                  const SizedBox(height: 12),

                  if (timelineItems.isNotEmpty)
                    _SectionCard(
                      title: 'Hành trình đơn hàng',
                      child: Column(
                        children: [
                          ...List.generate(displayedTimeline.length, (i) {
                            final item = displayedTimeline[i];
                            final isLast = i == displayedTimeline.length - 1;
                            return _TimelineItem(
                              isLast: isLast,
                              title: _statusTimelineLabel(
                                item.status,
                                detail.orderType,
                              ),
                              time: _formatDateTime(item.changedAt),
                              note: _statusTimelineNote(
                                item.status,
                                item.note,
                                detail.orderType,
                              ),
                              color: _statusColor(item.status),
                            );
                          }),
                          if (timelineItems.length > 3) ...[
                            const SizedBox(height: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setState(() {
                                  _timelineExpanded = !_timelineExpanded;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColor.surfaceWarm,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColor.border),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _timelineExpanded
                                          ? 'Thu gọn'
                                          : 'Xem thêm hành trình',
                                      style: const TextStyle(
                                        color: AppColor.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      _timelineExpanded
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      color: AppColor.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (timelineItems.isNotEmpty) const SizedBox(height: 12),

                  if (detail.merchant != null)
                    _SectionCard(
                      title: 'Thông tin quán',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          context.push(
                            '/merchant/${detail.merchant!.id}',
                            extra: {'lat': 0.0, 'lng': 0.0},
                          );
                        },
                        child: Row(
                          children: [
                            _SquareImage(
                              url: detail.merchant!.logoUrl,
                              size: 56,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    detail.merchant!.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppColor.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    detail.merchant!.address,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColor.textSecondary,
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColor.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (detail.merchant != null) const SizedBox(height: 12),

                  if (detail.driver != null)
                    _SectionCard(
                      title: 'Tài xế',
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: AppColor.surfaceWarm,
                            backgroundImage:
                                (detail.driver!.avatarUrl ?? '').isNotEmpty
                                ? CachedNetworkImageProvider(
                                    detail.driver!.avatarUrl!,
                                  )
                                : null,
                            child: (detail.driver!.avatarUrl ?? '').isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: AppColor.textMuted,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detail.driver!.fullName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: AppColor.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  detail.driver!.phone,
                                  style: const TextStyle(
                                    color: AppColor.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (detail.driver != null) const SizedBox(height: 12),

                  if (detail.deliveryAddress != null)
                    _SectionCard(
                      title: 'Địa chỉ giao hàng',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${detail.deliveryAddress!.receiverName} • ${detail.deliveryAddress!.receiverPhone}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppColor.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            detail.deliveryAddress!.address,
                            style: const TextStyle(
                              color: AppColor.textPrimary,
                              height: 1.35,
                            ),
                          ),
                          if (detail.deliveryAddress!.note
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColor.surfaceWarm,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Ghi chú: ${detail.deliveryAddress!.note}',
                                style: const TextStyle(
                                  color: AppColor.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (detail.deliveryAddress != null)
                    const SizedBox(height: 12),

                  _SectionCard(
                    title: 'Món đã đặt',
                    child: Column(
                      children: List.generate(detail.items.length, (i) {
                        final item = detail.items[i];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: i == detail.items.length - 1 ? 0 : 14,
                          ),
                          child: _OrderItemTile(
                            item: item,
                            formatMoney: _formatMoney,
                            onTap: item.productId == null
                                ? null
                                : () {
                                    context.push(
                                      '/product/${item.productId}',
                                      extra: {
                                        'lat': 0.0,
                                        'lng': 0.0,
                                        'merchantId': detail.merchant?.id,
                                      },
                                    );
                                  },
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _SectionCard(
                    title: 'Thanh toán',
                    child: Column(
                      children: [
                        _PriceRow(
                          label: 'Tạm tính',
                          value: _formatMoney(detail.subtotal),
                        ),
                        if (detail.orderType == 'delivery')
                          _PriceRow(
                            label: 'Phí giao hàng',
                            value: _formatMoney(detail.deliveryFee),
                          ),
                        if (detail.discounts.foodDiscount > 0)
                          _PriceRow(
                            label: 'Giảm giá món ăn',
                            value:
                                '-${_formatMoney(detail.discounts.foodDiscount)}',
                            valueColor: AppColor.success,
                          ),
                        if (detail.discounts.deliveryDiscount > 0)
                          _PriceRow(
                            label: 'Giảm phí giao',
                            value:
                                '-${_formatMoney(detail.discounts.deliveryDiscount)}',
                            valueColor: AppColor.success,
                          ),
                        const Divider(height: 20, color: AppColor.divider),
                        _PriceRow(
                          label: 'Tổng cộng',
                          value: _formatMoney(detail.totalAmount),
                          bold: true,
                        ),
                        const SizedBox(height: 8),
                        _PriceRow(
                          label: 'Phương thức thanh toán',
                          value: _paymentMethodLabel(detail.paymentMethod),
                        ),
                        _PriceRow(
                          label: 'Trạng thái thanh toán',
                          value: _paymentStatusLabel(detail.paymentStatus),
                          valueColor:
                              detail.paymentStatus.toLowerCase() == 'paid'
                              ? AppColor.success
                              : AppColor.textPrimary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (detail.actions.canCancel ||
                      detail.actions.canReviewMerchant ||
                      detail.actions.canReviewDriver ||
                      canReviewProduct)
                    _SectionCard(
                      title: 'Thao tác',
                      child: Column(
                        children: [
                          if (detail.actions.canCancel)
                            _ActionButton(
                              label: 'Huỷ đơn hàng',
                              onPressed: _canceling ? null : _cancelOrder,
                              loading: _canceling,
                              outlined: true,
                              color: AppColor.danger,
                            ),
                          if (detail.actions.canReviewMerchant) ...[
                            if (detail.actions.canCancel)
                              const SizedBox(height: 10),
                            _ActionButton(
                              label:
                                  reviewState.status?.merchantReview.exists ==
                                      true
                                  ? 'Chỉnh sửa đánh giá quán'
                                  : 'Đánh giá quán',
                              onPressed: reviewState.submitting
                                  ? null
                                  : _openMerchantReview,
                              color: AppColor.primary,
                            ),
                          ],
                          if (detail.actions.canReviewDriver) ...[
                            const SizedBox(height: 10),
                            _ActionButton(
                              label:
                                  reviewState.status?.driverReview.exists ==
                                      true
                                  ? 'Chỉnh sửa đánh giá tài xế'
                                  : 'Đánh giá tài xế',
                              onPressed: reviewState.submitting
                                  ? null
                                  : _openDriverReview,
                              outlined: true,
                              color: AppColor.primary,
                            ),
                          ],
                          if (canReviewProduct) ...[
                            const SizedBox(height: 10),
                            _ActionButton(
                              label: 'Đánh giá món ăn',
                              onPressed: _openProductReviewPicker,
                              outlined: true,
                              color: AppColor.info,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: detail == null
          ? null
          : FloatingActionButton.small(
              heroTag: 'copy_order_number',
              backgroundColor: Colors.white,
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: detail.orderNumber),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép mã đơn')),
                );
              },
              child: const Icon(
                Icons.copy,
                color: AppColor.textPrimary,
                size: 20,
              ),
            ),
    );
  }
}

class _TopHeroCard extends StatelessWidget {
  const _TopHeroCard({
    required this.orderNumber,
    required this.statusLabel,
    required this.orderTypeLabel,
    required this.statusColor,
    required this.createdAt,
    required this.totalAmount,
  });

  final String orderNumber;
  final String statusLabel;
  final String orderTypeLabel;
  final Color statusColor;
  final String createdAt;
  final String totalAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColor.headerGradStart, AppColor.headerGradEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: statusColor.withOpacity(0.45), width: 1.1),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColor.primary.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _HeroInfo(label: 'Mã đơn hàng', value: orderNumber),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  statusLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                orderTypeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroInfo(label: 'Thời gian tạo', value: createdAt),
              ),
              Expanded(
                child: _HeroInfo(
                  label: 'Tổng thanh toán',
                  value: totalAmount,
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroInfo extends StatelessWidget {
  const _HeroInfo({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColor.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: AppColor.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.isLast,
    required this.title,
    required this.time,
    required this.note,
    required this.color,
  });

  final bool isLast;
  final String title;
  final String time;
  final String note;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColor.border,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColor.textPrimary,
                    ),
                  ),
                  if (time.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      time,
                      style: const TextStyle(
                        color: AppColor.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (note.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      note,
                      style: const TextStyle(
                        color: AppColor.textSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderItemTile extends StatelessWidget {
  const _OrderItemTile({
    required this.item,
    required this.formatMoney,
    required this.onTap,
  });

  final CustomerOrderItem item;
  final String Function(num v) formatMoney;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SquareImage(url: item.image, size: 72),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColor.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.quantity} x ${formatMoney(item.unitPrice)}',
                style: const TextStyle(
                  color: AppColor.textSecondary,
                  fontSize: 13,
                ),
              ),
              if (item.selectedOptions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.selectedOptions
                      .map((o) => '${o['option_name']}: ${o['choice_name']}')
                      .join(', '),
                  style: const TextStyle(
                    color: AppColor.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
              if (item.selectedToppings.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.selectedToppings
                      .map(
                        (t) =>
                            '${t['topping_name']} x${t['quantity']} (+${formatMoney((t['unit_price'] as num?) ?? 0)})',
                      )
                      .join(', '),
                  style: const TextStyle(
                    color: AppColor.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatMoney(item.itemTotal),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: AppColor.textPrimary,
          ),
        ),
      ],
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }
}

class _SquareImage extends StatelessWidget {
  const _SquareImage({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: size,
        height: size,
        color: AppColor.surfaceWarm,
        child: (url == null || url!.isEmpty)
            ? const Icon(Icons.fastfood_rounded, color: AppColor.textMuted)
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Icon(
                  Icons.fastfood_rounded,
                  color: AppColor.textMuted,
                ),
              ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontSize: bold ? 15 : 13,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
      color: valueColor ?? AppColor.textPrimary,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 15 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: AppColor.textSecondary,
              ),
            ),
          ),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.outlined = false,
    required this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outlined;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Text(label, style: const TextStyle(fontWeight: FontWeight.w700));

    if (outlined) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: child,
      ),
    );
  }
}
