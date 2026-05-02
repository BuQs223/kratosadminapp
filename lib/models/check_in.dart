import 'profile.dart';
import 'gym.dart';
import 'membership.dart';

class CheckIn {
  final String id;
  final String userId;
  final String gymId;
  final String? membershipId;
  final DateTime checkedInAt;
  final DateTime? checkedOutAt;
  final String? notes;
  final String?
  status; // success, expiring, expired, denied, no_access, time_restricted
  final String? message; // User-friendly message
  final int? daysLeft; // Days remaining on membership
  final bool? shownToUser; // Flag to track if user has seen this check-in

  // Relations
  final Profile? profile;
  final Gym? gym;
  final Membership? membership;

  CheckIn({
    required this.id,
    required this.userId,
    required this.gymId,
    this.membershipId,
    required this.checkedInAt,
    this.checkedOutAt,
    this.notes,
    this.status,
    this.message,
    this.daysLeft,
    this.shownToUser,
    this.profile,
    this.gym,
    this.membership,
  });

  factory CheckIn.fromJson(Map<String, dynamic> json) {
    // Handle the checked_in_at field safely
    final checkedInAtStr =
        json['checked_in_at'] as String? ?? json['created_at'] as String?;

    if (checkedInAtStr == null) {
      throw Exception('No valid timestamp found for check-in');
    }

    return CheckIn(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      gymId: json['gym_id'] as String? ?? '',
      membershipId: json['membership_id'] as String?,
      checkedInAt: DateTime.parse(checkedInAtStr),
      checkedOutAt: json['checked_out_at'] != null
          ? DateTime.parse(json['checked_out_at'] as String)
          : null,
      notes: json['notes'] as String?,
      status: json['status'] as String?,
      message: json['message'] as String?,
      daysLeft: json['days_left'] as int?,
      shownToUser: json['shown_to_user'] as bool?,
      profile: json['profiles'] != null && json['profiles'] is Map
          ? Profile.fromJson(json['profiles'] as Map<String, dynamic>)
          : json['profile'] != null && json['profile'] is Map
          ? Profile.fromJson(json['profile'] as Map<String, dynamic>)
          : null,
      gym: json['gyms'] != null && json['gyms'] is Map
          ? Gym.fromJson(json['gyms'] as Map<String, dynamic>)
          : json['gym'] != null && json['gym'] is Map
          ? Gym.fromJson(json['gym'] as Map<String, dynamic>)
          : null,
      membership: json['memberships'] != null && json['memberships'] is Map
          ? Membership.fromJson(json['memberships'] as Map<String, dynamic>)
          : json['membership'] != null && json['membership'] is Map
          ? Membership.fromJson(json['membership'] as Map<String, dynamic>)
          : null,
    );
  }

  String? get duration {
    if (checkedOutAt == null) return null;
    final diff = checkedOutAt!.difference(checkedInAt);
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  bool get isActive => checkedOutAt == null;
}
