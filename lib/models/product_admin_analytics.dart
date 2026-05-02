class ProductDashboardKpis {
  final int totalProducts;
  final int activeProducts;
  final int inactiveProducts;
  final int totalStockUnits;
  final int lowStockProducts;
  final int outOfStockProducts;
  final int stockValueCents;
  final int salesCount;
  final int itemsSold;
  final int salesRevenueCents;
  final int cashRevenueCents;
  final int cardRevenueCents;

  const ProductDashboardKpis({
    required this.totalProducts,
    required this.activeProducts,
    required this.inactiveProducts,
    required this.totalStockUnits,
    required this.lowStockProducts,
    required this.outOfStockProducts,
    required this.stockValueCents,
    required this.salesCount,
    required this.itemsSold,
    required this.salesRevenueCents,
    required this.cashRevenueCents,
    required this.cardRevenueCents,
  });

  factory ProductDashboardKpis.empty() {
    return const ProductDashboardKpis(
      totalProducts: 0,
      activeProducts: 0,
      inactiveProducts: 0,
      totalStockUnits: 0,
      lowStockProducts: 0,
      outOfStockProducts: 0,
      stockValueCents: 0,
      salesCount: 0,
      itemsSold: 0,
      salesRevenueCents: 0,
      cashRevenueCents: 0,
      cardRevenueCents: 0,
    );
  }

  factory ProductDashboardKpis.fromJson(Map<String, dynamic> json) {
    return ProductDashboardKpis(
      totalProducts: _asInt(json['total_products']),
      activeProducts: _asInt(json['active_products']),
      inactiveProducts: _asInt(json['inactive_products']),
      totalStockUnits: _asInt(json['total_stock_units']),
      lowStockProducts: _asInt(json['low_stock_products']),
      outOfStockProducts: _asInt(json['out_of_stock_products']),
      stockValueCents: _asInt(json['stock_value_cents']),
      salesCount: _asInt(json['sales_count']),
      itemsSold: _asInt(json['items_sold']),
      salesRevenueCents: _asInt(json['sales_revenue_cents']),
      cashRevenueCents: _asInt(json['cash_revenue_cents']),
      cardRevenueCents: _asInt(json['card_revenue_cents']),
    );
  }
}

class ProductOverviewItem {
  final String productId;
  final String gymId;
  final String gymName;
  final String productName;
  final int priceCents;
  final String currency;
  final bool isActive;
  final String? barcode;
  final String? sku;
  final int stock;
  final int stockValueCents;
  final int totalCount;

  const ProductOverviewItem({
    required this.productId,
    required this.gymId,
    required this.gymName,
    required this.productName,
    required this.priceCents,
    required this.currency,
    required this.isActive,
    required this.barcode,
    required this.sku,
    required this.stock,
    required this.stockValueCents,
    required this.totalCount,
  });

  factory ProductOverviewItem.fromJson(Map<String, dynamic> json) {
    return ProductOverviewItem(
      productId: (json['product_id'] ?? '').toString(),
      gymId: (json['gym_id'] ?? '').toString(),
      gymName: (json['gym_name'] ?? '').toString(),
      productName: (json['product_name'] ?? '').toString(),
      priceCents: _asInt(json['price_cents']),
      currency: (json['currency'] ?? 'RON').toString(),
      isActive: json['is_active'] == true,
      barcode: json['barcode']?.toString(),
      sku: json['sku']?.toString(),
      stock: _asInt(json['stock']),
      stockValueCents: _asInt(json['stock_value_cents']),
      totalCount: _asInt(json['total_count']),
    );
  }
}

class TopSellingProduct {
  final String productId;
  final String gymId;
  final String gymName;
  final String productName;
  final int quantitySold;
  final int totalRevenueCents;
  final int cashRevenueCents;
  final int cardRevenueCents;
  final int salesCount;
  final double avgUnitPriceCents;

  const TopSellingProduct({
    required this.productId,
    required this.gymId,
    required this.gymName,
    required this.productName,
    required this.quantitySold,
    required this.totalRevenueCents,
    required this.cashRevenueCents,
    required this.cardRevenueCents,
    required this.salesCount,
    required this.avgUnitPriceCents,
  });

  factory TopSellingProduct.fromJson(Map<String, dynamic> json) {
    return TopSellingProduct(
      productId: (json['product_id'] ?? '').toString(),
      gymId: (json['gym_id'] ?? '').toString(),
      gymName: (json['gym_name'] ?? '').toString(),
      productName: (json['product_name'] ?? '').toString(),
      quantitySold: _asInt(json['quantity_sold']),
      totalRevenueCents: _asInt(json['total_revenue_cents']),
      cashRevenueCents: _asInt(json['cash_revenue_cents']),
      cardRevenueCents: _asInt(json['card_revenue_cents']),
      salesCount: _asInt(json['sales_count']),
      avgUnitPriceCents: _asDouble(json['avg_unit_price_cents']),
    );
  }
}

class EmployeeProductSales {
  final String employeeId;
  final String employeeName;
  final String gymId;
  final String gymName;
  final int salesCount;
  final int itemsSold;
  final int revenueCents;
  final int cashRevenueCents;
  final int cardRevenueCents;
  final double avgSaleValueCents;

