import 'package:customer/app/theme/app_color.dart';
import 'package:customer/core/di/providers.dart';
import 'package:customer/core/utils/formatters.dart';
import 'package:customer/features/addresses/data/models/choose_address_result.dart';
import 'package:customer/features/addresses/data/models/saved_address_models.dart';
import 'package:customer/features/addresses/data/models/search_place_models.dart';
import 'package:customer/features/orders/data/models/checkout_delivery_draft.dart';
import 'package:customer/features/orders/presentation/pages/checkout_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

String pickText(String? primary, String? fallback) {
  final p = (primary ?? '').trim();
  if (p.isNotEmpty) return p;
  return (fallback ?? '').trim();
}

bool _hasValidLatLng(double? lat, double? lng) {
  if (lat == null || lng == null) return false;
  if (lat == 0 && lng == 0) return false;
  return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

bool _sameDraft(CheckoutDeliveryDraft? a, CheckoutDeliveryDraft? b) {
  if (a == null || b == null) return false;

  final sameAddress =
      a.address.trim().toLowerCase() == b.address.trim().toLowerCase();

  final sameLat = (a.lat - b.lat).abs() < 0.00001;
  final sameLng = (a.lng - b.lng).abs() < 0.00001;

  return sameAddress && sameLat && sameLng;
}

class AddressPage extends ConsumerWidget {
  const AddressPage({
    super.key,
    this.pickForCheckout = false,
    this.checkoutDraft,
    this.entryDraft,
  });
  final bool pickForCheckout;
  final CheckoutDeliveryDraft? checkoutDraft;
  final CheckoutDeliveryDraft? entryDraft;
  Future<void> _pickFromSearch(BuildContext context, WidgetRef ref) async {
    final picked = await context.push<SearchPlaceItem>('/address/search');
    if (!context.mounted || picked == null) return;

    if (picked.lat == null || picked.lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Địa chỉ chưa xác định được toạ độ, vui lòng chọn lại'),
        ),
      );
      return;
    }

    final address = picked.subtitle.trim().isNotEmpty
        ? '${picked.title}, ${picked.subtitle}'
        : picked.title;

    if (!pickForCheckout) {
      final current = ref.read(addressControllerProvider).current;

      await ref
          .read(addressControllerProvider.notifier)
          .setCurrentManual(
            address: address,
            lat: picked.lat!,
            lng: picked.lng!,
            receiverName: current?.receiverName,
            receiverPhone: current?.receiverPhone,
            deliveryNote: current?.deliveryNote,
          );
      return;
    }

    context.pop(
      CheckoutDeliveryDraft(
        lat: picked.lat!,
        lng: picked.lng!,
        address: address,
        receiverName: checkoutDraft?.receiverName ?? '',
        receiverPhone: checkoutDraft?.receiverPhone ?? '',
        addressNote: checkoutDraft?.addressNote ?? '',
      ),
    );
  }

  Future<void> _pickFromMap(BuildContext context, WidgetRef ref) async {
    final picked = await context.push<ChooseAddressResult>('/address/choose');
    if (!context.mounted || picked == null) return;

    if (!pickForCheckout) {
      final current = ref.read(addressControllerProvider).current;

      await ref
          .read(addressControllerProvider.notifier)
          .setCurrentManual(
            address: picked.address,
            lat: picked.lat,
            lng: picked.lng,
            receiverName: current?.receiverName,
            receiverPhone: current?.receiverPhone,
            deliveryNote: current?.deliveryNote,
          );
      return;
    }

    context.pop(
      CheckoutDeliveryDraft(
        lat: picked.lat,
        lng: picked.lng,
        address: picked.address,
        receiverName: checkoutDraft?.receiverName ?? '',
        receiverPhone: checkoutDraft?.receiverPhone ?? '',
        addressNote: checkoutDraft?.addressNote ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(addressControllerProvider);
    final saved = st.saved;
    final ghostEntryDraft =
        pickForCheckout &&
            entryDraft != null &&
            checkoutDraft != null &&
            !_sameDraft(entryDraft, checkoutDraft)
        ? entryDraft
        : null;
    final displayAddress = pickForCheckout
        ? (checkoutDraft?.address ?? '').trim()
        : (st.current?.address ?? '').trim();

    final displayReceiverName = pickForCheckout
        ? (checkoutDraft?.receiverName ?? '').trim()
        : (st.current?.receiverName ?? '').trim();

    final displayReceiverPhone = pickForCheckout
        ? (checkoutDraft?.receiverPhone ?? '').trim()
        : (st.current?.receiverPhone ?? '').trim();

    final (title, subtitle) = _splitByFirstComma(displayAddress);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: _AddressAppBar(
        title: pickForCheckout
            ? 'Chọn địa chỉ cho đơn hàng'
            : 'Địa chỉ giao hàng',
        onBack: () => context.pop(),
        onTapMap: () => _pickFromMap(context, ref),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            const SizedBox(height: 4),
            _Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _pickFromSearch(context, ref),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: Color(0xFF9CA3AF)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tìm vị trí',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB0B7C3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Card địa chỉ hiện tại
            _Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: pickForCheckout && checkoutDraft != null
                    ? () => context.pop(checkoutDraft)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _LeadingIcon(
                        icon: Icons.location_on,
                        color: AppColor.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: displayAddress.isEmpty
                            ? Text(
                                pickForCheckout
                                    ? 'Chưa có địa chỉ đang dùng cho đơn hàng'
                                    : 'Chưa có địa chỉ hiện tại',
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6B7280),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  if (subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      subtitle,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        height: 1.25,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                  if (displayReceiverName.isNotEmpty ||
                                      displayReceiverPhone.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      '${displayReceiverName.isEmpty ? '—' : displayReceiverName} | ${displayReceiverPhone.isEmpty ? '—' : displayReceiverPhone}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF374151),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                      if (pickForCheckout && checkoutDraft != null)
                        TextButton(
                          onPressed: () async {
                            final updated = await context
                                .push<CheckoutDeliveryDraft>(
                                  '/address/add',
                                  extra: {'checkoutDraft': checkoutDraft},
                                );

                            if (!context.mounted || updated == null) return;
                            context.pop(updated);
                          },
                          child: const Text(
                            'Sửa',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColor.primary,
                            ),
                          ),
                        )
                      else if (st.isFetching)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),
            if (ghostEntryDraft != null)
              _CheckoutDraftRow(
                title: 'Địa chỉ ban đầu',
                draft: ghostEntryDraft,
                onTap: () => context.pop(ghostEntryDraft),
              ),
            const SizedBox(height: 18),
            const Text(
              'Địa chỉ đã lưu',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 10),

            _Card(
              child: saved.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Chưa có địa chỉ đã lưu',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (int i = 0; i < saved.length; i++) ...[
                          _SavedRow(
                            item: saved[i],
                            onTapUse: () async {
                              if (pickForCheckout) {
                                final item = saved[i];

                                context.pop(
                                  CheckoutDeliveryDraft(
                                    lat: item.lat ?? checkoutDraft?.lat ?? 0,
                                    lng: item.lng ?? checkoutDraft?.lng ?? 0,
                                    address: item.address,
                                    receiverName: pickText(
                                      item.receiverName,
                                      checkoutDraft?.receiverName,
                                    ),
                                    receiverPhone: pickText(
                                      item.receiverPhone,
                                      checkoutDraft?.receiverPhone,
                                    ),
                                    addressNote: pickText(
                                      item.deliveryNote,
                                      checkoutDraft?.addressNote,
                                    ),
                                  ),
                                );
                                return;
                              }

                              final ctrl = ref.read(
                                addressControllerProvider.notifier,
                              );
                              await ctrl.useSavedAsCurrent(saved[i]);
                              if (context.mounted) context.pop();
                            },
                            onTapEdit: () async {
                              await context.push(
                                '/address/add',
                                extra: saved[i],
                              );
                              // quay lại thì list đã tự reload khi save/delete
                            },
                          ),
                          if (i != saved.length - 1) const _DividerInset(),
                        ],
                      ],
                    ),
            ),

            const SizedBox(height: 90),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => context.push('/address/add'),
              child: const Text(
                'Thêm địa chỉ mới',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
    );
  }

  (String, String) _splitByFirstComma(String input) {
    final s = input.trim();
    if (s.isEmpty) return ('', '');
    final idx = s.indexOf(',');
    if (idx < 0) return (s, '');
    final head = s.substring(0, idx).trim();
    final tail = s.substring(idx + 1).trim();
    return (head.isEmpty ? s : head, tail);
  }
}

