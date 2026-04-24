import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:customer/app/theme/app_color.dart';
import 'package:customer/core/di/providers.dart';
import 'package:customer/core/utils/checkout_error_ui.dart';
import 'package:customer/features/auth/presentation/viewmodels/auth_providers.dart';
import 'package:customer/features/cart/data/repositories/cart_repository.dart';
import 'package:customer/features/merchant/presentation/pages/merchant_detail_page.dart';
import 'package:customer/features/orders/data/models/checkout_delivery_draft.dart';
import 'package:customer/features/orders/data/models/checkout_models.dart';
import 'package:customer/features/orders/presentation/pages/payment_webview_page.dart';
import 'package:customer/features/orders/presentation/viewmodels/checkout_state.dart';
import 'package:customer/features/promotion/data/models/promotion_models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage.delivery({
    super.key,
    required this.merchantId,
    required CheckoutDeliveryDraft deliveryDraft,
    this.onEditDeliveryAddress,
    this.onAddMoreItems,
    this.onEditItem,
    this.onOrderPlaced,
  }) : mode = CheckoutMode.delivery,
       tableSessionId = '',
       initialDeliveryDraft = deliveryDraft;

  const CheckoutPage.dineIn({
    super.key,
    required this.tableSessionId,
    this.onAddMoreItems,
    this.onEditItem,
    this.onOrderPlaced,
  }) : mode = CheckoutMode.dineIn,
       merchantId = '',
       initialDeliveryDraft = null,
       onEditDeliveryAddress = null;

  final CheckoutMode mode;
  final String merchantId;
  final String tableSessionId;
  final CheckoutDeliveryDraft? initialDeliveryDraft;

  final Future<CheckoutDeliveryDraft?> Function(
    CheckoutDeliveryDraft current,
    CheckoutDeliveryDraft entry,
  )?
  onEditDeliveryAddress;
  final Future<void> Function()? onAddMoreItems;
  final Future<void> Function(CheckoutCartLine item)? onEditItem;
  final Future<void> Function(PlaceOrderResponse result)? onOrderPlaced;

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _voucherCtrl = TextEditingController();
  CheckoutParams get _checkoutParams => widget.mode == CheckoutMode.delivery
      ? CheckoutParams.delivery(merchantId: widget.merchantId)
      : CheckoutParams.dineIn(tableSessionId: widget.tableSessionId);

  CartParams get _cartParams => widget.mode == CheckoutMode.delivery
      ? CartParams.delivery(merchantId: widget.merchantId)
      : CartParams.dineIn(tableSessionId: widget.tableSessionId);
  bool _suppressNextErrorSnack = false;
  @override
  void initState() {
    super.initState();

    _noteCtrl.addListener(() {
      ref
          .read(checkoutProvider(_checkoutParams).notifier)
          .setOrderNote(_noteCtrl.text);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final checkoutCtrl = ref.read(checkoutProvider(_checkoutParams).notifier);

      if (widget.mode == CheckoutMode.delivery &&
          widget.initialDeliveryDraft != null) {
        final d = widget.initialDeliveryDraft!;
        checkoutCtrl.setDeliveryAddress(
          lat: d.lat,
          lng: d.lng,
          address: d.address,
          receiverName: d.receiverName,
          receiverPhone: d.receiverPhone,
          addressNote: d.addressNote,
        );
      }

      await checkoutCtrl.loadPreview();
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _voucherCtrl.dispose();
    super.dispose();
  }

  Future<void> _reloadPreview() async {
    await ref.read(checkoutProvider(_checkoutParams).notifier).refreshPreview();
  }

  CheckoutDeliveryDraft _buildCurrentDraft() {
    final st = ref.read(checkoutProvider(_checkoutParams));
    final d = st.preview?.delivery;
    final fallback = widget.initialDeliveryDraft;

    return CheckoutDeliveryDraft(
      lat: d?.lat ?? fallback?.lat ?? 0,
      lng: d?.lng ?? fallback?.lng ?? 0,
      address: (d?.address ?? fallback?.address ?? '').trim(),
      receiverName: (d?.receiverName ?? fallback?.receiverName ?? '').trim(),
      receiverPhone: (d?.receiverPhone ?? fallback?.receiverPhone ?? '').trim(),
      addressNote: (d?.note ?? fallback?.addressNote ?? '').trim(),
    );
  }

  Future<bool> _ensureVoucherLogin() async {
    final user = ref.read(authViewModelProvider).valueOrNull;
    if (user != null) return true;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đăng nhập để sử dụng voucher')),
      );
    }

    await context.push('/signin');
    if (!mounted) return false;

    return ref.read(authViewModelProvider).valueOrNull != null;
  }

  Future<void> _applyVoucherFromInput() async {
    final code = _voucherCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng nhập mã voucher')));
      return;
    }

    if (!await _ensureVoucherLogin()) return;

    await ref
        .read(checkoutProvider(_checkoutParams).notifier)
        .applyVoucher(code);
  }

  Future<void> _clearVoucher() async {
    _voucherCtrl.clear();
    await ref.read(checkoutProvider(_checkoutParams).notifier).removeVoucher();
  }

  Future<void> _openSavedVoucherSheet(CheckoutPreviewResponse preview) async {
    if (!await _ensureVoucherLogin()) return;

    await ref.read(myVouchersControllerProvider.notifier).loadInitial();
    if (!mounted) return;

    final selected = await showModalBottomSheet<SavedVoucherItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: _SavedVoucherPickerSheet(preview: preview),
      ),
    );

    if (selected == null) return;

    _voucherCtrl.text = selected.voucherCode;
    await ref
        .read(checkoutProvider(_checkoutParams).notifier)
        .applyVoucher(selected.voucherCode);
  }

  Future<void> _placeOrder() async {
    ref
        .read(checkoutProvider(_checkoutParams).notifier)
        .setOrderNote(_noteCtrl.text.trim());

    final result = await ref
        .read(checkoutProvider(_checkoutParams).notifier)
        .placeOrder();

    if (!mounted || result == null) return;

    if (result.requiresOnlinePayment &&
        result.paymentAction?.url != null &&
        result.paymentAction!.url!.trim().isNotEmpty) {
      final paymentReturn = await Navigator.of(context)
          .push<PaymentGatewayReturn>(
            MaterialPageRoute(
              builder: (_) =>
                  PaymentWebViewPage(initialUrl: result.paymentAction!.url!),
            ),
          );

      if (!mounted) return;

      if (paymentReturn == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bạn chưa hoàn tất thanh toán online')),
        );
        return;
      }

      context.go(
        '/checkout/result',
        extra: CheckoutResultArgs(result: result, paymentReturn: paymentReturn),
      );
      return;
    }

    if (widget.onOrderPlaced != null) {
      await widget.onOrderPlaced!(result);
      return;
    }

    if (!mounted) return;

    context.go('/checkout/result', extra: CheckoutResultArgs(result: result));
  }

  Future<void> _handleEditAddress() async {
    if (widget.onEditDeliveryAddress == null) return;

    final currentDraft = _buildCurrentDraft();
    final entryDraft = widget.initialDeliveryDraft ?? currentDraft;

    final next = await widget.onEditDeliveryAddress!(currentDraft, entryDraft);

    if (!mounted || next == null) return;

    ref
        .read(checkoutProvider(_checkoutParams).notifier)
        .setDeliveryAddress(
          lat: next.lat,
          lng: next.lng,
          address: next.address,
          receiverName: next.receiverName,
          receiverPhone: next.receiverPhone,
          addressNote: next.addressNote,
        );

    _suppressNextErrorSnack = true;
    await _reloadPreview();
    _suppressNextErrorSnack = false;

    if (!mounted) return;

    final latest = ref.read(checkoutProvider(_checkoutParams));
    if (latest.error != null) {
      await showCheckoutErrorDialog(
        context,
        message: mapCheckoutErrorMessage(latest.error),
      );
    }
  }

  Future<void> _handleAddMore() async {
    if (widget.onAddMoreItems == null) return;
    await widget.onAddMoreItems!.call();
    if (!mounted) return;
    await _reloadPreview();
  }

  Future<void> _handleEditItem(CheckoutCartLine item) async {
    if (widget.onEditItem == null) return;
    await widget.onEditItem!(item);
    if (!mounted) return;
    await _reloadPreview();
  }

  Future<void> _changeQty(CheckoutCartLine item, int nextQty) async {
    final cartCtrl = ref.read(cartProvider(_cartParams).notifier);

    if (nextQty <= 0) {
      await cartCtrl.removeLine(item.lineKey);
    } else {
      await cartCtrl.updateQty(item.lineKey, nextQty);
    }

    if (!mounted) return;
    await _reloadPreview();
  }

  Future<void> _openPaymentSheet(CheckoutPaymentMethod current) async {
    final selected = await showModalBottomSheet<CheckoutPaymentMethod>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) {
        final options = CheckoutPaymentMethod.values;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Chọn phương thức thanh toán',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ...options.map(
                  (e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      e == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: const Color(0xFFEE4D2D),
                    ),
                    title: Text(_paymentLabel(e)),
                    onTap: () => Navigator.pop(context, e),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) return;

    ref
        .read(checkoutProvider(_checkoutParams).notifier)
        .setPaymentMethod(selected);
    await _reloadPreview();
  }

  Future<void> _openNoteSheet(String current) async {
    final ctrl = TextEditingController(text: current);

    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ghi chú cho đơn hàng',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              TextField(
                cursorColor: CupertinoColors.activeBlue,
                controller: ctrl,
                style: TextStyle(fontSize: 12),
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Nhập ghi chú...',
                  filled: true,
                  hintStyle: TextStyle(fontSize: 12),
                  fillColor: const Color(0xFFF7F7F7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEE4D2D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, ctrl.text.trim()),
                  child: const Text('Lưu'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (saved == null) return;
    _noteCtrl.text = saved;
    ref.read(checkoutProvider(_checkoutParams).notifier).setOrderNote(saved);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(checkoutProvider(_checkoutParams));
    final cartState = ref.watch(cartProvider(_cartParams));

    ref.listen<CheckoutState>(checkoutProvider(_checkoutParams), (prev, next) {
      if (next.error != null && next.error != prev?.error && mounted) {
        if (_suppressNextErrorSnack) return;

        final msg = mapCheckoutErrorMessage(next.error);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg)));
      }
    });

    final preview = state.preview;
    final isBusy = state.isLoading || cartState.isUpdating;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Xác nhận đơn hàng',
          style: TextStyle(
            color: Color(0xFF222222),
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFFEE4D2D)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: preview == null
          ? _InitialBody(
              isLoading: state.isLoading,
              error: state.error == null
                  ? null
                  : mapCheckoutErrorMessage(state.error),
              onRetry: _reloadPreview,
            )
          : Stack(
              children: [
                RefreshIndicator(
                  onRefresh: _reloadPreview,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
                    children: [
                      if (preview.isDelivery && preview.delivery != null)
                        _DeliveryCard(
                          info: preview.delivery!,
                          onEdit: _handleEditAddress,
                        ),
                      if (preview.isDineIn && preview.dineIn != null)
                        _DineInCard(info: preview.dineIn!),

                      const SizedBox(height: 12),

                      _ItemsCard(
                        merchantName: preview.merchant.name,
                        items: preview.cart.items,
                        onAddMore: widget.onAddMoreItems == null
                            ? null
                            : _handleAddMore,
                        onEditItem: widget.onEditItem == null
                            ? null
                            : _handleEditItem,
                        onDecrease: (item) =>
                            _changeQty(item, item.quantity - 1),
                        onIncrease: (item) =>
                            _changeQty(item, item.quantity + 1),
                      ),

                      const SizedBox(height: 12),

                      _CheckoutVoucherCard(
                        state: state,
                        preview: preview,
                        voucherController: _voucherCtrl,
                        onApply: _applyVoucherFromInput,
                        onClear: _clearVoucher,
                        onOpenCouponList: () => _openSavedVoucherSheet(preview),
                      ),

                      const SizedBox(height: 12),

                      if (preview.isDelivery) ...[
                        _PaymentCard(
                          method: state.paymentMethod,
                          onTap: () => _openPaymentSheet(state.paymentMethod),
                        ),
                        const SizedBox(height: 12),
                      ],

                      _PricingCard(
                        pricing: preview.pricing,
                        promotions: preview.promotions,
                        itemCount: preview.cart.itemCount,
                      ),

                      const SizedBox(height: 12),

                      _NoteCard(
                        value: _noteCtrl.text.trim(),
                        onTap: () => _openNoteSheet(_noteCtrl.text.trim()),
                      ),
                    ],
                  ),
                ),

                if (isBusy)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: Colors.black.withOpacity(0.04),
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator.adaptive(),
                      ),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: preview == null
          ? null
          : _BottomBar(
              total: preview.pricing.totalAmount,
              loading: state.isPlacing,
              onPressed: state.isPlacing ? null : _placeOrder,
            ),
    );
  }
}

