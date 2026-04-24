import 'package:customer/features/orders/data/models/my_order_models.dart';

class CustomerOrderDriverInfo {
  final String id;
  final String fullName;
  final String phone;
  final String? avatarUrl;

  const CustomerOrderDriverInfo({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.avatarUrl,
  });

  factory CustomerOrderDriverInfo.fromJson(Map<String, dynamic> j) {
    return CustomerOrderDriverInfo(
      id: (j['id'] ?? '').toString(),
      fullName: (j['full_name'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      avatarUrl: j['avatar_url']?.toString(),
    );
  }
}

class CustomerOrderAddress {
  final String address;
  final String receiverName;
  final String receiverPhone;
  final String note;

  const CustomerOrderAddress({
    required this.address,
    required this.receiverName,
    required this.receiverPhone,
    required this.note,
  });

  factory CustomerOrderAddress.fromJson(Map<String, dynamic> j) {
    return CustomerOrderAddress(
      address: (j['address'] ?? '').toString(),
      receiverName: (j['receiver_name'] ?? '').toString(),
      receiverPhone: (j['receiver_phone'] ?? '').toString(),
      note: (j['note'] ?? '').toString(),
    );
  }
}

class CustomerOrderDiscounts {
  final int foodDiscount;
  final int deliveryDiscount;
  final int totalDiscount;

  const CustomerOrderDiscounts({
    required this.foodDiscount,
    required this.deliveryDiscount,
    required this.totalDiscount,
  });

  factory CustomerOrderDiscounts.fromJson(Map<String, dynamic> j) {
    return CustomerOrderDiscounts(
      foodDiscount: (j['food_discount'] as num?)?.toInt() ?? 0,
      deliveryDiscount: (j['delivery_discount'] as num?)?.toInt() ?? 0,
      totalDiscount: (j['total_discount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CustomerOrderItem {
  final String id;
  final String itemType;
  final String? productId;
  final String? toppingId;
  final String name;
  final String? image;
  final int quantity;
  final int unitPrice;
  final int itemTotal;
  final List<Map<String, dynamic>> selectedOptions;
  final List<Map<String, dynamic>> selectedToppings;

  const CustomerOrderItem({
    required this.id,
    required this.itemType,
    required this.productId,
    required this.toppingId,
    required this.name,
    required this.image,
    required this.quantity,
    required this.unitPrice,
    required this.itemTotal,
    required this.selectedOptions,
    required this.selectedToppings,
  });

  factory CustomerOrderItem.fromJson(Map<String, dynamic> j) {
    return CustomerOrderItem(
      id: (j['id'] ?? '').toString(),
      itemType: (j['item_type'] ?? '').toString(),
      productId: j['product_id']?.toString(),
      toppingId: j['topping_id']?.toString(),
      name: (j['name'] ?? '').toString(),
      image: j['image']?.toString(),
      quantity: (j['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (j['unit_price'] as num?)?.toInt() ?? 0,
      itemTotal: (j['item_total'] as num?)?.toInt() ?? 0,
      selectedOptions: ((j['selected_options'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
      selectedToppings: ((j['selected_toppings'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
    );
  }
}

class CustomerOrderStatusHistoryItem {
  final String status;
  final DateTime? changedAt;
  final String? note;

  const CustomerOrderStatusHistoryItem({
    required this.status,
    required this.changedAt,
    required this.note,
  });

  factory CustomerOrderStatusHistoryItem.fromJson(Map<String, dynamic> j) {
    return CustomerOrderStatusHistoryItem(
      status: (j['status'] ?? '').toString(),
      changedAt: DateTime.tryParse((j['changed_at'] ?? '').toString()),
      note: j['note']?.toString(),
    );
  }
}

class CustomerOrderActions {
  final bool canCancel;
  final bool canReviewMerchant;
  final bool canReviewDriver;

  const CustomerOrderActions({
    required this.canCancel,
    required this.canReviewMerchant,
    required this.canReviewDriver,
  });

  factory CustomerOrderActions.fromJson(Map<String, dynamic> j) {
    return CustomerOrderActions(
      canCancel: j['can_cancel'] == true,
      canReviewMerchant: j['can_review_merchant'] == true,
      canReviewDriver: j['can_review_driver'] == true,
    );
  }
}

class CustomerOrderReviewStatus {
  final bool merchantReviewed;
  final bool driverReviewed;

  const CustomerOrderReviewStatus({
    required this.merchantReviewed,
    required this.driverReviewed,
  });

  factory CustomerOrderReviewStatus.fromJson(Map<String, dynamic> j) {
    return CustomerOrderReviewStatus(
      merchantReviewed: j['merchant_reviewed'] == true,
      driverReviewed: j['driver_reviewed'] == true,
    );
  }
}

class CustomerOrderDetail {
  final String id;
  final String orderNumber;
  final String status;
  final String statusLabel;
  final String displayStatus;
  final String displayStatusLabel;
  final String orderType;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String paymentMethod;
  final String paymentStatus;
  final int subtotal;
  final int deliveryFee;
  final int totalAmount;
  final CustomerOrderDiscounts discounts;
  final MyOrderMerchant? merchant;
  final CustomerOrderDriverInfo? driver;
  final CustomerOrderAddress? deliveryAddress;
  final List<CustomerOrderItem> items;
  final List<CustomerOrderStatusHistoryItem> statusHistory;
  final CustomerOrderActions actions;
  final CustomerOrderReviewStatus reviewStatus;

  const CustomerOrderDetail({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.statusLabel,
    required this.displayStatus,
    required this.displayStatusLabel,
    required this.orderType,
    required this.createdAt,
    required this.updatedAt,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.subtotal,
    required this.deliveryFee,
    required this.totalAmount,
    required this.discounts,
    required this.merchant,
    required this.driver,
    required this.deliveryAddress,
    required this.items,
    required this.statusHistory,
    required this.actions,
    required this.reviewStatus,
  });

  factory CustomerOrderDetail.fromJson(Map<String, dynamic> j) {
    return CustomerOrderDetail(
      id: (j['id'] ?? '').toString(),
      orderNumber: (j['order_number'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      statusLabel: (j['status_label'] ?? '').toString(),
      displayStatus: (j['display_status'] ?? j['status'] ?? '').toString(),
      displayStatusLabel: (j['display_status_label'] ?? j['status_label'] ?? '')
          .toString(),
      orderType: (j['order_type'] ?? '').toString(),
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()),
      paymentMethod: (j['payment_method'] ?? '').toString(),
      paymentStatus: (j['payment_status'] ?? '').toString(),
      subtotal: (j['subtotal'] as num?)?.toInt() ?? 0,
      deliveryFee: (j['delivery_fee'] as num?)?.toInt() ?? 0,
      totalAmount: (j['total_amount'] as num?)?.toInt() ?? 0,
      discounts: CustomerOrderDiscounts.fromJson(
        (j['discounts'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      merchant: j['merchant'] is Map
          ? MyOrderMerchant.fromJson(
              (j['merchant'] as Map).cast<String, dynamic>(),
            )
          : null,
      driver: j['driver'] is Map
          ? CustomerOrderDriverInfo.fromJson(
              (j['driver'] as Map).cast<String, dynamic>(),
            )
          : null,
      deliveryAddress: j['delivery_address'] is Map
          ? CustomerOrderAddress.fromJson(
              (j['delivery_address'] as Map).cast<String, dynamic>(),
            )
          : null,
      items: ((j['items'] as List?) ?? const [])
          .map(
            (e) =>
                CustomerOrderItem.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
      statusHistory: ((j['status_history'] as List?) ?? const [])
          .map(
            (e) => CustomerOrderStatusHistoryItem.fromJson(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      actions: CustomerOrderActions.fromJson(
        (j['actions'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      reviewStatus: CustomerOrderReviewStatus.fromJson(
        (j['review_status'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
}