class _CheckoutDraftRow extends StatelessWidget {
  const _CheckoutDraftRow({
    required this.title,
    required this.draft,
    required this.onTap,
  });

  final String title;
  final CheckoutDeliveryDraft draft;
  final VoidCallback onTap;

  (String, String) _split(String input) {
    final s = input.trim();
    if (s.isEmpty) return ('', '');
    final idx = s.indexOf(',');
    if (idx < 0) return (s, '');
    return (s.substring(0, idx).trim(), s.substring(idx + 1).trim());
  }

  @override
  Widget build(BuildContext context) {
    final (head, tail) = _split(draft.address);

    return _Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _LeadingIcon(icon: Icons.history, color: AppColor.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      head,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    if (tail.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        tail,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.25,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${draft.receiverName.isEmpty ? '—' : draft.receiverName} | ${draft.receiverPhone.isEmpty ? '—' : draft.receiverPhone}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'Chọn',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColor.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.item,
    required this.onTapUse,
    required this.onTapEdit,
  });

  final SavedAddress item;
  final VoidCallback onTapUse;
  final VoidCallback onTapEdit;

  (String, String) _split(String input) {
    final s = input.trim();
    if (s.isEmpty) return ('', '');
    final idx = s.indexOf(',');
    if (idx < 0) return (s, '');
    return (s.substring(0, idx).trim(), s.substring(idx + 1).trim());
  }

  @override
  Widget build(BuildContext context) {
    final (t, sub) = _split(item.address);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTapUse, // chọn => use => pop về home
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _LeadingIcon(
              icon: Icons.location_on_outlined,
              color: Color(0xFF111827),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.isNotEmpty ? t : item.address,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      sub,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.25,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            TextButton(
              onPressed: onTapEdit,
              style: TextButton.styleFrom(
                foregroundColor: AppColor.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              child: const Text(
                'Sửa',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== UI =====
class _AddressAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AddressAppBar({
    required this.title,
    required this.onBack,
    required this.onTapMap,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onTapMap;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 6);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      actions: [
        IconButton(
          onPressed: onTapMap,
          icon: const Icon(Icons.map_outlined),
          color: AppColor.primary,
        ),
      ],
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      leading: IconButton(
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        color: AppColor.primary,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 28, child: Icon(icon, color: color, size: 22));
  }
}

class _DividerInset extends StatelessWidget {
  const _DividerInset();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 54),
      child: Divider(height: 1, thickness: 1, color: Color(0xFFF1F3F5)),
    );
  }
}