class _InitialBody extends StatelessWidget {
  const _InitialBody({
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final bool isLoading;
  final String? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error ?? 'Không tải được dữ liệu checkout',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEE4D2D),
              ),
              onPressed: onRetry,
              child: const Text('Tải lại'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.info, required this.onEdit});

  final CheckoutDeliveryInfo info;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: Color(0xFFEE4D2D),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  info.address ?? 'Chưa có địa chỉ',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ),
              TextButton(
                onPressed: onEdit,
                child: Text(
                  'Sửa',
                  style: TextStyle(
                    color: CupertinoColors.activeBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              '${info.receiverName ?? '—'}  |  ${info.receiverPhone ?? '—'}',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF444444),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              'Khoảng cách ${formatDistance(info.distanceKm)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF7A7A7A)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.access_time, color: Color(0xFFEE4D2D), size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Thời gian giao dự kiến: ${_formatEta(info.etaAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DineInCard extends StatelessWidget {
  const _DineInCard({required this.info});

  final CheckoutDineInInfo info;

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Thông tin tại quán',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Table session', value: info.tableSessionId),
          const SizedBox(height: 8),
          _InfoRow(label: 'Table ID', value: info.tableId ?? '—'),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Thời gian chuẩn bị',
            value: '${info.estimatedPrepTimeMin} phút',
          ),
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({
    required this.merchantName,
    required this.items,
    required this.onAddMore,
    required this.onEditItem,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String merchantName;
  final List<CheckoutCartLine> items;
  final VoidCallback? onAddMore;
  final Future<void> Function(CheckoutCartLine item)? onEditItem;
  final Future<void> Function(CheckoutCartLine item) onDecrease;
  final Future<void> Function(CheckoutCartLine item) onIncrease;

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.storefront_outlined,
                color: Color(0xFF666666),
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  merchantName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
              if (onAddMore != null)
                TextButton(onPressed: onAddMore, child: const Text('Thêm món')),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _CheckoutItemTile(
                item: item,
                onEdit: onEditItem == null ? null : () => onEditItem!(item),
                onDecrease: () => onDecrease(item),
                onIncrease: () => onIncrease(item),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutItemTile extends StatelessWidget {
  const _CheckoutItemTile({
    required this.item,
    required this.onEdit,
    required this.onDecrease,
    required this.onIncrease,
  });

  final CheckoutCartLine item;
  final VoidCallback? onEdit;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final sub = _buildSubText(item);

    return Container(
      padding: EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12, width: .7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 70,
              height: 70,
              child: item.imageUrl == null || item.imageUrl!.isEmpty
                  ? Container(
                      color: const Color(0xFFF0F0F0),
                      alignment: Alignment.center,
                      child: const Icon(Icons.fastfood, color: Colors.grey),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF989898),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        _money(item.unitPrice),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFEE4D2D),
                        ),
                      ),
                      if (item.basePrice != null &&
                          item.basePrice! > item.unitPrice)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            _money(item.basePrice!),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFFB7B7B7),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      const Spacer(),
                      _QtyButton(
                        icon: Icons.remove,
                        filled: false,
                        onTap: onDecrease,
                      ),
                      SizedBox(
                        width: 34,
                        child: Center(
                          child: Text(
                            '${item.quantity}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                      _QtyButton(
                        icon: Icons.add,
                        filled: true,
                        onTap: onIncrease,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = filled ? const Color(0xFFEE4D2D) : Colors.transparent;
    final border = filled ? Colors.transparent : const Color(0xFFDCDCDC);
    final iconColor = filled ? Colors.white : const Color(0xFFAAAAAA);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Icon(icon, size: 14, color: iconColor),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.method, required this.onTap});

  final CheckoutPaymentMethod method;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Phương thức thanh toán',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              _paymentLabel(method),
              style: const TextStyle(fontSize: 12, color: Color(0xFF222222)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Color(0xFF9B9B9B)),
          ],
        ),
      ),
    );
  }
}

