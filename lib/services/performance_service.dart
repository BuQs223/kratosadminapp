import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseMetrics {
  final String tableName;
  final int totalScans;
  final int tuplesRead;
  final int tuplesFetched;
  final double indexHitRatio;
  final int totalRows;

  DatabaseMetrics({
    required this.tableName,
    required this.totalScans,
    required this.tuplesRead,
    required this.tuplesFetched,
    required this.indexHitRatio,
    required this.totalRows,
  });

  factory DatabaseMetrics.fromJson(Map<String, dynamic> json) {
    return DatabaseMetrics(
      tableName: json['table_name'] ?? '',
      totalScans: json['total_scans'] ?? 0,
      tuplesRead: json['tuples_read'] ?? 0,
      tuplesFetched: json['tuples_fetched'] ?? 0,
      indexHitRatio: (json['index_hit_ratio'] ?? 0.0).toDouble(),
      totalRows: json['total_rows'] ?? 0,
    );
  }
}

class QueryPerformance {
  final String query;
  final double avgTime;
  final int calls;
  final double totalTime;
  final double minTime;
  final double maxTime;

  QueryPerformance({
    required this.query,
    required this.avgTime,
    required this.calls,
    required this.totalTime,
    required this.minTime,
    required this.maxTime,
  });

  factory QueryPerformance.fromJson(Map<String, dynamic> json) {
    return QueryPerformance(
      query: json['query'] ?? '',
      avgTime: (json['mean_exec_time'] ?? 0.0).toDouble(),
      calls: json['calls'] ?? 0,
      totalTime: (json['total_exec_time'] ?? 0.0).toDouble(),
      minTime: (json['min_exec_time'] ?? 0.0).toDouble(),
      maxTime: (json['max_exec_time'] ?? 0.0).toDouble(),
    );
  }
}

class ConnectionMetrics {
  final int activeConnections;
  final int maxConnections;
  final int idleConnections;
  final DateTime timestamp;

  ConnectionMetrics({
    required this.activeConnections,
    required this.maxConnections,
    required this.idleConnections,
    required this.timestamp,
  });
}

class DatabasePerformanceService {
  static final SupabaseClient _client = Supabase.instance.client;

  // Get table-level performance metrics
  static Future<List<DatabaseMetrics>> getTableMetrics() async {
    try {
      final response = await _client.rpc('get_table_metrics');

      if (response == null) return [];

      return (response as List)
          .map((item) => DatabaseMetrics.fromJson(item))
          .toList();
    } catch (error) {
      print('Error fetching table metrics: $error');
      return [];
    }
  }

  // Get slowest running queries
  static Future<List<QueryPerformance>> getSlowestQueries({
    int limit = 10,
  }) async {
    try {
      final response = await _client.rpc(
        'get_slowest_queries',
        params: {'query_limit': limit},
      );

      if (response == null) return [];

      return (response as List)
          .map((item) => QueryPerformance.fromJson(item))
          .toList();
    } catch (error) {
      print('Error fetching slow queries: $error');
      return [];
    }
  }

  // Get database size metrics
  static Future<Map<String, dynamic>> getDatabaseSizeMetrics() async {
    try {
      final response = await _client.rpc('get_database_size_metrics');
      return response ?? {};
    } catch (error) {
      print('Error fetching database size metrics: $error');
      return {};
    }
  }

  // Get connection metrics
  static Future<ConnectionMetrics> getConnectionMetrics() async {
    try {
      final response = await _client.rpc('get_connection_metrics');

      return ConnectionMetrics(
        activeConnections: response?['active_connections'] ?? 0,
        maxConnections: response?['max_connections'] ?? 0,
        idleConnections: response?['idle_connections'] ?? 0,
        timestamp: DateTime.now(),
      );
    } catch (error) {
      print('Error fetching connection metrics: $error');
      return ConnectionMetrics(
        activeConnections: 0,
        maxConnections: 0,
        idleConnections: 0,
        timestamp: DateTime.now(),
      );
    }
  }

  // Get index usage statistics
  static Future<List<Map<String, dynamic>>> getIndexUsageStats() async {
    try {
      final response = await _client.rpc('get_index_usage_stats');
      return response != null ? List<Map<String, dynamic>>.from(response) : [];
    } catch (error) {
      print('Error fetching index usage stats: $error');
      return [];
    }
  }

  // Get cache hit ratios
  static Future<Map<String, double>> getCacheHitRatios() async {
    try {
      final response = await _client.rpc('get_cache_hit_ratios');

      return {
        'buffer_hit_ratio': (response?['buffer_hit_ratio'] ?? 0.0).toDouble(),
        'index_hit_ratio': (response?['index_hit_ratio'] ?? 0.0).toDouble(),
      };
    } catch (error) {
      print('Error fetching cache hit ratios: $error');
      return {'buffer_hit_ratio': 0.0, 'index_hit_ratio': 0.0};
    }
  }

  // Get recent performance trends
  static Future<List<Map<String, dynamic>>> getPerformanceTrends({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _client.rpc(
        'get_performance_trends',
        params: {
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
        },
      );

      return response != null ? List<Map<String, dynamic>>.from(response) : [];
    } catch (error) {
      print('Error fetching performance trends: $error');
      return [];
    }
  }
}
