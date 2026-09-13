import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/profile.dart';
import '../../models/revenue_ledger.dart';
import '../../services/powersync_service.dart';

class MemberRevenueHistoryScreen extends StatefulWidget {
  final Profile member;

  const MemberRevenueHistoryScreen({super.key, required this.member});

  @override
  State<MemberRevenueHistoryScreen> createState() =>
      _MemberRevenueHistoryScreenState();
}

class _MemberRevenueHistoryScreenState
    extends State<MemberRevenueHistoryScreen> {
  List<RevenueLedger> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRevenueEntries();
  }

  Future<void> _loadRevenueEntries() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      await PowerSyncService.connectIfAuthenticated();
      final rows = await PowerSyncService.db.getAll(_memberRevenueSql, [
        widget.member.id,
        widget.member.id,
        widget.member.id,
      ]);

      if (mounted) {
        setState(() {
          _entries = rows.map(_mapRevenueRowToEntry).toList();
          _isLoading = false;
        });
      }
    } catch (error) {
      debugPrint('Error loading member revenue history: $error');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la încărcarea încasărilor: $error')),
        );
      }
    }
  }

  static const String _memberRevenueSql = '''
    WITH user_membership_ids AS (
      SELECT DISTINCT m.id AS membership_id
      FROM memberships m
      LEFT JOIN family_memberships fm ON fm.membership_id = m.id
      WHERE m.user_id = ? OR fm.user_id = ?
    )
    SELECT
      r.id,
      r.paid_at,
      r.plan_id,
      r.membership_id,
      r.gym_id,
      r.amount_cents,
      r.currency,
      r.source,
      r.notes,
      r.created_at,
      r.entry_kind,
      r.payment_method,
      r.recorded_by,
      r.is_deleted,
      r.deleted_at,
      r.deleted_by,
      r.client_user_id,
      r.client_full_name,
      COALESCE(r.client_user_id, p_client.id) AS profile_id,
      COALESCE(r.client_full_name, p_client.full_name) AS profile_full_name,
      g.name AS gym_name,
      mp.name AS plan_name,
      p_recorded.full_name AS recorded_by_full_name,
      p_deleted.full_name AS deleted_by_full_name
    FROM revenue_ledger r
    LEFT JOIN profiles p_client ON p_client.id = r.client_user_id
    LEFT JOIN gyms g ON g.id = r.gym_id
    LEFT JOIN membership_plans mp ON mp.id = r.plan_id
    LEFT JOIN profiles p_recorded ON p_recorded.id = r.recorded_by
    LEFT JOIN profiles p_deleted ON p_deleted.id = r.deleted_by
    WHERE r.client_user_id = ?
      OR r.membership_id IN (SELECT membership_id FROM user_membership_ids)
    ORDER BY datetime(r.paid_at) DESC
  ''';

  RevenueLedger _mapRevenueRowToEntry(Map<String, dynamic> row) {
    final profileId = row['profile_id'] ?? row['client_user_id'];
    final profileFullName = row['profile_full_name'] ?? row['client_full_name'];

    return RevenueLedger.fromJson({
      'id': row['id'],
      'paid_at': row['paid_at'],
      'plan_id': row['plan_id'],
      'membership_id': row['membership_id'],
      'gym_id': row['gym_id'],
      'amount_cents': (row['amount_cents'] as num?)?.toInt() ?? 0,
      'currency': row['currency'] ?? 'RON',
      'source': row['source'] ?? 'membership',
      'notes': row['notes'],
      'created_at': row['created_at'] ?? row['paid_at'],
      'entry_kind': row['entry_kind'] ?? 'charge',
      'payment_method': row['payment_method'] ?? 'cash',
      'recorded_by': row['recorded_by'],
      'is_deleted': _sqliteBool(row['is_deleted']),
      'deleted_at': row['deleted_at'],
      'deleted_by': row['deleted_by'],
      'profile': profileId != null
          ? {
              'id': profileId,
              'full_name': profileFullName ?? widget.member.fullName,
            }
          : {'id': widget.member.id, 'full_name': widget.member.fullName},
      'gym': row['gym_id'] != null && row['gym_name'] != null
          ? {'id': row['gym_id'], 'name': row['gym_name']}
          : null,
      'membership_plan': row['plan_id'] != null && row['plan_name'] != null
          ? {'id': row['plan_id'], 'name': row['plan_name']}
          : null,
      'recorded_by_profile':
          row['recorded_by'] != null && row['recorded_by_full_name'] != null
          ? {
              'id': row['recorded_by'],
              'full_name': row['recorded_by_full_name'],
            }
          : null,
      'deleted_by_profile':
          row['deleted_by'] != null && row['deleted_by_full_name'] != null
          ? {'id': row['deleted_by'], 'full_name': row['deleted_by_full_name']}
          : null,
    });
  }

  bool _sqliteBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    return false;
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('dd MMM yyyy, HH:mm').format(dateTime.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final totalCents = _entries
        .where((entry) => !entry.isDeleted)
        .fold<int>(
          0,
          (sum, entry) =>
              sum + (entry.isRefund ? -entry.amountCents : entry.amountCents),
        );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Istoric încasări'),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: RefreshIndicator(
        onRefresh: _loadRevenueEntries,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 72,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Nicio încasare',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.payments_outlined,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${(totalCents / 100).toStringAsFixed(2)} RON',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${_entries.length} tranzacții',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._entries.map(_buildRevenueCard),
                ],
              ),
      ),
    );
  }

  Widget _buildRevenueCard(RevenueLedger entry) {
    final isDeleted = entry.isDeleted;
    final isRefund = entry.isRefund;
    final amountLabel = isDeleted
        ? '${entry.amountInCurrency} • ȘTERS'
        : isRefund
        ? '- ${entry.amountInCurrency}'
        : '+ ${entry.amountInCurrency}';
    final amountColor = isDeleted
        ? Theme.of(context).colorScheme.onErrorContainer
        : isRefund
        ? Theme.of(context).colorScheme.error
        : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDeleted
              ? Theme.of(context).colorScheme.error.withValues(alpha: 0.35)
              : Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    entry.profile?.fullName ?? widget.member.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDeleted
                        ? Theme.of(
                            context,
                          ).colorScheme.errorContainer.withValues(alpha: 0.45)
                        : isRefund
                        ? Theme.of(
                            context,
                          ).colorScheme.errorContainer.withValues(alpha: 0.45)
                        : Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    amountLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: amountColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildMetaItem(Icons.event, _formatDateTime(entry.paymentDate)),
                _buildMetaItem(
                  entry.paymentMethod == 'cash'
                      ? Icons.money
                      : Icons.credit_card,
                  entry.paymentMethod,
                ),
                if (entry.gym != null)
                  _buildMetaItem(Icons.fitness_center, entry.gym!.name),
                if (entry.recordedByProfile != null)
                  _buildMetaItem(
                    Icons.person_outline,
                    'Înregistrat de ${entry.recordedByProfile!.fullName}',
                  ),
              ],
            ),
            if (isDeleted) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        entry.deletedAt != null
                            ? 'Șters la ${_formatDateTime(entry.deletedAt!)}'
                            : 'Marcat ca șters',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (entry.membershipPlan != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.card_membership,
                      size: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      entry.membershipPlan!.name,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (entry.notes != null && entry.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                entry.notes!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetaItem(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
