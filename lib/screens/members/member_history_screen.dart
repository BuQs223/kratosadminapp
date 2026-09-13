import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/profile.dart';
import '../../services/powersync_service.dart';

class MembershipEvent {
  final String id;
  final String membershipId;
  final String eventType;
  final DateTime at;
  final String? byUserId;
  final String? byUserName;
  final String? notes;
  final int? deltaDays;
  final int? deltaCents;
  final DateTime? oldStartDate;
  final DateTime? oldEndDate;
  final DateTime? newStartDate;
  final DateTime? newEndDate;
  final String? planName;

  MembershipEvent({
    required this.id,
    required this.membershipId,
    required this.eventType,
    required this.at,
    this.byUserId,
    this.byUserName,
    this.notes,
    this.deltaDays,
    this.deltaCents,
    this.oldStartDate,
    this.oldEndDate,
    this.newStartDate,
    this.newEndDate,
    this.planName,
  });

  factory MembershipEvent.fromJson(Map<String, dynamic> json) {
    return MembershipEvent(
      id: json['id'] as String,
      membershipId: json['membership_id'] as String,
      eventType: json['event_type'] as String,
      at: DateTime.parse(json['at'] as String),
      byUserId: json['by_user'] as String?,
      byUserName: json['by_user_name'] as String?,
      notes: json['notes'] as String?,
      deltaDays: json['delta_days'] as int?,
      deltaCents: json['delta_cents'] as int?,
      oldStartDate: json['old_start_date'] != null
          ? DateTime.parse(json['old_start_date'] as String)
          : null,
      oldEndDate: json['old_end_date'] != null
          ? DateTime.parse(json['old_end_date'] as String)
          : null,
      newStartDate: json['new_start_date'] != null
          ? DateTime.parse(json['new_start_date'] as String)
          : null,
      newEndDate: json['new_end_date'] != null
          ? DateTime.parse(json['new_end_date'] as String)
          : null,
      planName: json['plan_name'] as String?,
    );
  }

  String get eventTypeDisplay {
    switch (eventType) {
      case 'created':
        return 'Creat';
      case 'extended':
        return 'Prelungit';
      case 'canceled':
        return 'Anulat';
      case 'paused':
        return 'Înghețat';
      case 'upgraded':
        return 'Upgrade';
      case 'edited':
        return 'Editat';
      case 'resumed':
        return 'Reluat';
      default:
        return eventType;
    }
  }

  IconData get eventIcon {
    switch (eventType) {
      case 'created':
        return Icons.add_circle;
      case 'extended':
        return Icons.update;
      case 'canceled':
        return Icons.cancel;
      case 'paused':
        return Icons.pause_circle;
      case 'upgraded':
        return Icons.upgrade;
      case 'edited':
        return Icons.edit;
      case 'resumed':
        return Icons.play_circle;
      default:
        return Icons.info;
    }
  }

  Color get eventColor {
    switch (eventType) {
      case 'created':
        return const Color(0xFF43A047); // Green
      case 'extended':
        return const Color(0xFF1E88E5); // Blue
      case 'canceled':
        return const Color(0xFFE53935); // Red
      case 'paused':
        return const Color(0xFF7B1FA2); // Purple
      case 'upgraded':
        return const Color(0xFFFB8C00); // Orange
      case 'edited':
        return const Color(0xFF757575); // Grey
      case 'resumed':
        return const Color(0xFF00ACC1); // Cyan
      default:
        return const Color(0xFF757575); // Grey
    }
  }
}

class MemberHistoryScreen extends StatefulWidget {
  final Profile member;

  const MemberHistoryScreen({super.key, required this.member});

  @override
  State<MemberHistoryScreen> createState() => _MemberHistoryScreenState();
}