class _SavedVoucherPickerSheet extends ConsumerWidget {
  const _SavedVoucherPickerSheet({required this.preview});

  final CheckoutPreviewResponse preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(myVouchersControllerProvider);
    final ctrl = ref.read(myVouchersControllerProvider.notifier);
    final items = _filterSavedVouchersForCheckout(st.items, preview);

    if (st.isLoading && st.items.isEmpty) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            'Voucher đã lưu',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: ctrl.refresh,
            child: items.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text(
                          'Không có voucher phù hợp cho đơn này',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: items.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      if (i == items.length) {
                        if (st.isLoadingMore) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: CircularProgressIndicator.adaptive(),
                            ),
                          );
                        }

                        if (st.hasMore) {
                          return TextButton(
                            onPressed: ctrl.loadMore,
                            child: const Text('Tải thêm'),
                          );
                        }

                        return const SizedBox.shrink();
                      }

                      final item = items[i];
                      return _SavedVoucherTile(
                        item: item,
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _SavedVoucherTile extends StatelessWidget {
  const _SavedVoucherTile({required this.item, required this.onTap});

  final SavedVoucherItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final discountText = item.discountType == 'percentage'
        ? 'Giảm ${item.discountValue.toStringAsFixed(0)}%'
        : 'Giảm ${_money(item.discountValue)}';

    final maxText = item.maxDiscount > 0
        ? ' • Tối đa ${_money(item.maxDiscount)}'
        : '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1EE),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.confirmation_number_outlined,
                  color: AppColor.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.voucherCode,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColor.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$discountText$maxText',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (item.minOrderAmount > 0)
                      Text(
                        'Đơn tối thiểu ${_money(item.minOrderAmount)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    if ((item.merchantName ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          item.merchantName!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

class _SponsorDiscountBreakdown {
  final num merchant;
  final num platform;

  const _SponsorDiscountBreakdown({
    required this.merchant,
    required this.platform,
  });
}

_SponsorDiscountBreakdown _buildSponsorDiscountBreakdown(
  CheckoutPromotions promotions,
) {
  num merchant = 0;
  num platform = 0;

  for (final item in promotions.autoApplied) {
    if (item.sponsor == 'merchant') {
      merchant += item.discountAmount;
    } else if (item.sponsor == 'platform') {
      platform += item.discountAmount;
    }
  }

  final voucher = promotions.voucherApplied;
  if (voucher != null) {
    if (voucher.sponsor == 'merchant') {
      merchant += voucher.discountAmount;
    } else if (voucher.sponsor == 'platform') {
      platform += voucher.discountAmount;
    }
  }

  return _SponsorDiscountBreakdown(merchant: merchant, platform: platform);
}

List<SavedVoucherItem> _filterSavedVouchersForCheckout(
  List<SavedVoucherItem> items,
  CheckoutPreviewResponse preview,
) {
  return items
      .where((e) => _isSavedVoucherUsableForCheckout(e, preview))
      .toList();
}

bool _isSavedVoucherUsableForCheckout(
  SavedVoucherItem item,
  CheckoutPreviewResponse preview,
) {
  if (!item.isSaved) return false;
  if (item.isUsed) return false;

  if (item.remainingUserUses != null && item.remainingUserUses! <= 0) {
    return false;
  }

  if (item.perUserLimit > 0 && item.usedCount >= item.perUserLimit) {
    return false;
  }

  if (!_isTimeWindowValid(item.validFrom, item.validTo)) return false;
  if (!_isTimeWindowValid(item.voucherStartDate, item.voucherEndDate)) {
    return false;
  }

  final scope = item.scope.trim().toLowerCase();

  if (preview.mode == CheckoutMode.delivery) {
    if (!(scope == 'food' || scope == 'delivery')) return false;
  } else {
    if (!(scope == 'food' || scope == 'dine_in')) return false;
  }

  final merchantId = item.merchantId?.trim();
  if (merchantId != null &&
      merchantId.isNotEmpty &&
      merchantId != preview.merchant.id) {
    return false;
  }

  return true;
}

bool _isTimeWindowValid(String? fromIso, String? toIso) {
  final now = DateTime.now();

  if (fromIso != null && fromIso.trim().isNotEmpty) {
    final from = DateTime.tryParse(fromIso)?.toLocal();
    if (from != null && now.isBefore(from)) return false;
  }

  if (toIso != null && toIso.trim().isNotEmpty) {
    final to = DateTime.tryParse(toIso)?.toLocal();
    if (to != null && now.isAfter(to)) return false;
  }

  return true;
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({
    required this.pricing,
    required this.promotions,
    required this.itemCount,
  });

  final CheckoutPricing pricing;
  final CheckoutPromotions promotions;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final sponsor = _buildSponsorDiscountBreakdown(promotions);

    return _CardBox(
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tổng thanh toán',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                ),
              ),
              Text(
                _money(pricing.totalAmount),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFEE4D2D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Divider(color: Colors.black12, height: .4),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _PriceRow(
                  label: 'Tổng giá món ($itemCount món)',
                  value: _money(pricing.subtotalBeforeDiscount),
                ),
                if (pricing.foodDiscount > 0) ...[
                  const SizedBox(height: 10),
                  _PriceRow(
                    label: 'Giảm giá món ăn',
                    value: '-${_money(pricing.foodDiscount)}',
                  ),
                ],
                if (pricing.deliveryFeeBeforeDiscount > 0) ...[
                  const SizedBox(height: 10),
                  _PriceRow(
                    label: 'Phí giao hàng',
                    value: _money(pricing.deliveryFeeBeforeDiscount),
                  ),
                ],
                if (pricing.deliveryDiscount > 0) ...[
                  const SizedBox(height: 10),
                  _PriceRow(
                    label: 'Giảm phí vận chuyển',
                    value: '-${_money(pricing.deliveryDiscount)}',
                  ),
                ],
                if (pricing.platformFee > 0) ...[
                  const SizedBox(height: 10),
                  _PriceRow(
                    label: 'Phí khác',
                    value: _money(pricing.platformFee),
                  ),
                ],
                if (sponsor.merchant > 0 || sponsor.platform > 0) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Colors.black12, height: .4),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Chi tiết nguồn ưu đãi',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ),
                  if (sponsor.merchant > 0) ...[
                    const SizedBox(height: 10),
                    _PriceRow(
                      label: 'Quán hỗ trợ',
                      value: '-${_money(sponsor.merchant)}',
                    ),
                  ],
                  if (sponsor.platform > 0) ...[
                    const SizedBox(height: 10),
                    _PriceRow(
                      label: 'Nền tảng hỗ trợ',
                      value: '-${_money(sponsor.platform)}',
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutVoucherCard extends StatelessWidget {
  const _CheckoutVoucherCard({
    required this.state,
    required this.preview,
    required this.voucherController,
    required this.onApply,
    required this.onClear,
    required this.onOpenCouponList,
  });

  final CheckoutState state;
  final CheckoutPreviewResponse preview;
  final TextEditingController voucherController;
  final Future<void> Function() onApply;
  final Future<void> Function() onClear;
  final VoidCallback onOpenCouponList;

  @override
  Widget build(BuildContext context) {
    final appliedVoucher = preview.promotions.voucherApplied;
    final hasAutoPromo = preview.promotions.autoApplied.isNotEmpty;

    return _CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Voucher',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: voucherController,
                  cursorColor: const Color(0xFFEE4D2D),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Nhập mã voucher',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF7F7F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEE4D2D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onApply,
                  child: const Text('Áp dụng'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              InkWell(
                onTap: onOpenCouponList,
                child: Row(
                  mainAxisSize:
                      MainAxisSize.min, // Thu gọn Row vừa khít với nội dung
                  children: [
                    const Text(
                      'Chọn voucher đã lưu',
                      style: TextStyle(color: AppColor.primary),
                    ),
                    const SizedBox(
                      width: 4,
                    ), //  Chỉnh khoảng cách chữ và icon ở đây (ví dụ 4px)
                    const Icon(
                      Iconsax.arrow_right_1_copy,
                      size: 16,
                      color: AppColor.primary,
                      // Thường mũi tên cùng màu với chữ sẽ đẹp hơn
                      // color: AppColor.primary,
                    ),
                  ],
                ),
              ),
              if (state.voucherCode.trim().isNotEmpty || appliedVoucher != null)
                TextButton(
                  onPressed: onClear,
                  child: const Text('Xoá', style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
          if (appliedVoucher != null) ...[
            Text(
              'Đang áp dụng mã ${appliedVoucher.voucherCode}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if (state.voucherCode.trim().isNotEmpty) ...[
            Text(
              'Mã hiện tại: ${state.voucherCode.trim()}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (hasAutoPromo) ...[
            const SizedBox(height: 6),
            const Text(
              'Ưu đãi tự động của quán/nền tảng vẫn sẽ được BE tính cùng với voucher nếu hợp lệ.',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF888888),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Ghi chú:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            Flexible(
              child: Text(
                value.isEmpty ? 'Thêm ghi chú' : value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: value.isEmpty
                      ? const Color(0xFFC4C4C4)
                      : const Color(0xFF333333),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.total,
    required this.loading,
    required this.onPressed,
  });

  final num total;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final padBottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(13, 10, 13, padBottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, -2),
            color: Color(0x12000000),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tổng thanh toán',
                  style: TextStyle(fontSize: 13, color: Color(0xFF7A7A7A)),
                ),
                const SizedBox(height: 2),
                Text(
                  _money(total),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFEE4D2D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 200,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEE4D2D),
                disabledBackgroundColor: const Color(0xFFFFC4B7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onPressed,
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Đặt đơn',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardBox extends StatelessWidget {
  const _CardBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6E6E6E),
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E6E)),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: Color(0xFF7A7A7A))),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

String _buildSubText(CheckoutCartLine item) {
  final parts = <String>[];

  for (final x in item.selectedOptions) {
    if (x is Map) {
      final choiceName = x['choice_name']?.toString() ?? '';
      if (choiceName.isNotEmpty) parts.add(choiceName);
    }
  }

  for (final x in item.selectedToppings) {
    if (x is Map) {
      final toppingName = x['topping_name']?.toString() ?? '';
      final qty = (x['quantity'] as num?)?.toInt() ?? 0;
      if (toppingName.isNotEmpty) {
        parts.add(qty > 1 ? '$toppingName x$qty' : toppingName);
      }
    }
  }

  return parts.join(' • ');
}

String _paymentLabel(CheckoutPaymentMethod m) {
  switch (m) {
    case CheckoutPaymentMethod.cash:
      return 'Tiền mặt';
    case CheckoutPaymentMethod.vnpay:
      return 'VNPay';
    case CheckoutPaymentMethod.momo:
      return 'MoMo';
    case CheckoutPaymentMethod.zalopay:
      return 'ZaloPay';
  }
}

String _money(num v) {
  final s = v.toStringAsFixed(0);
  final out = s.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '${out}đ';
}

String _formatEta(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '—';

  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  final mo = d.month.toString().padLeft(2, '0');

  return '$hh:$mm - Hôm nay $dd/$mo';
}
