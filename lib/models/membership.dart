import 'gym.dart';
import 'membership_plan.dart';

class Membership {
  final String id;
  final String userId;
  final String planId;
  final String soldAtGymId;
  final DateTime startDate;
  final DateTime? effectiveStartDate;
  final DateTime endDate;
  final int durationMonths;
  final int pricePaidCents;
  final String currency;
  final String paymentMethod;
  final String membershipType;
  final bool isActive;
  final bool isStudent;
  final String? cancelReason;
  final DateTime? canceledAt;
  final DateTime createdAt;
  final bool isFrozen;
  final DateTime? frozenAt;
  final String? frozenByUserId;
  final int? daysLeftWhenFrozen;
  final int? daysLeft; // From database, can be negative if expired

  // Relations
  final MembershipPlan? plan;
  final Gym? gym;

  Membership({
    required this.id,
    required this.userId,
    required this.planId,
    required this.soldAtGymId,
    required this.startDate,
    this.effectiveStartDate,
    required this.endDate,
    required this.durationMonths,
    required this.pricePaidCents,
    required this.currency,
    required this.paymentMethod,
    required this.membershipType,
    required this.isActive,
    required this.isStudent,
    this.cancelReason,
    this.canceledAt,
    required this.createdAt,
    required this.isFrozen,
    this.frozenAt,
    this.frozenByUserId,
    this.daysLeftWhenFrozen,
    this.daysLeft,
    this.plan,
    this.gym,
  });

  factory Membership.fromJson(Map<String, dynamic> json) {
    return Membership(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      planId: json['plan_id'] as String? ?? '',
      soldAtGymId: json['sold_at_gym_id'] as String? ?? '',
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : DateTime.now(),
      effectiveStartDate: json['effective_start_date'] != null
          ? DateTime.parse(json['effective_start_date'] as String)
          : null,
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : DateTime.now().add(const Duration(days: 30)),
      durationMonths: json['duration_months'] as int? ?? 1,
      pricePaidCents: json['price_paid_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'RON',
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      membershipType: json['membership_type'] as String? ?? 'monthly',
      isActive: json['is_active'] as bool? ?? false,
      isStudent: json['is_student'] as bool? ?? false,
      cancelReason: json['cancel_reason'] as String?,
      canceledAt: json['canceled_at'] != null
          ? DateTime.parse(json['canceled_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      isFrozen: json['is_frozen'] as bool? ?? false,
      frozenAt: json['frozen_at'] != null
          ? DateTime.parse(json['frozen_at'] as String)
          : null,
      frozenByUserId: json['frozen_by_user_id'] as String?,
      daysLeftWhenFrozen: json['days_left_when_frozen'] as int?,
      daysLeft: json['days_left'] as int?,
      plan: json['membership_plans'] != null
          ? MembershipPlan.fromJson(
              json['membership_plans'] as Map<String, dynamic>,
            )
          : null,
      gym: json['gyms'] != null
          ? Gym.fromJson(json['gyms'] as Map<String, dynamic>)
          : null,
    );
  }

  factory Membership.fromOptimizedJson(Map<String, dynamic> json) {
    return Membership(
      id: json['membership_id'] as String? ?? '',
      userId: '', // Not returned by this RPC
      planId: json['membership_plan_id'] as String? ?? '',
      soldAtGymId: json['sold_at_gym_id'] as String? ?? '',
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : DateTime.now(),
      effectiveStartDate: json['effective_start_date'] != null
          ? DateTime.parse(json['effective_start_date'] as String)
          : null,
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : DateTime.now().add(const Duration(days: 30)),
      durationMonths: json['duration_months'] as int? ?? 1,
      pricePaidCents: json['price_paid_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'RON',
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      membershipType: json['membership_type'] as String? ?? 'monthly',
      isActive: json['is_active'] as bool? ?? false,
      isStudent: json['is_student'] as bool? ?? false,
      cancelReason: json['cancel_reason'] as String?,
      canceledAt: json['canceled_at'] != null
          ? DateTime.parse(json['canceled_at'] as String)
          : null,
      createdAt: DateTime.now(),
      isFrozen: json['is_frozen'] as bool? ?? false,
      frozenAt: json['frozen_at'] != null
          ? DateTime.parse(json['frozen_at'] as String)
          : null,
      frozenByUserId: null,
      daysLeftWhenFrozen: json['days_left_when_frozen'] as int?,
      daysLeft: json['days_left'] as int?,
      plan: MembershipPlan(
        id: json['membership_plan_id'] as String? ?? '',
        name: json['plan_name'] as String? ?? 'Plan Necunoscut',
        tier: json['tier'] as String? ?? 'basic',
        monthlyPriceCents: 0,
        yearlyPriceCents: 0,
        currency: 'RON',
        isActive: true,
        isFamilyPlan: json['is_family_plan'] as bool? ?? false,
        createdAt: DateTime.now(),
      ),
      gym: json['sold_at_gym_name'] != null
          ? Gym(
              id: json['sold_at_gym_id'] as String? ?? '',
              name: json['sold_at_gym_name'] as String? ?? '',
              isActive: true,
              createdAt: DateTime.now(),
            )
          : null,
    );
  }

  double get priceInCurrency => pricePaidCents / 100.0;

  // Use daysLeft from DB if available, otherwise calculate from endDate
  bool get isExpired =>
      daysLeft != null ? daysLeft! < 0 : DateTime.now().isAfter(endDate);

  bool get isCanceled => canceledAt != null;

  // Getter alias for compatibility
  String get gymId => soldAtGymId;

  // Use effective_start_date if available, otherwise fall back to start_date
  DateTime get actualStartDate => effectiveStartDate ?? startDate;

  int get daysUntilExpiry {
    // Use daysLeft from database if available
    if (daysLeft != null) {
      return daysLeft! >= 0 ? daysLeft! : 0;
    }
    // Fallback to calculation
    final now = DateTime.now();
    if (now.isAfter(endDate)) return 0;
    return endDate.difference(now).inDays;
  }

  String get statusText {
    if (isCanceled) return 'Anulat';
    if (isExpired) return 'Expirat';
    if (isFrozen) return 'Înghețat';
    final days = daysLeft ?? daysUntilExpiry;
    if (days <= 7 && days >= 0) return 'Expiră în $days zile';
    return 'Activ';
  }
}
