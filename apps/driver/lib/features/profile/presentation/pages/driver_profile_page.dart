import 'package:driver/app/theme/app_color.dart';
import 'package:driver/core/di/providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'edit_driver_profile_text_page.dart';

class DriverProfilePage extends ConsumerStatefulWidget {
  const DriverProfilePage({super.key});

  @override
  ConsumerState<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends ConsumerState<DriverProfilePage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(driverProfileControllerProvider.notifier).load(),
    );
  }

  static Future<void> _confirmLogout(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Đăng xuất'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Bạn có chắc muốn đăng xuất khỏi tài khoản này không?'),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Huỷ',
              style: TextStyle(
                color: CupertinoColors.activeBlue.resolveFrom(context),
              ),
            ),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Đăng xuất',
              style: TextStyle(
                color: CupertinoColors.destructiveRed.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ref.read(driverAuthControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(driverProfileControllerProvider);
    final profile = st.profile;

    if (st.isLoading && profile == null) {
      return const Scaffold(
        backgroundColor: AppColor.background,
        body: Center(child: CircularProgressIndicator(color: AppColor.primary)),
      );
    }

    if (profile == null) {
      return Scaffold(
        backgroundColor: AppColor.background,
        appBar: AppBar(
          backgroundColor: AppColor.background,
          elevation: 0,
          surfaceTintColor: AppColor.background,
          title: const Text('Tài khoản tài xế'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(st.error ?? 'Không tải được thông tin tài khoản'),
          ),
        ),
      );
    }

    final fullName = (profile.fullName ?? '').trim().isNotEmpty
        ? profile.fullName!.trim()
        : 'Tài xế';
    final phone = profile.phone ?? '';
    final email = profile.email ?? 'Chưa cập nhật email';
    final avatarUrl = profile.avatarUrl;
    final genderLabel = switch (profile.gender) {
      'male' => 'Nam',
      'female' => 'Nữ',
      'other' => 'Khác',
      _ => 'Cập nhật ngay',
    };
    final birthDateLabel = profile.dateOfBirth == null
        ? 'Cập nhật ngay'
        : _formatDate(profile.dateOfBirth!);

    final bankName = (profile.driverProfile.bankName ?? '').trim();
    final bankAccountName = (profile.driverProfile.bankAccountName ?? '')
        .trim();
    final bankAccountNumber = (profile.driverProfile.bankAccountNumber ?? '')
        .trim();

    return AbsorbPointer(
      absorbing: st.isBusy,
      child: Scaffold(
        backgroundColor: AppColor.background,
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 18,
                16,
                36,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColor.headerGradStart,
                    AppColor.headerGradStart,
                    AppColor.headerGradStart,
                    AppColor.headerGradStart,
                    AppColor.headerGradEnd.withOpacity(.78),
                    AppColor.headerGradEnd.withOpacity(.34),
                    Colors.transparent
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _AvatarView(
                    avatarUrl: avatarUrl,
                    name: fullName,
                    radius: 34,
                    isVerified: profile.isVerified,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.92),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _VerificationChip(
                          verified: profile.isVerified,
                          verificationStatus:
                              profile.driverProfile.verificationStatus,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: RefreshIndicator.adaptive(
                  onRefresh: () => ref
                      .read(driverProfileControllerProvider.notifier)
                      .refresh(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
                    child: Column(
                      children: [
                        _SectionCard(
                          children: [
                            _MenuTile(
                              icon: Icons.image_outlined,
                              iconColor: AppColor.primary,
                              title: 'Ảnh đại diện',
                              trailingText: 'Đổi ảnh',
                              onTap: _pickAndUploadAvatar,
                            ),
                            _MenuTile(
                              icon: Icons.person_outline_rounded,
                              iconColor: AppColor.primary,
                              title: 'Họ và tên',
                              trailingText: fullName,
                              onTap: () => _editFullName(fullName),
                            ),
                            _MenuTile(
                              icon: Icons.phone_outlined,
                              iconColor: AppColor.accentTeal,
                              title: 'Số điện thoại',
                              trailingText: phone.isEmpty
                                  ? 'Cập nhật ngay'
                                  : phone,
                              onTap: () => _editPhone(phone),
                            ),
                            _MenuTile(
                              icon: Icons.email_outlined,
                              iconColor: AppColor.info,
                              title: 'Email',
                              trailingText: email,
                              onTap: null,
                            ),
                            _MenuTile(
                              icon: Icons.wc_outlined,
                              iconColor: AppColor.warning,
                              title: 'Giới tính',
                              trailingText: genderLabel,
                              onTap: () => _pickGender(profile.gender),
                            ),
                            _MenuTile(
                              icon: Icons.cake_outlined,
                              iconColor: AppColor.accentOrange,
                              title: 'Ngày sinh',
                              trailingText: birthDateLabel,
                              onTap: () => _pickBirthDate(profile.dateOfBirth),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _SectionCard(
                          children: [
                            _MenuTile(
                              icon: Icons.account_balance_outlined,
                              iconColor: AppColor.primary,
                              title: 'Tên ngân hàng',
                              trailingText: bankName.isEmpty
                                  ? 'Cập nhật ngay'
                                  : bankName,
                              onTap: () => _editBankName(bankName),
                            ),
                            _MenuTile(
                              icon: Icons.badge_outlined,
                              iconColor: AppColor.accentTeal,
                              title: 'Tên chủ tài khoản',
                              trailingText: bankAccountName.isEmpty
                                  ? 'Cập nhật ngay'
                                  : bankAccountName,
                              onTap: () =>
                                  _editBankAccountName(bankAccountName),
                            ),
                            _MenuTile(
                              icon: Icons.credit_card_outlined,
                              iconColor: AppColor.info,
                              title: 'Số tài khoản',
                              trailingText: bankAccountNumber.isEmpty
                                  ? 'Cập nhật ngay'
                                  : bankAccountNumber,
                              onTap: () =>
                                  _editBankAccountNumber(bankAccountNumber),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton(
                            onPressed: () => _confirmLogout(context, ref),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColor.danger,
                              side: const BorderSide(color: AppColor.border),
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Đăng xuất',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (st.isBusy)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColor.primary,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      final path = picked?.files.single.path;
      if (path == null || path.trim().isEmpty) return;

      await ref
          .read(driverProfileControllerProvider.notifier)
          .uploadAvatar(path);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cập nhật ảnh đại diện thành công'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColor.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload ảnh thất bại: $e')));
    }
  }

  Future<void> _editFullName(String currentValue) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditDriverProfileTextPage(
          title: 'Họ và tên',
          label: 'Họ và tên',
          initialValue: currentValue,
          onSave: (value) async {
            await ref
                .read(driverProfileControllerProvider.notifier)
                .updateProfile(fullName: value);
          },
        ),
      ),
    );
  }

  Future<void> _editPhone(String currentValue) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditDriverProfileTextPage(
          title: 'Số điện thoại',
          label: 'Số điện thoại',
          initialValue: currentValue,
          keyboardType: TextInputType.phone,
          onSave: (value) async {
            await ref
                .read(driverProfileControllerProvider.notifier)
                .updateProfile(phone: value);
          },
        ),
      ),
    );
  }

  Future<void> _editBankName(String currentValue) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditDriverProfileTextPage(
          title: 'Tên ngân hàng',
          label: 'Tên ngân hàng',
          initialValue: currentValue,
          onSave: (value) async {
            await ref
                .read(driverProfileControllerProvider.notifier)
                .updateProfile(bankName: value);
          },
        ),
      ),
    );
  }

  Future<void> _editBankAccountName(String currentValue) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditDriverProfileTextPage(
          title: 'Tên chủ tài khoản',
          label: 'Tên chủ tài khoản',
          initialValue: currentValue,
          onSave: (value) async {
            await ref
                .read(driverProfileControllerProvider.notifier)
                .updateProfile(bankAccountName: value);
          },
        ),
      ),
    );
  }

  Future<void> _editBankAccountNumber(String currentValue) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditDriverProfileTextPage(
          title: 'Số tài khoản',
          label: 'Số tài khoản',
          initialValue: currentValue,
          keyboardType: TextInputType.number,
          onSave: (value) async {
            await ref
                .read(driverProfileControllerProvider.notifier)
                .updateProfile(bankAccountNumber: value);
          },
        ),
      ),
    );
  }

  Future<void> _pickGender(String? currentGender) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('Nam'),
                  trailing: currentGender == 'male'
                      ? const Icon(Icons.check, color: AppColor.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop('male'),
                ),
                ListTile(
                  title: const Text('Nữ'),
                  trailing: currentGender == 'female'
                      ? const Icon(Icons.check, color: AppColor.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop('female'),
                ),
                ListTile(
                  title: const Text('Khác'),
                  trailing: currentGender == 'other'
                      ? const Icon(Icons.check, color: AppColor.primary)
                      : null,
                  onTap: () => Navigator.of(context).pop('other'),
                ),
                ListTile(
                  title: const Text('Xoá giới tính'),
                  textColor: AppColor.danger,
                  onTap: () => Navigator.of(context).pop('__clear__'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (value == null) return;

    try {
      if (value == '__clear__') {
        await ref
            .read(driverProfileControllerProvider.notifier)
            .updateProfile(clearGender: true);
      } else {
        await ref
            .read(driverProfileControllerProvider.notifier)
            .updateProfile(gender: value);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật giới tính thành công')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cập nhật thất bại: $e')));
    }
  }

  Future<void> _pickBirthDate(DateTime? currentDate) async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColor.primary,
              onPrimary: Colors.white,
              onSurface: AppColor.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    try {
      await ref
          .read(driverProfileControllerProvider.notifier)
          .updateProfile(dateOfBirth: picked);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật ngày sinh thành công')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cập nhật thất bại: $e')));
    }
  }

  String _formatDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(children: children),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.trailingText,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String trailingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final editable = onTap != null;
    final isPlaceholder =
        trailingText.trim().isEmpty || trailingText == 'Cập nhật ngay';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColor.divider)),
          ),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColor.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  trailingText.isEmpty ? 'Cập nhật ngay' : trailingText,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlaceholder
                        ? AppColor.textMuted
                        : AppColor.textPrimary,
                    fontSize: 13,
                    fontWeight: isPlaceholder
                        ? FontWeight.w500
                        : FontWeight.w600,
                  ),
                ),
              ),
              if (editable) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColor.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarView extends StatelessWidget {
  const _AvatarView({
    required this.avatarUrl,
    required this.name,
    required this.isVerified,
    this.radius = 28,
  });

  final String? avatarUrl;
  final String name;
  final bool isVerified;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'D';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: Colors.white.withOpacity(.22),
          backgroundImage: (avatarUrl?.trim().isNotEmpty ?? false)
              ? NetworkImage(avatarUrl!)
              : null,
          child: (avatarUrl?.trim().isEmpty ?? true)
              ? Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : null,
        ),
        if (isVerified)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              height: 22,
              width: 22,
              decoration: BoxDecoration(
                color: AppColor.success,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

class _VerificationChip extends StatelessWidget {
  const _VerificationChip({
    required this.verified,
    required this.verificationStatus,
  });

  final bool verified;
  final String? verificationStatus;

  @override
  Widget build(BuildContext context) {
    final text = verified
        ? 'Đã duyệt'
        : switch (verificationStatus) {
            'pending' => 'Đang chờ duyệt',
            'rejected' => 'Đã bị từ chối',
            _ => 'Chưa duyệt',
          };

    final bg = verified
        ? Colors.white.withOpacity(.20)
        : Colors.black.withOpacity(.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
