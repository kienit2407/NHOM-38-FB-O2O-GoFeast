import 'package:driver/app/theme/app_color.dart';
import 'package:flutter/material.dart';

class EditDriverProfileTextPage extends StatefulWidget {
  const EditDriverProfileTextPage({
    super.key,
    required this.title,
    required this.label,
    required this.initialValue,
    this.hintText,
    this.keyboardType = TextInputType.text,
    this.onSave,
  });

  final String title;
  final String label;
  final String initialValue;
  final String? hintText;
  final TextInputType keyboardType;
  final Future<void> Function(String value)? onSave;

  @override
  State<EditDriverProfileTextPage> createState() =>
      _EditDriverProfileTextPageState();
}

class _EditDriverProfileTextPageState extends State<EditDriverProfileTextPage> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSave {
    final value = _controller.text.trim();
    final initial = widget.initialValue.trim();
    return !_saving && value.isNotEmpty && value != initial;
  }

  Future<void> _handleSave() async {
    if (!_canSave) return;

    final value = _controller.text.trim();

    setState(() => _saving = true);
    try {
      if (widget.onSave != null) {
        await widget.onSave!(value);
      }
      if (!mounted) return;
      Navigator.of(context).pop(value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lưu thất bại: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.background,
      appBar: AppBar(
        backgroundColor: AppColor.background,
        elevation: 0,
        surfaceTintColor: AppColor.background,
        centerTitle: true,
        title: Text(
          widget.title,
          style: const TextStyle(
            color: AppColor.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColor.primary),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColor.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: const TextStyle(
                          color: AppColor.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        keyboardType: widget.keyboardType,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _handleSave(),
                        decoration: InputDecoration(
                          hintText:
                              widget.hintText ??
                              'Nhập ${widget.label.toLowerCase()}',
                          filled: true,
                          fillColor: AppColor.surfaceWarm,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 16,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: AppColor.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: AppColor.primary,
                              width: 1.4,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: AppColor.border,
                            ),
                          ),
                        ),
                        style: const TextStyle(
                          color: AppColor.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: AppColor.surface,
              border: Border(top: BorderSide(color: AppColor.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _canSave ? _handleSave : null,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: AppColor.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColor.border,
                      disabledForegroundColor: AppColor.textMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text(
                            'Lưu',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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
