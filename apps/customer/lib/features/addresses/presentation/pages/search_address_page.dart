// lib/features/addresses/presentation/pages/search_address_page.dart
import 'dart:async';

import 'package:customer/app/theme/app_color.dart';
import 'package:customer/core/di/providers.dart';
import 'package:customer/features/addresses/data/models/search_place_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class SearchAddressPage extends ConsumerStatefulWidget {
  const SearchAddressPage({
    super.key,
    this.initialQuery,
    this.biasLat,
    this.biasLng,
  });

  final String? initialQuery;
  final double? biasLat;
  final double? biasLng;

  @override
  ConsumerState<SearchAddressPage> createState() => _SearchAddressPageState();
}

class _SearchAddressPageState extends ConsumerState<SearchAddressPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  Timer? _debounce;
  CancelToken? _cancel;

  bool _isLoading = false;
  bool _isResolving = false;

  String _query = '';
  List<SearchPlaceItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.initialQuery ?? '';
    _query = _ctrl.text.trim();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
      if (_query.isNotEmpty) _triggerSearch(_query);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancel?.cancel('dispose');
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    final q = v.trim();
    setState(() => _query = q);

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _triggerSearch(q);
    });
  }

  Future<void> _triggerSearch(String q) async {
    if (!mounted) return;

    _cancel?.cancel('new search');
    _cancel = CancelToken();

    if (q.isEmpty) {
      setState(() {
        _isLoading = false;
        _items = const [];
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(addressRepositoryProvider);
      final items = await repo.autocompletePublic(
        input: q,
        lat: widget.biasLat,
        lng: widget.biasLng,
        size: 8,
        cancelToken: _cancel,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _items = items;
      });
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _items = const [];
      });
    }
  }

  Future<void> _pickItem(SearchPlaceItem item) async {
    final text = (item.description ?? item.subtitle).trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không xác định được vị trí này')),
      );
      return;
    }

    setState(() => _isResolving = true);

    try {
      final repo = ref.read(addressRepositoryProvider);
      final resolved = await repo.resolveByTextSearchPublic(text: text);

      if (!mounted) return;
      setState(() => _isResolving = false);

      if (resolved == null || resolved.lat == null || resolved.lng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không lấy được toạ độ của địa chỉ này, hãy thử địa chỉ khác',
            ),
          ),
        );
        return;
      }

      Navigator.of(context).pop(
        item.copyWith(
          lat: resolved.lat,
          lng: resolved.lng,
          description: resolved.description ?? item.description,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isResolving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không lấy được toạ độ của địa chỉ này')),
      );
    }
  }

  void _clear() {
    _ctrl.clear();
    _onChanged('');
    _focus.requestFocus();
  }

  void _cancelPage() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final showEmpty = !_isLoading && _query.isNotEmpty && _items.isEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        toolbarHeight: 62,
        titleSpacing: 12,
        title: Row(
          children: [
            Expanded(
              child: _SearchField(
                controller: _ctrl,
                focusNode: _focus,
                hintText: 'Tìm vị trí',
                onChanged: _onChanged,
                onClear: _clear,
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _cancelPage,
              child: const Text(
                'Huỷ',
                style: TextStyle(
                  color: AppColor.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Column(
              children: [
                if (_isLoading)
                  const LinearProgressIndicator(
                    minHeight: 1.2,
                    backgroundColor: Color(0xFFF3F4F6),
                    color: AppColor.primary,
                  )
                else
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFF1F3F5),
                  ),
                Expanded(
                  child: showEmpty
                      ? const _EmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.only(top: 4),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFF1F3F5),
                          ),
                          itemBuilder: (context, i) {
                            final item = _items[i];
                            return _SearchResultTile(
                              item: item,
                              query: _query,
                              onTap: () => _pickItem(item), //  pop về Add
                            );
                          },
                        ),
                ),
              ],
            ),

            if (_isResolving)
              Positioned.fill(
                child: Container(
                  color: Colors.white.withOpacity(0.6),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CupertinoActivityIndicator(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ===================== UI (y như bản bạn) =====================

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, value, __) {
          final hasText = value.text.trim().isNotEmpty;

          return TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            cursorColor: AppColor.primary, //  cursor primary
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111827),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF3F4F6),

              hintText: hintText,
              hintStyle: const TextStyle(
                color: Color(0xFF9CA3AF),
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),

              //  icon trái
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: Color(0xFF9CA3AF),
              ),

              //  clear nằm TRONG TextField luôn
              suffixIcon: hasText
                  ? GestureDetector(
                      onTap: () {
                        onClear();
                        focusNode.requestFocus();
                      },
                      child: const Icon(
                        Iconsax.tag_cross_copy,
                        size: 20,
                        color: AppColor.primary,
                      ),
                    )
                  : null,
              //  padding để text nằm giữa
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 0,
              ),

              //  bình thường KHÔNG viền
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),

              //  focus mới hiện viền primary
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColor.primary, width: 1),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.item,
    required this.query,
    required this.onTap,
  });

  final SearchPlaceItem item;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.location_on_outlined,
                size: 22,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightText(
                    text: item.title,
                    query: query,
                    baseStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                    highlightStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColor.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.subtitle,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.25,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}

class _HighlightText extends StatelessWidget {
  const _HighlightText({
    required this.text,
    required this.query,
    required this.baseStyle,
    required this.highlightStyle,
  });

  final String text;
  final String query;
  final TextStyle baseStyle;
  final TextStyle highlightStyle;

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) return Text(text, style: baseStyle);

    final lowerText = text.toLowerCase();
    final lowerQ = q.toLowerCase();
    final idx = lowerText.indexOf(lowerQ);
    if (idx < 0) return Text(text, style: baseStyle);

    final before = text.substring(0, idx);
    final match = text.substring(idx, idx + q.length);
    final after = text.substring(idx + q.length);

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: before, style: baseStyle),
          TextSpan(text: match, style: highlightStyle),
          TextSpan(text: after, style: baseStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Không tìm thấy kết quả',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
