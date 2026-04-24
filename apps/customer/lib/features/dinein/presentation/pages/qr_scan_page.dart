import 'dart:math' as math;
import 'package:customer/app/theme/app_color.dart';
import 'package:customer/core/di/providers.dart';
import 'package:customer/core/utils/checkout_error_ui.dart';
import 'package:customer/core/utils/parse_table_qr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScanPage extends ConsumerStatefulWidget {
  const QrScanPage({super.key});

  @override
  ConsumerState<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends ConsumerState<QrScanPage>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  final ImagePicker _imagePicker = ImagePicker();

  late final AnimationController _lineCtrl;
  bool _isEnteringTable = false;
  bool _popped = false;
  bool _torchOn = false;
  bool _isPickingImage = false;
  double _zoom = 0.0;

  @override
  void initState() {
    super.initState();
    _lineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _lineCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_popped || _isEnteringTable) return;

    final codes = capture.barcodes;
    if (codes.isEmpty) return;

    final value = codes.first.rawValue?.trim();
    if (value == null || value.isEmpty) return;

    await _finishWithResult(value);
  }

  Future<void> _finishWithResult(String rawValue) async {
    if (_popped || _isEnteringTable) return;

    final tableId = parseTableIdFromQr(rawValue);
    if (tableId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR không hợp lệ hoặc không phải mã bàn')),
      );
      return;
    }

    _popped = true;
    _isEnteringTable = true;
    HapticFeedback.mediumImpact();

    try {
      await _controller.stop();
    } catch (_) {}

    if (!mounted) return;
    setState(() {});

    try {
      final dineInCtrl = ref.read(dineInSessionProvider.notifier);
      final ctx = await dineInCtrl.enterTable(tableId: tableId);
      await ref.read(customerSocketServiceProvider).reconnectWithFreshToken();

      if (!mounted) return;

      Navigator.of(context).pop(ctx);
    } catch (e) {
      _popped = false;
      _isEnteringTable = false;

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mapCheckoutErrorMessage(e))));
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _toggleTorch() async {
    if (_isEnteringTable) return;
    try {
      await _controller.toggleTorch();
      if (!mounted) return;
      setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  Future<void> _setZoom(double value) async {
    setState(() => _zoom = value);
    try {
      await _controller.setZoomScale(value);
    } catch (_) {}
  }

  Future<void> _debugEnterTable() async {
    if (_popped || _isEnteringTable) return;

    final inputCtrl = TextEditingController();
    final rawValue = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Debug vào bàn'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Nhập tableId (24 ký tự) hoặc dán URL QR bàn.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: inputCtrl,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Ví dụ: 69b58c7f8729bc5bde25de58',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Huỷ'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(inputCtrl.text.trim()),
              child: const Text('Vào bàn'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    final value = rawValue?.trim() ?? '';
    if (value.isEmpty) return;

    await _finishWithResult(value);
  }

  Future<void> _pickQrFromGallery() async {
    if (_isPickingImage || _popped || _isEnteringTable) return;

    setState(() => _isPickingImage = true);

    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (file == null) {
        if (mounted) setState(() => _isPickingImage = false);
        debugPrint('[QR] user cancelled picking image');
        return;
      }

      debugPrint('[QR] picked image path: ${file.path}');

      final result = await _controller.analyzeImage(file.path);
      debugPrint('[QR] analyzeImage result: $result');

      final codes = result?.barcodes ?? <Barcode>[];
      debugPrint('[QR] barcodes count: ${codes.length}');

      for (final code in codes) {
        debugPrint('[QR] rawValue: ${code.rawValue}');
      }

      String? value;
      for (final code in codes) {
        final raw = code.rawValue?.trim();
        if (raw != null && raw.isNotEmpty) {
          value = raw;
          break;
        }
      }

      if (value == null || value.isEmpty) {
        if (!mounted) return;
        setState(() => _isPickingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không tìm thấy mã QR hợp lệ trong ảnh đã chọn'),
          ),
        );
        return;
      }

      final tableId = parseTableIdFromQr(value);
      debugPrint('[QR] parsed tableId: $tableId');

      if (!mounted) return;
      setState(() => _isPickingImage = false);
      await _finishWithResult(value);
    } catch (e, st) {
      debugPrint('[QR] analyze image error: $e');
      debugPrintStack(stackTrace: st);

      if (!mounted) return;
      setState(() => _isPickingImage = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể đọc mã QR từ ảnh: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final topInset = media.padding.top;
    final bottomInset = media.padding.bottom;

    final scanWidth = math.min(size.width * 0.78, 320.0);
    final scanHeight = math.min(scanWidth * 1.32, size.height * 0.43);

    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.43),
      width: scanWidth,
      height: scanHeight,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              fit: BoxFit.cover,
              onDetect: _handleDetect,
            ),

            IgnorePointer(
              child: CustomPaint(
                painter: _ScannerOverlayPainter(scanRect: scanRect),
              ),
            ),

            SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: 8,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        _GlassCircleButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Quét mã QR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _GlassCircleButton(
                          icon: _torchOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          onTap: _toggleTorch,
                          active: _torchOn,
                        ),
                      ],
                    ),
                  ),

                  Positioned(
                    top: math.max(72, topInset + 48),
                    left: 24,
                    right: 24,
                    child: const Column(
                      children: [
                        Text(
                          'Quét mã QR tại bàn để đặt món',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            height: 1.12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Positioned(
                    left: scanRect.left,
                    top: scanRect.top - media.padding.top,
                    width: scanRect.width,
                    height: scanRect.height,
                    child: IgnorePointer(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _lineCtrl,
                              builder: (context, _) {
                                final lineTop =
                                    20 +
                                    (scanRect.height - 40) * _lineCtrl.value;

                                return Stack(
                                  children: [
                                    Positioned(
                                      left: 18,
                                      right: 18,
                                      top: lineTop,
                                      child: Container(
                                        height: 3,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          gradient: const LinearGradient(
                                            colors: [
                                              Colors.transparent,
                                              AppColor.primary,
                                              AppColor.primary,
                                              Colors.transparent,
                                            ],
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: AppColor.primary,
                                              blurRadius: 14,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: math.max(bottomInset + 10, 16),
                    child: _BottomControlCard(
                      zoom: _zoom,
                      pickingImage: _isPickingImage,
                      onZoomChanged: _setZoom,
                      onPickImage: _pickQrFromGallery,
                    ),
                  ),
                  if (_isEnteringTable)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.45),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xE61A1A1A),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 12),
                              Text(
                                'Đang vào bàn...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (kDebugMode)
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 140,
                      child: ElevatedButton(
                        onPressed: _isEnteringTable ? null : _debugEnterTable,
                        child: const Text('Debug: nhập mã bàn'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomControlCard extends StatelessWidget {
  const _BottomControlCard({
    required this.zoom,
    required this.pickingImage,
    required this.onZoomChanged,
    required this.onPickImage,
  });

  final double zoom;
  final bool pickingImage;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xD9141414),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.14), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.remove_rounded, color: Colors.white70, size: 24),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white12,
                    trackHeight: 3.5,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 9,
                    ),
                  ),
                  child: Slider(
                    value: zoom,
                    min: 0,
                    max: 1,
                    onChanged: onZoomChanged,
                  ),
                ),
              ),
              const Icon(Icons.add_rounded, color: Colors.white70, size: 24),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: pickingImage ? null : onPickImage,
              icon: pickingImage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.photo_library_outlined),
              label: Text(
                pickingImage ? 'Đang đọc ảnh...' : 'Chọn ảnh QR từ thư viện',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.22)),
                backgroundColor: Colors.white.withOpacity(0.04),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? const Color(0x5539D2FF) : const Color(0xCC141414),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
          ),
          child: Icon(icon, color: Colors.white, size: 21),
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter({required this.scanRect});

  final Rect scanRect;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Path()..addRect(Offset.zero & size);
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(28)));

    final overlay = Path.combine(PathOperation.difference, background, hole);

    canvas.drawPath(overlay, Paint()..color = Colors.black.withOpacity(0.60));
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanRect != scanRect;
  }
}