class _MemberHistoryScreenState extends State<MemberHistoryScreen> {
  List<MembershipEvent> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    try {
      await PowerSyncService.connectIfAuthenticated();
      final response = await PowerSyncService.db.getAll(_membershipHistorySql, [
        widget.member.id,
        widget.member.id,
      ]);

      if (mounted) {
        setState(() {
          _events = response
              .map(
                (row) => MembershipEvent.fromJson({
                  'id': row['id'],
                  'membership_id': row['membership_id'],
                  'event_type': row['event_type'],
                  'at': row['at'],
                  'by_user': row['by_user'],
                  'by_user_name': row['by_user_name'],
                  'notes': row['notes'],
                  'delta_days': (row['delta_days'] as num?)?.toInt(),
                  'delta_cents': (row['delta_cents'] as num?)?.toInt(),
                  'old_start_date': row['old_start_date'],
                  'old_end_date': row['old_end_date'],
                  'new_start_date': row['new_start_date'],
                  'new_end_date': row['new_end_date'],
                  'plan_name': row['plan_name'],
                }),
              )
              .toList();
          _isLoading = false;
        });
      }
    } catch (error) {
      debugPrint('Error loading history: $error');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  static const String _membershipHistorySql = '''
    SELECT
      me.id,
      me.membership_id,
      me.event_type,
      me.at,
      me.by_user,
      p.full_name AS by_user_name,
      me.notes,
      me.delta_days,
      me.delta_cents,
      me.old_start_date,
      me.old_end_date,
      me.new_start_date,
      me.new_end_date,
      mp.name AS plan_name
    FROM membership_events me
    JOIN memberships m ON m.id = me.membership_id
    JOIN membership_plans mp ON mp.id = m.plan_id
    LEFT JOIN profiles p ON p.id = me.by_user
    WHERE m.user_id = ?
      OR me.membership_id IN (
        SELECT fm.membership_id
        FROM family_memberships fm
        WHERE fm.user_id = ?
      )
    ORDER BY datetime(me.at) DESC
  ''';

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  String _formatDateTime(DateTime dateTime) {
    final localDateTime = dateTime.toLocal();
    return DateFormat('dd MMM yyyy, HH:mm').format(localDateTime);
  }

  String _formatPrice(int cents) {
    return '${(cents / 100).toStringAsFixed(0)} RON';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Istoric Membru'), elevation: 0),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
          ? _buildEmptyState()
          : _buildTimeline(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'Niciun eveniment',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Istoricul va apărea aici',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          final isFirst = index == 0;
          final isLast = index == _events.length - 1;

          return _buildTimelineItem(event, isFirst, isLast);
        },
      ),
    );
  }

  Widget _buildTimelineItem(MembershipEvent event, bool isFirst, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line and dot
          SizedBox(
            width: 48,
            child: Column(
              children: [
                // Top line
                if (!isFirst)
                  Container(
                    width: 2,
                    height: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withOpacity(0.5),
                  ),
                // Dot
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: event.eventColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: event.eventColor, width: 2),
                  ),
                  child: Icon(
                    event.eventIcon,
                    size: 16,
                    color: event.eventColor,
                  ),
                ),
                // Bottom line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withOpacity(0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Event card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                elevation: 0,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: event.eventColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              event.eventTypeDisplay,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: event.eventColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatDateTime(event.at),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Plan name
                      if (event.planName != null)
                        Row(
                          children: [
                            Icon(
                              Icons.card_membership,
                              size: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              event.planName!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      // Date changes
                      if (event.newStartDate != null ||
                          event.newEndDate != null) ...[
                        const SizedBox(height: 8),
                        _buildDateChange(event),
                      ],
                      // Delta info
                      if (event.deltaDays != null ||
                          event.deltaCents != null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (event.deltaDays != null)
                              _buildInfoChip(
                                Icons.calendar_today,
                                '${event.deltaDays! > 0 ? '+' : ''}${event.deltaDays} zile',
                                event.deltaDays! > 0
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            if (event.deltaCents != null)
                              _buildInfoChip(
                                Icons.payments,
                                _formatPrice(event.deltaCents!),
                                Colors.blue,
                              ),
                          ],
                        ),
                      ],
                      // By user
                      if (event.byUserName != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'de ${event.byUserName}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                          ],
                        ),
                      ],
                      // Notes
                      if (event.notes != null && event.notes!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withOpacity(0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.notes,
                                size: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  event.notes!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateChange(MembershipEvent event) {
    final hasOldDates = event.oldStartDate != null || event.oldEndDate != null;
    final hasNewDates = event.newStartDate != null || event.newEndDate != null;

    if (!hasNewDates) return const SizedBox.shrink();

    return Row(
      children: [
        Icon(
          Icons.date_range,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        if (hasOldDates && event.oldEndDate != null) ...[
          Text(
            _formatDate(event.oldEndDate!),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              decoration: TextDecoration.lineThrough,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_forward,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
        ],
        if (event.newEndDate != null)
          Text(
            _formatDate(event.newEndDate!),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.green,
            ),
          ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
