import 'package:customer/features/orders/data/models/checkout_models.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ResultPage extends StatelessWidget {
  const ResultPage({super.key, required this.args});

  final CheckoutResultArgs args;

  PlaceOrderResponse get result => args.result;
  PaymentGatewayReturn? get paymentReturn => args.paymentReturn;

  @override
  Widget build(BuildContext context) {
    final isOnline = result.requiresOnlinePayment;
    final paymentSuccess = paymentReturn?.isSuccess == true;
    final paymentFailed = paymentReturn?.isFailed == true;

    final title = !isOnline
        ? 'Đặt đơn thành công'
        : paymentSuccess
        ? 'Thanh toán thành công'
        : paymentFailed
        ? 'Thanh toán thất bại'
        : 'Tạo đơn thành công';

    final subtitle = !isOnline
        ? 'Đơn hàng của bạn đã được tạo thành công.'
        : paymentSuccess
        ? 'Đơn hàng đã được thanh toán thành công và hệ thống sẽ tiếp tục xử lý.'
        : paymentFailed
        ? 'Thanh toán chưa thành công. Bạn có thể vào chi tiết đơn hàng để kiểm tra lại.'
        : 'Đơn hàng đã được tạo. Bạn cần hoàn tất thanh toán online để hệ thống tiếp tục xử lý.';

    final iconColor = paymentFailed
        ? const Color(0xFFFF4D4F)
        : const Color(0xFF28C76F);

    final iconBg = paymentFailed
        ? const Color(0x14FF4D4F)
        : const Color(0x1428C76F);

    final paymentText = _buildPaymentText(
      isOnline: isOnline,
      paymentMethod: result.payment?.method ?? 'cash',
      paymentSuccess: paymentSuccess,
      paymentFailed: paymentFailed,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Kết quả đặt đơn',
          style: TextStyle(
            color: Color(0xFF222222),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  paymentFailed ? Icons.cancel_rounded : Icons.check_circle,
                  size: 64,
                  color: iconColor,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF222222),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEAEAEA)),
                ),
                child: Column(
                  children: [
                    _InfoRow(label: 'Mã đơn hàng', value: result.orderNumber),
                    const SizedBox(height: 10),
                    _InfoRow(
                      label: 'Trạng thái đơn',
                      value: _orderStatusLabel(
                        result.status,
                        isDineIn: result.dineIn != null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      label: 'Tổng thanh toán',
                      value: _money(result.pricing.totalAmount),
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(label: 'Thanh toán', value: paymentText),
                    if (paymentReturn?.code != null &&
                        paymentReturn!.code!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _InfoRow(
                        label: 'Mã cổng thanh toán',
                        value: paymentReturn!.code!,
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    context.go('/');
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFEE4D2D)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Về trang chủ',
                    style: TextStyle(
                      color: Color(0xFFEE4D2D),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    context.go('/orders/${result.orderId}');
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEE4D2D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Xem đơn hàng',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF777777)),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF222222),
            ),
          ),
        ),
      ],
    );
  }
}

String _money(num v) {
  final s = v.toStringAsFixed(0);
  final out = s.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '$outđ';
}

String _orderStatusLabel(String raw, {required bool isDineIn}) {
  switch (raw) {
    case 'pending':
      return 'Chờ xác nhận';
    case 'confirmed':
      return 'Đã xác nhận';
    case 'preparing':
      return 'Đang chuẩn bị';
    case 'ready_for_pickup':
      return isDineIn ? 'Sẵn sàng phục vụ' : 'Sẵn sàng lấy hàng';
    case 'driver_assigned':
      return 'Đã có tài xế';
    case 'driver_arrived':
      return 'Tài xế đã tới quán';
    case 'picked_up':
      return 'Tài xế đã lấy hàng';
    case 'delivering':
      return 'Đang giao hàng';
    case 'delivered':
      return 'Đã giao hàng';
    case 'completed':
      return 'Hoàn thành';
    case 'cancelled':
      return 'Đã huỷ';
    case 'served':
      return 'Đã phục vụ';
    default:
      return raw;
  }
}

String _paymentMethodLabel(String raw) {
  switch (raw) {
    case 'cash':
      return 'Tiền mặt';
    case 'vnpay':
      return 'VNPay';
    case 'momo':
      return 'MoMo';
    case 'zalopay':
      return 'ZaloPay';
    case 'online':
      return 'Thanh toán online';
    default:
      return raw;
  }
}

String _buildPaymentText({
  required bool isOnline,
  required String paymentMethod,
  required bool paymentSuccess,
  required bool paymentFailed,
}) {
  final label = _paymentMethodLabel(paymentMethod);

  if (!isOnline) return label;
  if (paymentSuccess) return 'Đã thanh toán qua $label';
  if (paymentFailed) return 'Thanh toán thất bại';
  return 'Chờ thanh toán qua $label';
}
