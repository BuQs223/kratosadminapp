import '../models/product_admin_analytics.dart';
import 'supabase_service.dart';

class ProductAdminAnalyticsService {
  Future<List<Map<String, String>>> fetchGyms() async {
    final response = await SupabaseService.client
        .from('gyms')
        .select('id, name')
        .order('name');

    return (response as List)
        .map(
          (row) => {
            'id': (row['id'] ?? '').toString(),
            'name': (row['name'] ?? '').toString(),
          },
        )
        .toList();
  }

  Future<List<Map<String, String>>> fetchEmployees({String? gymId}) async {
    final response = await SupabaseService.client.rpc(
      'get_admin_product_employees',
      params: {'p_gym_id': gymId},
    );

    return (response as List)
        .map(
          (row) => {
            'id': (row['employee_id'] ?? '').toString(),
            'name': (row['employee_name'] ?? '').toString(),
            'gym_id': (row['gym_id'] ?? '').toString(),
            'gym_name': (row['gym_name'] ?? '').toString(),
          },
        )
        .toList();
  }

  Future<ProductDashboardKpis> fetchDashboardKpis({
    String? gymId,
    DateTime? dateStart,
    DateTime? dateEnd,
    int lowStockThreshold = 5,
  }) async {
    final response = await SupabaseService.client.rpc(
      'get_admin_product_dashboard_kpis',
      params: {
        'p_gym_id': gymId,
        'p_date_start': dateStart?.toIso8601String(),
        'p_date_end': dateEnd?.toIso8601String(),
        'p_low_stock_threshold': lowStockThreshold,
      },
    );

    final rows = response as List;
    if (rows.isEmpty) return ProductDashboardKpis.empty();
    return ProductDashboardKpis.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<List<ProductOverviewItem>> fetchProductsOverview({
    String? gymId,
    String? searchQuery,
    bool includeInactive = true,
    int? lowStockThreshold,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await SupabaseService.client.rpc(
      'get_admin_products_overview',
      params: {
        'p_gym_id': gymId,
        'p_search_query': searchQuery,
        'p_include_inactive': includeInactive,
        'p_low_stock_threshold': lowStockThreshold,
        'p_limit': limit,
        'p_offset': offset,
      },
    );

    return (response as List)
        .map((row) => ProductOverviewItem.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<TopSellingProduct>> fetchTopSellingProducts({
    String? gymId,
    DateTime? dateStart,
    DateTime? dateEnd,
    int limit = 15,
  }) async {
    final response = await SupabaseService.client.rpc(
      'get_admin_top_selling_products',
      params: {
        'p_gym_id': gymId,
        'p_date_start': dateStart?.toIso8601String(),
        'p_date_end': dateEnd?.toIso8601String(),
        'p_limit': limit,
      },
    );

    return (response as List)
        .map((row) => TopSellingProduct.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<EmployeeProductSales>> fetchEmployeeProductSales({
    String? gymId,
    String? employeeId,
    DateTime? dateStart,
    DateTime? dateEnd,
    int limit = 100,
  }) async {
    final response = await SupabaseService.client.rpc(
      'get_admin_employee_product_sales',
      params: {
        'p_gym_id': gymId,
        'p_employee_id': employeeId,
        'p_date_start': dateStart?.toIso8601String(),
        'p_date_end': dateEnd?.toIso8601String(),
        'p_limit': limit,
      },
    );

    return (response as List)
        .map(
          (row) => EmployeeProductSales.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }

  Future<List<EmployeeProductSaleTransaction>> fetchEmployeeSaleTransactions({
    String? gymId,
    String? employeeId,
    DateTime? dateStart,
    DateTime? dateEnd,
    int limit = 250,
  }) async {
    final response = await SupabaseService.client.rpc(
      'get_admin_employee_product_sale_transactions',
      params: {
        'p_gym_id': gymId,
        'p_employee_id': employeeId,
        'p_date_start': dateStart?.toIso8601String(),
        'p_date_end': dateEnd?.toIso8601String(),
        'p_limit': limit,
      },
    );

    return (response as List)
        .map(
          (row) => EmployeeProductSaleTransaction.fromJson(
            row as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<List<ProductStockMovement>> fetchStockMovements({
    String? gymId,
    String? productId,
    String? employeeId,
    String? reason,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? searchQuery,
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await SupabaseService.client.rpc(
      'get_admin_product_stock_movements',
      params: {
        'p_gym_id': gymId,
        'p_product_id': productId,
        'p_employee_id': employeeId,
        'p_reason': reason,
        'p_date_start': dateStart?.toIso8601String(),
        'p_date_end': dateEnd?.toIso8601String(),
        'p_search_query': searchQuery,
        'p_limit': limit,
        'p_offset': offset,
      },
    );

    return (response as List)
        .map(
          (row) => ProductStockMovement.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }
}