  const EmployeeProductSales({
    required this.employeeId,
    required this.employeeName,
    required this.gymId,
    required this.gymName,
    required this.salesCount,
    required this.itemsSold,
    required this.revenueCents,
    required this.cashRevenueCents,
    required this.cardRevenueCents,
    required this.avgSaleValueCents,
  });

  factory EmployeeProductSales.fromJson(Map<String, dynamic> json) {
    return EmployeeProductSales(
      employeeId: (json['employee_id'] ?? '').toString(),
      employeeName: (json['employee_name'] ?? '').toString(),
      gymId: (json['gym_id'] ?? '').toString(),
      gymName: (json['gym_name'] ?? '').toString(),
      salesCount: _asInt(json['sales_count']),
      itemsSold: _asInt(json['items_sold']),
      revenueCents: _asInt(json['revenue_cents']),
      cashRevenueCents: _asInt(json['cash_revenue_cents']),
      cardRevenueCents: _asInt(json['card_revenue_cents']),
      avgSaleValueCents: _asDouble(json['avg_sale_value_cents']),
    );
  }
}

class ProductSaleTransactionItem {
  final String productId;
  final String productName;
  final int quantity;
  final int unitPriceCents;
  final int lineTotalCents;

  const ProductSaleTransactionItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPriceCents,
    required this.lineTotalCents,
  });

  factory ProductSaleTransactionItem.fromJson(Map<String, dynamic> json) {
    return ProductSaleTransactionItem(
      productId: (json['product_id'] ?? '').toString(),
      productName: (json['product_name'] ?? '').toString(),
      quantity: _asInt(json['quantity']),
      unitPriceCents: _asInt(json['unit_price_cents']),
      lineTotalCents: _asInt(json['line_total_cents']),
    );
  }
}

class EmployeeProductSaleTransaction {
  final String saleId;
  final DateTime soldAt;
  final String paymentMethod;
  final int totalCents;
  final int totalItems;
  final String employeeId;
  final String employeeName;
  final String gymId;
  final String gymName;
  final List<ProductSaleTransactionItem> items;

  const EmployeeProductSaleTransaction({
    required this.saleId,
    required this.soldAt,
    required this.paymentMethod,
    required this.totalCents,
    required this.totalItems,
    required this.employeeId,
    required this.employeeName,
    required this.gymId,
    required this.gymName,
    required this.items,
  });

  factory EmployeeProductSaleTransaction.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final itemsList = <ProductSaleTransactionItem>[];

    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          itemsList.add(ProductSaleTransactionItem.fromJson(item));
        } else if (item is Map) {
          itemsList.add(
            ProductSaleTransactionItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }

    final soldAtRaw = json['sold_at']?.toString();
    return EmployeeProductSaleTransaction(
      saleId: (json['sale_id'] ?? '').toString(),
      soldAt: soldAtRaw != null
          ? DateTime.tryParse(soldAtRaw)?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      paymentMethod: (json['payment_method'] ?? '').toString(),
      totalCents: _asInt(json['total_cents']),
      totalItems: _asInt(json['total_items']),
      employeeId: (json['employee_id'] ?? '').toString(),
      employeeName: (json['employee_name'] ?? '').toString(),
      gymId: (json['gym_id'] ?? '').toString(),
      gymName: (json['gym_name'] ?? '').toString(),
      items: itemsList,
    );
  }
}

class ProductStockMovement {
  final String movementId;
  final String gymId;
  final String gymName;
  final String productId;
  final String productName;
  final int deltaQuantity;
  final String reason;
  final int stockBefore;
  final int stockAfter;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;
  final String? verifiedAgainstUserId;
  final String? verifiedAgainstUserName;
  final int? countedStock;
  final String? notes;
  final int totalCount;

  const ProductStockMovement({
    required this.movementId,
    required this.gymId,
    required this.gymName,
    required this.productId,
    required this.productName,
    required this.deltaQuantity,
    required this.reason,
    required this.stockBefore,
    required this.stockAfter,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
    required this.verifiedAgainstUserId,
    required this.verifiedAgainstUserName,
    required this.countedStock,
    required this.notes,
    required this.totalCount,
  });

  factory ProductStockMovement.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at']?.toString();
    return ProductStockMovement(
      movementId: (json['movement_id'] ?? '').toString(),
      gymId: (json['gym_id'] ?? '').toString(),
      gymName: (json['gym_name'] ?? '').toString(),
      productId: (json['product_id'] ?? '').toString(),
      productName: (json['product_name'] ?? '').toString(),
      deltaQuantity: _asInt(json['delta_quantity']),
      reason: (json['reason'] ?? '').toString(),
      stockBefore: _asInt(json['stock_before']),
      stockAfter: _asInt(json['stock_after']),
      createdAt: createdAtRaw != null
          ? DateTime.tryParse(createdAtRaw)?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      createdBy: (json['created_by'] ?? '').toString(),
      createdByName: (json['created_by_name'] ?? '').toString(),
      verifiedAgainstUserId: json['verified_against_user_id']?.toString(),
      verifiedAgainstUserName: json['verified_against_user_name']?.toString(),
      countedStock: json['counted_stock'] == null
          ? null
          : _asInt(json['counted_stock']),
      notes: json['notes']?.toString(),
      totalCount: _asInt(json['total_count']),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}
