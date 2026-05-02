import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessMetrics {
  final int totalMembers;
  final int activeMembers;
  final int newMembersThisMonth;
  final double monthlyRevenue;
  final int checkInsToday;
  final double averageGymOccupancy;
  final int totalGyms;

  BusinessMetrics({
    required this.totalMembers,
    required this.activeMembers,
    required this.newMembersThisMonth,
    required this.monthlyRevenue,
    required this.checkInsToday,
    required this.averageGymOccupancy,
    required this.totalGyms,
  });

  factory BusinessMetrics.fromJson(Map<String, dynamic> json) {
    return BusinessMetrics(
      totalMembers: json['total_members'] ?? 0,
      activeMembers: json['active_members'] ?? 0,
      newMembersThisMonth: json['new_members_this_month'] ?? 0,
      monthlyRevenue: (json['monthly_revenue'] ?? 0.0).toDouble(),
      checkInsToday: json['check_ins_today'] ?? 0,
      averageGymOccupancy: (json['average_gym_occupancy'] ?? 0.0).toDouble(),
      totalGyms: json['total_gyms'] ?? 0,
    );
  }
}

class RevenueData {
  final DateTime date;
  final double amount;
  final String source;

  RevenueData({required this.date, required this.amount, required this.source});

  factory RevenueData.fromJson(Map<String, dynamic> json) {
    return RevenueData(
      date: DateTime.parse(json['date']),
      amount: (json['amount'] ?? 0.0).toDouble(),
      source: json['source'] ?? '',
    );
  }
}

class MembershipTrend {
  final DateTime date;
  final int newMemberships;
  final int canceledMemberships;
  final int netChange;

  MembershipTrend({
    required this.date,
    required this.newMemberships,
    required this.canceledMemberships,
    required this.netChange,
  });

  factory MembershipTrend.fromJson(Map<String, dynamic> json) {
    return MembershipTrend(
      date: DateTime.parse(json['date']),
      newMemberships: json['new_memberships'] ?? 0,
      canceledMemberships: json['canceled_memberships'] ?? 0,
      netChange: json['net_change'] ?? 0,
    );
  }
}

class GymOccupancy {
  final String gymName;
  final int currentOccupancy;
  final int maxCapacity;
  final double occupancyPercentage;
  final List<Map<String, dynamic>> hourlyData;

  GymOccupancy({
    required this.gymName,
    required this.currentOccupancy,
    required this.maxCapacity,
    required this.occupancyPercentage,
    required this.hourlyData,
  });

  factory GymOccupancy.fromJson(Map<String, dynamic> json) {
    return GymOccupancy(
      gymName: json['gym_name'] ?? '',
      currentOccupancy: json['current_occupancy'] ?? 0,
      maxCapacity: json['max_capacity'] ?? 0,
      occupancyPercentage: (json['occupancy_percentage'] ?? 0.0).toDouble(),
      hourlyData: List<Map<String, dynamic>>.from(json['hourly_data'] ?? []),
    );
  }
}

class AnalyticsService {
  static final SupabaseClient _client = Supabase.instance.client;

  // Get overall business metrics
  static Future<BusinessMetrics> getBusinessMetrics() async {
    try {
      final response = await _client.rpc('get_business_metrics');
      return BusinessMetrics.fromJson(response ?? {});
    } catch (error) {
      print('Error fetching business metrics: $error');
      return BusinessMetrics(
        totalMembers: 0,
        activeMembers: 0,
        newMembersThisMonth: 0,
        monthlyRevenue: 0.0,
        checkInsToday: 0,
        averageGymOccupancy: 0.0,
        totalGyms: 0,
      );
    }
  }

  // Get revenue trends over time
  static Future<List<RevenueData>> getRevenueTrends({
    required DateTime startDate,
    required DateTime endDate,
    String groupBy = 'day', // 'day', 'week', 'month'
  }) async {
    try {
      final response = await _client.rpc(
        'get_revenue_trends',
        params: {
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
          'group_by': groupBy,
        },
      );

      if (response == null) return [];

      return (response as List)
          .map((item) => RevenueData.fromJson(item))
          .toList();
    } catch (error) {
      print('Error fetching revenue trends: $error');
      return [];
    }
  }

  // Get membership trends
  static Future<List<MembershipTrend>> getMembershipTrends({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _client.rpc(
        'get_membership_trends',
        params: {
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
        },
      );

      if (response == null) return [];

      return (response as List)
          .map((item) => MembershipTrend.fromJson(item))
          .toList();
    } catch (error) {
      print('Error fetching membership trends: $error');
      return [];
    }
  }

  // Get gym occupancy data
  static Future<List<GymOccupancy>> getGymOccupancy() async {
    try {
      final response = await _client.rpc('get_gym_occupancy');

      if (response == null) return [];

      return (response as List)
          .map((item) => GymOccupancy.fromJson(item))
          .toList();
    } catch (error) {
      print('Error fetching gym occupancy: $error');
      return [];
    }
  }

  // Get top performing gyms by revenue
  static Future<List<Map<String, dynamic>>> getTopPerformingGyms({
    int limit = 5,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final params = <String, dynamic>{'limit_count': limit};
      if (startDate != null) params['start_date'] = startDate.toIso8601String();
      if (endDate != null) params['end_date'] = endDate.toIso8601String();

      final response = await _client.rpc(
        'get_top_performing_gyms',
        params: params,
      );
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (error) {
      print('Error fetching top performing gyms: $error');
      return [];
    }
  }

  // Get member retention analytics
  static Future<Map<String, dynamic>> getMemberRetention() async {
    try {
      final response = await _client.rpc('get_member_retention');
      return Map<String, dynamic>.from(response ?? {});
    } catch (error) {
      print('Error fetching member retention: $error');
      return {};
    }
  }

  // Get check-in patterns (hourly distribution)
  static Future<List<Map<String, dynamic>>> getCheckinPatterns({
    DateTime? date,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (date != null) params['target_date'] = date.toIso8601String();

      final response = await _client.rpc(
        'get_checkin_patterns',
        params: params,
      );
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (error) {
      print('Error fetching checkin patterns: $error');
      return [];
    }
  }

  // Get membership plan performance
  static Future<List<Map<String, dynamic>>>
  getMembershipPlanPerformance() async {
    try {
      final response = await _client.rpc('get_membership_plan_performance');
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (error) {
      print('Error fetching membership plan performance: $error');
      return [];
    }
  }

  // Get payment method analytics
  static Future<Map<String, dynamic>> getPaymentMethodAnalytics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (startDate != null) params['start_date'] = startDate.toIso8601String();
      if (endDate != null) params['end_date'] = endDate.toIso8601String();

      final response = await _client.rpc(
        'get_payment_method_analytics',
        params: params,
      );
      return Map<String, dynamic>.from(response ?? {});
    } catch (error) {
      print('Error fetching payment method analytics: $error');
      return {};
    }
  }

  // Track custom events (for app usage analytics)
  static Future<void> trackEvent({
    required String eventName,
    required String userId,
    Map<String, dynamic>? properties,
  }) async {
    try {
      await _client.from('analytics_events').insert({
        'event_name': eventName,
        'user_id': userId,
        'properties': properties ?? {},
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (error) {
      print('Error tracking event: $error');
    }
  }
}
