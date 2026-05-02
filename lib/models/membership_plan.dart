class MembershipPlan {
  final String id;
  final String name;
  final String tier;
  final int monthlyPriceCents;
  final int yearlyPriceCents;
  final String currency;
  final bool isFamilyPlan;
  final int? maxFamilyMembers;
  final bool isActive;
  final DateTime createdAt;

  MembershipPlan({
    required this.id,
    required this.name,
    required this.tier,
    required this.monthlyPriceCents,
    required this.yearlyPriceCents,
    required this.currency,
    required this.isFamilyPlan,
    this.maxFamilyMembers,
    required this.isActive,
    required this.createdAt,
  });

  factory MembershipPlan.fromJson(Map<String, dynamic> json) {
    return MembershipPlan(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Plan Necunoscut',
      tier: json['tier'] as String? ?? 'basic',
      monthlyPriceCents: json['monthly_price_cents'] as int? ?? 0,
      yearlyPriceCents: json['yearly_price_cents'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'RON',
      isFamilyPlan: json['is_family_plan'] as bool? ?? false,
      maxFamilyMembers: json['max_family_members'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  double get monthlyPriceInCurrency => monthlyPriceCents / 100.0;
  double get yearlyPriceInCurrency => yearlyPriceCents / 100.0;
}
