import 'profile.dart';
import 'membership_plan.dart';
import 'gym.dart';

class RevenueLedger {
  final String id;
  final DateTime paidAt;
  final String? planId;
  final String? membershipId;
  final String? gymId;
  final int amountCents;
  final String currency;
  final String source;
  final String entryKind;
  final String paymentMethod;
  final String? notes;
  final String? recordedBy;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedBy;
  final DateTime createdAt;

  // Relations
  final Profile? recordedByProfile;
  final Profile? clientProfile;
  final MembershipPlan? plan;
  final Gym? gym;
  final Profile? deletedByProfile;

  RevenueLedger({
    required this.id,
    required this.paidAt,
    this.planId,
    this.membershipId,
    this.gymId,
    required this.amountCents,
    required this.currency,
    required this.source,
    required this.entryKind,
    required this.paymentMethod,
    this.notes,
    this.recordedBy,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedBy,
    required this.createdAt,
    this.recordedByProfile,
    this.clientProfile,
    this.plan,
    this.gym,
    this.deletedByProfile,
  });

  // Getters for compatibility
  double get amount => amountCents / 100.0;
  Profile? get profile => clientProfile;
  DateTime get paymentDate => paidAt;
  MembershipPlan? get membershipPlan => plan;

  factory RevenueLedger.fromJson(Map<String, dynamic> json) {
    return RevenueLedger(
      id: json['id'] as String,
      paidAt: DateTime.parse(json['paid_at'] as String),
      planId: json['plan_id'] as String?,
      membershipId: json['membership_id'] as String?,
      gymId: json['gym_id'] as String?,
      amountCents: json['amount_cents'] as int,
      currency: json['currency'] as String,
      source: json['source'] as String,
      entryKind: json['entry_kind'] as String,
      paymentMethod: json['payment_method'] as String,
      notes: json['notes'] as String?,
      recordedBy: json['recorded_by'] as String?,
      isDeleted: json['is_deleted'] as bool? ?? false,
      deletedAt: json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      deletedBy: json['deleted_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      recordedByProfile: json['recorded_by_profile'] != null
          ? Profile.fromJson(
              json['recorded_by_profile'] as Map<String, dynamic>,
            )
          : null,
      clientProfile: json['profile'] != null
          ? Profile.fromJson(json['profile'] as Map<String, dynamic>)
          : null,
      plan: json['membership_plan'] != null
          ? MembershipPlan.fromJson(
              json['membership_plan'] as Map<String, dynamic>,
            )
          : null,
      gym: json['gym'] != null
          ? Gym.fromJson(json['gym'] as Map<String, dynamic>)
          : null,
      deletedByProfile: json['deleted_by_profile'] != null
          ? Profile.fromJson(json['deleted_by_profile'] as Map<String, dynamic>)
          : null,
    );
  }

  String get amountInCurrency => '${amount.toStringAsFixed(2)} $currency';

  bool get isCharge => entryKind == 'charge';
  bool get isRefund => entryKind == 'refund';
}
