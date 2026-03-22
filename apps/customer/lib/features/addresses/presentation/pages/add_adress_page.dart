import 'package:customer/app/theme/app_color.dart';
import 'package:customer/core/di/providers.dart';
import 'package:customer/features/addresses/data/models/choose_address_result.dart';
import 'package:customer/features/addresses/data/models/saved_address_models.dart';
import 'package:customer/features/auth/domain/entities/auth_user.dart'
    hide SavedAddress;
import 'package:customer/features/auth/presentation/viewmodels/auth_providers.dart';
import 'package:customer/features/orders/data/models/checkout_delivery_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AddAddressPage extends ConsumerStatefulWidget {
  const AddAddressPage({super.key, this.editing})
    : checkoutDraftEditing = null,
      returnCheckoutDraftOnly = false;

  const AddAddressPage.checkoutDraft({
    super.key,
    required CheckoutDeliveryDraft draft,
  }) : editing = null,
       checkoutDraftEditing = draft,
       returnCheckoutDraftOnly = true;

  final SavedAddress? editing;
  final CheckoutDeliveryDraft? checkoutDraftEditing;
  final bool returnCheckoutDraftOnly;

  @override
  ConsumerState<AddAddressPage> createState() => _AddAddressPageState();
}

class _AddAddressPageState extends ConsumerState<AddAddressPage> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String? _pickedAddress;
  double? _pickedLat;
  double? _pickedLng;

  bool _didPrefill = false;

  bool get _isEdit => widget.editing != null;
  bool get _isCheckoutDraftEdit =>
      widget.returnCheckoutDraftOnly && widget.checkoutDraftEditing != null;
  bool get _canSave {
    return _nameCtrl.text.trim().isNotEmpty &&
        _phoneCtrl.text.trim().isNotEmpty &&
        (_pickedAddress?.trim().isNotEmpty == true);
  }

  @override
  void initState() {
    super.initState();

    final e = widget.editing;
    final draft = widget.checkoutDraftEditing;

    if (draft != null) {
      _pickedAddress = draft.address;
      _pickedLat = draft.lat;
      _pickedLng = draft.lng;
      _nameCtrl.text = draft.receiverName;
      _phoneCtrl.text = draft.receiverPhone;
      _noteCtrl.text = draft.addressNote;
      _didPrefill = true;
      return;
    }

    if (e != null) {
      _pickedAddress = e.address;
      _pickedLat = e.lat;
      _pickedLng = e.lng;
      _nameCtrl.text = (e.receiverName ?? '').trim();
      _phoneCtrl.text = (e.receiverPhone ?? '').trim();
      _noteCtrl.text = (e.deliveryNote ?? '').trim();
      _didPrefill = true;
      return;
    }

    _tryPrefillFromUser(ref.read(authViewModelProvider).valueOrNull);
  }

  void _tryPrefillFromUser(AuthUser? user) {
    if (user == null) return;
    if (_didPrefill) return;
    if (_isEdit || _isCheckoutDraftEdit) return;

    final name = (user.fullName ?? '').trim();
    final phone = (user.phone ?? '').trim();

    bool changed = false;
    if (_nameCtrl.text.trim().isEmpty && name.isNotEmpty) {
      _nameCtrl.text = name;
      changed = true;
    }
    if (_phoneCtrl.text.trim().isEmpty && phone.isNotEmpty) {
      _phoneCtrl.text = phone;
      changed = true;
    }

    if (changed) _didPrefill = true;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAddress() async {
    final result = await context.push<ChooseAddressResult>('/address/choose');
    if (result == null) return;

    setState(() {
      _pickedAddress = result.address;
      _pickedLat = result.lat;
      _pickedLng = result.lng;
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;

    if (_isCheckoutDraftEdit) {
      if (!mounted) return;

      context.pop(
        CheckoutDeliveryDraft(
          lat: _pickedLat ?? 0,
          lng: _pickedLng ?? 0,
          address: _pickedAddress ?? '',
          receiverName: _nameCtrl.text.trim(),
          receiverPhone: _phoneCtrl.text.trim(),
          addressNote: _noteCtrl.text.trim(),
        ),
      );
      return;
    }

    final ctrl = ref.read(addressControllerProvider.notifier);

    if (_isEdit) {
      await ctrl.updateSaved(
        widget.editing!.id,
        address: _pickedAddress,
        lat: _pickedLat,
        lng: _pickedLng,
        receiverName: _nameCtrl.text.trim(),
        receiverPhone: _phoneCtrl.text.trim(),
        deliveryNote: _noteCtrl.text.trim().isEmpty
            ? null
            : _noteCtrl.text.trim(),
      );
    } else {
      await ctrl.createSaved(
        address: _pickedAddress!,
        lat: _pickedLat,
        lng: _pickedLng,
        receiverName: _nameCtrl.text.trim(),
        receiverPhone: _phoneCtrl.text.trim(),
        deliveryNote: _noteCtrl.text.trim().isEmpty
            ? null
            : _noteCtrl.text.trim(),
      );
    }

    if (!mounted) return;
    context.pop();
  }

  Future<void> _delete() async {
    final e = widget.editing;
    if (e == null) return;

    await ref.read(addressControllerProvider.notifier).deleteSaved(e.id);

    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AuthUser?>>(authViewModelProvider, (prev, next) {
      _tryPrefillFromUser(next.valueOrNull);
    });
    final kb = MediaQuery.viewInsetsOf(context).bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F6F6),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(
            _isCheckoutDraftEdit
                ? 'Sửa địa chỉ đơn hàng'
                : (_isEdit ? 'Sửa địa chỉ' : 'Thêm địa chỉ mới'),
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: AppColor.primary,
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _Card(
                child: Column(
                  children: [
                    _InputRow(
                      controller: _nameCtrl,
                      hintText: 'Họ và tên',
                      onChanged: (_) => setState(() {}),
                    ),
                    const _DividerInset(),
                    _InputRow(
                      controller: _phoneCtrl,
                      hintText: 'Số điện thoại',
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              _Card(
                child: _SelectRow(
                  title: _pickedAddress?.isNotEmpty == true
                      ? _pickedAddress!
                      : 'Chọn địa chỉ',
                  isPlaceholder: !(_pickedAddress?.isNotEmpty == true),
                  onTap: _pickAddress,
                ),
              ),

              const SizedBox(height: 12),

              _Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    cursorColor: AppColor.primary,
                    controller: _noteCtrl,
                    minLines: 6,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Ghi chú cho Tài xế (không bắt buộc)',
                      hintStyle: TextStyle(
                        color: Color(0xFFB0B7C3),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              ),

              if (_isEdit) ...[
                const SizedBox(height: 12),
                _Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _delete,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Center(
                        child: Text(
                          'Xoá địa chỉ',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 90),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.fromLTRB(16, 0, 16, 14 + kb),
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _canSave ? _save : null,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColor.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  disabledForegroundColor: const Color(0xFF9CA3AF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Lưu',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== UI small widgets (y như bạn) =====

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

class _DividerInset extends StatelessWidget {
  const _DividerInset();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 12),
      child: Divider(height: 1, thickness: 1, color: Color(0xFFF1F3F5)),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            cursorColor: AppColor.primary,
            controller: controller,
            keyboardType: keyboardType,
            onChanged: onChanged,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hintText,
              hintStyle: const TextStyle(
                color: Color(0xFFB0B7C3),
                fontWeight: FontWeight.w600,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectRow extends StatelessWidget {
  const _SelectRow({
    required this.title,
    required this.onTap,
    required this.isPlaceholder,
  });

  final String title;
  final VoidCallback onTap;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: isPlaceholder
                      ? const Color(0xFFB0B7C3)
                      : const Color(0xFF111827),
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}
