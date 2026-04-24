enum MyOrderTab { active, reviews, history, drafts }

class MyOrdersTabCounts {
  final int activeCount;
  final int reviewCount;
  final int historyCount;
  final int draftCount;

  const MyOrdersTabCounts({
    required this.activeCount,
    required this.reviewCount,
    required this.historyCount,
    required this.draftCount,
  });

  const MyOrdersTabCounts.zero()
    : activeCount = 0,
      reviewCount = 0,
      historyCount = 0,
      draftCount = 0;

  factory MyOrdersTabCounts.fromJson(Map<String, dynamic> j) {
    return MyOrdersTabCounts(
      activeCount: (j['active_count'] as num?)?.toInt() ?? 0,
      reviewCount: (j['review_count'] as num?)?.toInt() ?? 0,
      historyCount: (j['history_count'] as num?)?.toInt() ?? 0,
      draftCount: (j['draft_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class MyDraftCartItem {
  final String id;
  final MyOrderMerchant merchant;
  final String? previewImageUrl;
  final int itemCount;
  final int totalAmount;
  final List<String> itemsPreview;
  final DateTime? updatedAt;
  final String serviceLabel;

  const MyDraftCartItem({
    required this.id,
    required this.merchant,
    required this.previewImageUrl,
    required this.itemCount,
    required this.totalAmount,
    required this.itemsPreview,
    required this.updatedAt,
    required this.serviceLabel,
  });

  factory MyDraftCartItem.fromJson(Map<String, dynamic> j) {
    return MyDraftCartItem(
      id: (j['id'] ?? '').toString(),
      merchant: MyOrderMerchant.fromJson(
        (j['merchant'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      previewImageUrl: j['preview_image_url']?.toString(),
      itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
      totalAmount: (j['total_amount'] as num?)?.toInt() ?? 0,
      itemsPreview: ((j['items_preview'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()),
      serviceLabel: (j['service_label'] ?? 'Đồ ăn').toString(),
    );
  }
}

class MyDraftCartListResponse {
  final List<MyDraftCartItem> items;
  final String? nextCursor;
  final bool hasMore;

  const MyDraftCartListResponse({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  factory MyDraftCartListResponse.fromJson(Map<String, dynamic> j) {
    return MyDraftCartListResponse(
      items: ((j['items'] as List?) ?? const [])
          .map(
            (e) => MyDraftCartItem.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
      nextCursor: j['next_cursor']?.toString(),
      hasMore: j['has_more'] == true,
    );
  }
}

class MyOrderMerchant {
  final String id;
  final String name;
  final String? logoUrl;
  final String address;

  const MyOrderMerchant({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.address,
  });

  factory MyOrderMerchant.fromJson(Map<String, dynamic> j) {
    return MyOrderMerchant(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      logoUrl: j['logo_url']?.toString(),
      address: (j['address'] ?? '').toString(),
    );
  }
}

class MyOrderListItem {
  final String id;
  final String orderNumber;
  final String status;
  final String statusLabel;
  final String displayStatus;
  final String displayStatusLabel;
  final String orderType;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int totalAmount;
  final int itemCount;
  final DateTime? etaAt;
  final int? etaMin;
  final MyOrderMerchant merchant;
  final List<String> itemsPreview;
  final bool canCancel;

  const MyOrderListItem({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.statusLabel,
    required this.displayStatus,
    required this.displayStatusLabel,
    required this.orderType,
    required this.createdAt,
    required this.updatedAt,
    required this.totalAmount,
    required this.itemCount,
    required this.etaAt,
    required this.etaMin,
    required this.merchant,
    required this.itemsPreview,
    required this.canCancel,
  });

  factory MyOrderListItem.fromJson(Map<String, dynamic> j) {
    return MyOrderListItem(
      id: (j['id'] ?? '').toString(),
      orderNumber: (j['order_number'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      statusLabel: (j['status_label'] ?? '').toString(),
      displayStatus: (j['display_status'] ?? j['status'] ?? '').toString(),
      displayStatusLabel: (j['display_status_label'] ?? j['status_label'] ?? '')
          .toString(),
      orderType: (j['order_type'] ?? 'delivery').toString(),
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()),
      totalAmount: (j['total_amount'] as num?)?.toInt() ?? 0,
      itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
      etaAt: DateTime.tryParse((j['eta_at'] ?? '').toString()),
      etaMin: (j['eta_min'] as num?)?.toInt(),
      merchant: MyOrderMerchant.fromJson(
        (j['merchant'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      itemsPreview: ((j['items_preview'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      canCancel: ((j['actions'] as Map?)?['can_cancel'] == true),
    );
  }
}

class MyOrderListResponse {
  final List<MyOrderListItem> items;
  final String? nextCursor;
  final bool hasMore;

  const MyOrderListResponse({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  factory MyOrderListResponse.fromJson(Map<String, dynamic> j) {
    return MyOrderListResponse(
      items: ((j['items'] as List?) ?? const [])
          .map(
            (e) => MyOrderListItem.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
      nextCursor: j['next_cursor']?.toString(),
      hasMore: j['has_more'] == true,
    );
  }
}

class MyReviewProduct {
  final String id;
  final String name;
  final String? imageUrl;

  const MyReviewProduct({
    required this.id,
    required this.name,
    required this.imageUrl,
  });

  factory MyReviewProduct.fromJson(Map<String, dynamic> j) {
    return MyReviewProduct(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      imageUrl: j['image_url']?.toString(),
    );
  }
}

class MyMerchantReply {
  final String content;
  final bool isEdited;
  final DateTime? repliedAt;

  const MyMerchantReply({
    required this.content,
    required this.isEdited,
    required this.repliedAt,
  });

  factory MyMerchantReply.fromJson(Map<String, dynamic> j) {
    return MyMerchantReply(
      content: (j['content'] ?? '').toString(),
      isEdited: j['is_edited'] == true,
      repliedAt: DateTime.tryParse((j['replied_at'] ?? '').toString()),
    );
  }
}

class MyReviewListItem {
  final String id;
  final String entityType; // merchant | product
  final int rating;
  final String comment;
  final List<Map<String, dynamic>> images;
  final String? videoUrl;
  final DateTime? createdAt;
  final MyOrderMerchant? merchant;
  final MyReviewProduct? product;
  final MyMerchantReply? merchantReply;

  const MyReviewListItem({
    required this.id,
    required this.entityType,
    required this.rating,
    required this.comment,
    required this.images,
    required this.videoUrl,
    required this.createdAt,
    required this.merchant,
    required this.product,
    required this.merchantReply,
  });

  factory MyReviewListItem.fromJson(Map<String, dynamic> j) {
    return MyReviewListItem(
      id: (j['id'] ?? '').toString(),
      entityType: (j['entity_type'] ?? '').toString(),
      rating: (j['rating'] as num?)?.toInt() ?? 0,
      comment: (j['comment'] ?? '').toString(),
      images: ((j['images'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
      videoUrl: j['video_url']?.toString(),
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
      merchant: j['merchant'] is Map
          ? MyOrderMerchant.fromJson(
              (j['merchant'] as Map).cast<String, dynamic>(),
            )
          : null,
      product: j['product'] is Map
          ? MyReviewProduct.fromJson(
              (j['product'] as Map).cast<String, dynamic>(),
            )
          : null,
      merchantReply: j['merchant_reply'] is Map
          ? MyMerchantReply.fromJson(
              (j['merchant_reply'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }
}

class MyReviewListResponse {
  final List<MyReviewListItem> items;
  final String? nextCursor;
  final bool hasMore;

  const MyReviewListResponse({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  factory MyReviewListResponse.fromJson(Map<String, dynamic> j) {
    return MyReviewListResponse(
      items: ((j['items'] as List?) ?? const [])
          .map(
            (e) =>
                MyReviewListItem.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
      nextCursor: j['next_cursor']?.toString(),
      hasMore: j['has_more'] == true,
    );
  }
}
