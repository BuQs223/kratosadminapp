import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../models/revenue_ledger.dart';
import '../../services/powersync_service.dart';
import '../../services/supabase_service.dart';
import '../members/member_detail_screen.dart';
import 'revenue_analytics_screen.dart';

class RevenueScreen extends StatefulWidget {
  const RevenueScreen({super.key});

  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  List<RevenueLedger> _entries = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  Map<String, double> _stats = {'total': 0, 'cash': 0, 'card': 0};
  int _totalCount = 0;

  // Tab for period filter
  String _periodFilter = 'all'; // 'all' or 'today'

  // Pagination
  static const int _pageSize = 20;
  int _currentOffset = 0;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isExporting = false;

  // Today vs Yesterday comparison
  Map<String, dynamic>? _comparisonData;
  bool _isLoadingComparison = false;

  // Filters
  String? _selectedGymId;
  String _paymentMethodFilter = 'all'; // all, cash, card
  String? _selectedPlanId;
  String _amountFilter = 'all'; // all, zero, non_zero
  String _deletedStatusFilter = 'all'; // active, deleted, all
  DateTime? _customDateStart;
  DateTime? _customDateEnd;
  final List<Map<String, String>> _gyms = [];
  final List<Map<String, String>> _membershipPlans = [];

  // Scroll controller for pagination
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadGyms();
    _loadMembershipPlans();
    _loadRevenue();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoadingMore &&
        _hasMoreData) {
      _loadMoreRevenue();
    }
  }

  Future<void> _loadGyms() async {
    try {
      await PowerSyncService.connectIfAuthenticated();
      final response = await PowerSyncService.db.getAll(
        'SELECT id, name FROM gyms ORDER BY name COLLATE NOCASE',
      );

      if (mounted) {
        setState(() {
          _gyms.clear();
          _gyms.addAll(
            response.map(
              (gym) => {
                'id': gym['id'] as String,
                'name': gym['name'] as String? ?? '',
              },
            ),
          );
        });
      }
    } catch (error) {
      print('Error loading gyms: $error');
    }
  }

  Future<void> _loadMembershipPlans() async {
    try {
      await PowerSyncService.connectIfAuthenticated();
      final response = await PowerSyncService.db.getAll('''
        SELECT id, name
        FROM membership_plans
        WHERE COALESCE(is_active, 0) = 1
        ORDER BY name COLLATE NOCASE
      ''');

      if (mounted) {
        setState(() {
          _membershipPlans.clear();
          _membershipPlans.addAll(
            response.map(
              (plan) => {
                'id': plan['id'] as String,
                'name': plan['name'] as String? ?? '',
              },
            ),
          );
        });
      }
    } catch (error) {
      print('Error loading membership plans: $error');
    }
  }

  Future<void> _loadComparison() async {
    if (_periodFilter != 'today') {
      if (mounted) setState(() => _comparisonData = null);
      return;
    }

    if (mounted) setState(() => _isLoadingComparison = true);

    try {
      await PowerSyncService.connectIfAuthenticated();
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));
      final lastWeekStart = todayStart.subtract(const Duration(days: 7));
      final lastWeekEnd = lastWeekStart.add(const Duration(days: 1));
      final params = <Object?>[
        todayStart.toIso8601String(),
        todayEnd.toIso8601String(),
        yesterdayStart.toIso8601String(),
        todayStart.toIso8601String(),
        lastWeekStart.toIso8601String(),
        lastWeekEnd.toIso8601String(),
        todayStart.toIso8601String(),
        todayEnd.toIso8601String(),
        yesterdayStart.toIso8601String(),
        todayStart.toIso8601String(),
      ];
      final gymClause = _selectedGymId != null ? 'AND gym_id = ?' : '';
      if (_selectedGymId != null) {
        params.add(_selectedGymId);
      }

      final row = await PowerSyncService.db.get('''
        SELECT
          COALESCE(SUM(CASE WHEN datetime(paid_at) >= datetime(?) AND datetime(paid_at) < datetime(?) THEN amount_cents ELSE 0 END), 0) AS today_revenue,
          COALESCE(SUM(CASE WHEN datetime(paid_at) >= datetime(?) AND datetime(paid_at) < datetime(?) THEN amount_cents ELSE 0 END), 0) AS yesterday_revenue,
          COALESCE(SUM(CASE WHEN datetime(paid_at) >= datetime(?) AND datetime(paid_at) < datetime(?) THEN amount_cents ELSE 0 END), 0) AS last_week_same_day_revenue,
          COUNT(CASE WHEN datetime(paid_at) >= datetime(?) AND datetime(paid_at) < datetime(?) THEN 1 END) AS today_count,
          COUNT(CASE WHEN datetime(paid_at) >= datetime(?) AND datetime(paid_at) < datetime(?) THEN 1 END) AS yesterday_count
        FROM revenue_ledger
        WHERE entry_kind = 'charge'
          AND COALESCE(is_deleted, 0) = 0
          $gymClause
      ''', params);

      if (mounted) {
        setState(() {
          _comparisonData = Map<String, dynamic>.from(row);
          _isLoadingComparison = false;
        });
      }
    } catch (error) {
      print('Error loading comparison: $error');
      if (mounted) {
        setState(() => _isLoadingComparison = false);
      }
    }
  }

  Map<String, DateTime?> _resolveDateRange() {
    DateTime? dateStart;
    DateTime? dateEnd;

    if (_periodFilter == 'today') {
      final now = DateTime.now();
      dateStart = DateTime(now.year, now.month, now.day);
      dateEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    } else if (_customDateStart != null && _customDateEnd != null) {
      dateStart = _customDateStart;
      dateEnd = DateTime(
        _customDateEnd!.year,
        _customDateEnd!.month,
        _customDateEnd!.day,
        23,
        59,
        59,
        999,
      );
    }

    return {'start': dateStart, 'end': dateEnd};
  }

  RevenueLedger _mapRevenueRowToEntry(Map<String, dynamic> row) {
    final profileId = row['profile_id'] ?? row['client_user_id'];
    final profileFullName = row['profile_full_name'] ?? row['client_full_name'];
    final gymMap = row['gym'] as Map<String, dynamic>?;
    final planMap = row['membership_plan'] as Map<String, dynamic>?;
    final recordedByProfileMap =
        row['recorded_by_profile'] as Map<String, dynamic>?;
    final deletedByProfileMap =
        row['deleted_by_profile'] as Map<String, dynamic>?;

    return RevenueLedger.fromJson({
      'id': row['id'],
      'paid_at': row['paid_at'],
      'plan_id': row['plan_id'],
      'membership_id': row['membership_id'],
      'gym_id': row['gym_id'],
      'amount_cents': row['amount_cents'],
      'currency': row['currency'],
      'source': row['source'],
      'notes': row['notes'],
      'created_at': row['created_at'],
      'entry_kind': row['entry_kind'],
      'payment_method': row['payment_method'],
      'idempotency_key': row['idempotency_key'],
      'recorded_by': row['recorded_by'],
      'is_deleted': _sqliteBool(row['is_deleted']),
      'deleted_at': row['deleted_at'],
      'deleted_by': row['deleted_by'],
      'profile': profileId != null
          ? {'id': profileId, 'full_name': profileFullName ?? 'Necunoscut'}
          : null,
      'gym': gymMap != null
          ? {'id': gymMap['id'], 'name': gymMap['name']}
          : (row['gym_id'] != null && row['gym_name'] != null)
          ? {'id': row['gym_id'], 'name': row['gym_name']}
          : null,
      'membership_plan': planMap != null
          ? {'id': planMap['id'], 'name': planMap['name']}
          : (row['plan_id'] != null && row['plan_name'] != null)
          ? {'id': row['plan_id'], 'name': row['plan_name']}
          : null,
      'recorded_by_profile': recordedByProfileMap != null
          ? {
              'id': recordedByProfileMap['id'],
              'full_name': recordedByProfileMap['full_name'],
            }
          : row['recorded_by'] != null && row['recorded_by_full_name'] != null
          ? {
              'id': row['recorded_by'],
              'full_name': row['recorded_by_full_name'],
            }
          : null,
      'deleted_by_profile': deletedByProfileMap != null
          ? {
              'id': deletedByProfileMap['id'],
              'full_name': deletedByProfileMap['full_name'],
            }
          : row['deleted_by'] != null && row['deleted_by_full_name'] != null
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

  String _escapeLikeValue(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  String _buildRevenueWhereClause({
    required DateTime? dateStart,
    required DateTime? dateEnd,
    required List<Object?> params,
  }) {
    final clauses = <String>["r.entry_kind = 'charge'"];

    if (_deletedStatusFilter == 'deleted') {
      clauses.add('COALESCE(r.is_deleted, 0) = 1');
    } else if (_deletedStatusFilter == 'active') {
      clauses.add('COALESCE(r.is_deleted, 0) = 0');
    }

    if (_selectedGymId != null) {
      clauses.add('r.gym_id = ?');
      params.add(_selectedGymId);
    }
    if (_paymentMethodFilter != 'all') {
      clauses.add('r.payment_method = ?');
      params.add(_paymentMethodFilter);
    }
    if (_selectedPlanId != null) {
      clauses.add('r.plan_id = ?');
      params.add(_selectedPlanId);
    }
    if (_amountFilter == 'zero') {
      clauses.add('COALESCE(r.amount_cents, 0) = 0');
    } else if (_amountFilter == 'non_zero') {
      clauses.add('COALESCE(r.amount_cents, 0) > 0');
    }
    if (dateStart != null) {
      clauses.add('datetime(r.paid_at) >= datetime(?)');
      params.add(dateStart.toIso8601String());
    }
    if (dateEnd != null) {
      clauses.add('datetime(r.paid_at) <= datetime(?)');
      params.add(dateEnd.toIso8601String());
    }

    final search = _searchQuery.trim().toLowerCase();
    if (search.isNotEmpty) {
      final like = '%${_escapeLikeValue(search)}%';
      clauses.add('''
        (
          LOWER(COALESCE(r.notes, '')) LIKE ? ESCAPE '\\'
          OR LOWER(COALESCE(r.client_full_name, '')) LIKE ? ESCAPE '\\'
          OR LOWER(COALESCE(p_client.full_name, '')) LIKE ? ESCAPE '\\'
          OR LOWER(COALESCE(r.source, '')) LIKE ? ESCAPE '\\'
          OR CAST(COALESCE(r.amount_cents, 0) / 100.0 AS TEXT) LIKE ? ESCAPE '\\'
        )
      ''');
      params.addAll([like, like, like, like, like]);
    }

    return 'WHERE ${clauses.join(' AND ')}';
  }

  String _revenueRowsSql(String whereClause) {
    return '''
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
        r.idempotency_key,
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
      $whereClause
      ORDER BY datetime(r.paid_at) DESC
      LIMIT ? OFFSET ?
    ''';
  }

  String _revenueStatsSql(String whereClause) {
    return '''
      SELECT
        COUNT(*) AS total_count,
        COALESCE(SUM(r.amount_cents), 0) AS total_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'cash' THEN r.amount_cents ELSE 0 END), 0) AS cash_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'card' THEN r.amount_cents ELSE 0 END), 0) AS card_revenue
      FROM revenue_ledger r
      LEFT JOIN profiles p_client ON p_client.id = r.client_user_id
      $whereClause
    ''';
  }

  Future<_RevenueFetchResult> _fetchRevenueData({
    required DateTime? dateStart,
    required DateTime? dateEnd,
    required int limit,
    required int offset,
  }) async {
    await PowerSyncService.connectIfAuthenticated();
    final whereParams = <Object?>[];
    final whereClause = _buildRevenueWhereClause(
      dateStart: dateStart,
      dateEnd: dateEnd,
      params: whereParams,
    );
    final statsRow = await PowerSyncService.db.get(
      _revenueStatsSql(whereClause),
      whereParams,
    );
    final rows = await PowerSyncService.db.getAll(
      _revenueRowsSql(whereClause),
      [...whereParams, limit, offset],
    );
    final totalCount = (statsRow['total_count'] as num?)?.toInt() ?? 0;

    return _RevenueFetchResult(
      rows: rows.map((row) => Map<String, dynamic>.from(row)).toList(),
      totalCount: totalCount,
      totalRevenueCents: (statsRow['total_revenue'] as num?)?.toInt() ?? 0,
      cashRevenueCents: (statsRow['cash_revenue'] as num?)?.toInt() ?? 0,
      cardRevenueCents: (statsRow['card_revenue'] as num?)?.toInt() ?? 0,
      hasMoreData: offset + rows.length < totalCount,
    );
  }

  Future<void> _loadRevenue({bool isLoadMore = false}) async {
    if (isLoadMore) {
      if (mounted) {
        setState(() => _isLoadingMore = true);
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _currentOffset = 0;
          _hasMoreData = true;
        });
      }
    }

    try {
      final dateRange = _resolveDateRange();
      final result = await _fetchRevenueData(
        dateStart: dateRange['start'],
        dateEnd: dateRange['end'],
        limit: _pageSize,
        offset: isLoadMore ? _currentOffset : 0,
      );

      final entries = result.rows.map(_mapRevenueRowToEntry).toList();
      final stats = {
        'total': result.totalRevenueCents / 100,
        'cash': result.cashRevenueCents / 100,
        'card': result.cardRevenueCents / 100,
      };

      if (mounted) {
        setState(() {
          if (isLoadMore) {
            _entries.addAll(entries);
          } else {
            _entries = entries;
            _stats = stats;
            _totalCount = result.totalCount;
          }
          _currentOffset = isLoadMore
              ? _currentOffset + entries.length
              : entries.length;
          _hasMoreData = result.hasMoreData;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (error) {
      print('Error loading revenue: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare: $error')));
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
      }
    }
  }

  Future<void> _loadMoreRevenue() async {
    if (!_hasMoreData || _isLoadingMore) return;
    await _loadRevenue(isLoadMore: true);
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        selectedGymId: _selectedGymId,
        paymentMethodFilter: _paymentMethodFilter,
        selectedPlanId: _selectedPlanId,
        amountFilter: _amountFilter,
        deletedStatusFilter: _deletedStatusFilter,
        customDateStart: _customDateStart,
        customDateEnd: _customDateEnd,
        gyms: _gyms,
        membershipPlans: _membershipPlans,
        onApplyFilters:
            (
              gymId,
              paymentMethod,
              planId,
              amountFilter,
              deletedStatusFilter,
              dateStart,
              dateEnd,
            ) {
              if (mounted) {
                setState(() {
                  _selectedGymId = gymId;
                  _paymentMethodFilter = paymentMethod;
                  _selectedPlanId = planId;
                  _amountFilter = amountFilter;
                  _deletedStatusFilter = deletedStatusFilter;
                  _customDateStart = dateStart;
                  _customDateEnd = dateEnd;
                  // Reset period filter when custom dates are applied
                  if (dateStart != null && dateEnd != null) {
                    _periodFilter = 'all';
                  }
                });
              }
              _loadRevenue();
            },
        onClearFilters: () {
          if (mounted) {
            setState(() {
              _selectedGymId = null;
              _paymentMethodFilter = 'all';
              _selectedPlanId = null;
              _amountFilter = 'all';
              _deletedStatusFilter = 'all';
              _customDateStart = null;
              _customDateEnd = null;
              _periodFilter = 'all';
              _searchQuery = '';
              _searchController.clear();
            });
          }
          _loadRevenue();
        },
      ),
    );
  }

  int get _activeFiltersCount {
    int count = 0;
    if (_selectedGymId != null) count++;
    if (_paymentMethodFilter != 'all') count++;
    if (_selectedPlanId != null) count++;
    if (_amountFilter != 'all') count++;
    if (_deletedStatusFilter != 'all') count++;
    if (_customDateStart != null && _customDateEnd != null) count++;
    if (_searchQuery.isNotEmpty) count++;
    return count;
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(
      symbol: 'RON ',
      decimalDigits: 2,
    ).format(amount);
  }

  String _formatDateTime(DateTime dateTime) {
    // Convert to local time (Bucharest timezone)
    final localDateTime = dateTime.toLocal();
    return DateFormat('dd MMM yyyy, HH:mm').format(localDateTime);
  }

  Widget _buildComparisonCard() {
    if (_isLoadingComparison) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_comparisonData == null) {
      return const SizedBox.shrink();
    }

    final todayRevenue =
        ((_comparisonData!['today_revenue'] as num?) ?? 0) / 100;
    final yesterdayRevenue =
        ((_comparisonData!['yesterday_revenue'] as num?) ?? 0) / 100;
    final lastWeekRevenue =
        ((_comparisonData!['last_week_same_day_revenue'] as num?) ?? 0) / 100;
    final todayCount = (_comparisonData!['today_count'] as num?) ?? 0;
    final yesterdayCount = (_comparisonData!['yesterday_count'] as num?) ?? 0;

    // Calculate percentage changes
    double vsYesterdayPercent = 0;
    if (yesterdayRevenue > 0) {
      vsYesterdayPercent =
          ((todayRevenue - yesterdayRevenue) / yesterdayRevenue) * 100;
    } else if (todayRevenue > 0) {
      vsYesterdayPercent = 100;
    }

    double vsLastWeekPercent = 0;
    if (lastWeekRevenue > 0) {
      vsLastWeekPercent =
          ((todayRevenue - lastWeekRevenue) / lastWeekRevenue) * 100;
    } else if (todayRevenue > 0) {
      vsLastWeekPercent = 100;
    }

    final difference = todayRevenue - yesterdayRevenue;
    final isPositive = difference >= 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isPositive
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isPositive
                ? [
                    Colors.green.withValues(alpha: 0.08),
                    Colors.green.withValues(alpha: 0.02),
                  ]
                : [
                    Colors.red.withValues(alpha: 0.08),
                    Colors.red.withValues(alpha: 0.02),
                  ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isPositive ? Icons.trending_up : Icons.trending_down,
                    color: isPositive ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Astăzi vs Ieri',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Astăzi',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatCurrency(todayRevenue),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$todayCount tranzacții',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 60,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ieri',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatCurrency(yesterdayRevenue),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          Text(
                            '$yesterdayCount tranzacții',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isPositive
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPositive
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 16,
                              color: isPositive ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${isPositive ? '+' : ''}${_formatCurrency(difference)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isPositive ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${isPositive ? '+' : ''}${vsYesterdayPercent.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isPositive ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (lastWeekRevenue > 0 || todayRevenue > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'vs aceeași zi săpt. trecută: ',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      '${vsLastWeekPercent >= 0 ? '+' : ''}${vsLastWeekPercent.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: vsLastWeekPercent >= 0
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    Text(
                      ' (${_formatCurrency(lastWeekRevenue)})',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportToCSV() async {
    if (_isExporting) return;

    if (mounted) setState(() => _isExporting = true);

    try {
      final dateRange = _resolveDateRange();
      final dateStart = dateRange['start'];
      final dateEnd = dateRange['end'];

      final result = await _fetchRevenueData(
        dateStart: dateStart,
        dateEnd: dateEnd,
        limit: 1000000,
        offset: 0,
      );
      final allData = result.rows;

      if (allData.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nu există tranzacții de exportat')),
          );
        }
        return;
      }

      // Create CSV content
      final StringBuffer csv = StringBuffer();

      // Add BOM for Excel to recognize UTF-8
      csv.write('\uFEFF');

      // Header row
      csv.writeln(
        'Data,Membru,Sumă (RON),Metodă Plată,Sală,Plan Abonament,Note,Înregistrat de,Status,Șters la,Șters de',
      );

      // Data rows
      for (final row in allData) {
        final paidAt = row['paid_at'] != null
            ? DateFormat(
                'dd/MM/yyyy HH:mm',
              ).format(DateTime.parse(row['paid_at']).toLocal())
            : '';
        final memberName = _escapeCSV(row['profile_full_name'] ?? 'Necunoscut');
        final amount = ((row['amount_cents'] as num?) ?? 0) / 100;
        final paymentMethod = row['payment_method'] ?? '';
        final gymName = _escapeCSV(row['gym_name'] ?? '');
        final planName = _escapeCSV(row['plan_name'] ?? '');
        final notes = _escapeCSV(row['notes'] ?? '');
        final recordedBy = _escapeCSV(row['recorded_by_full_name'] ?? '');
        final isDeleted = _sqliteBool(row['is_deleted']);
        final deletedStatus = isDeleted ? 'Șters' : 'Activ';
        final deletedAt = row['deleted_at'] != null
            ? _escapeCSV(
                DateFormat(
                  'dd/MM/yyyy HH:mm',
                ).format(DateTime.parse(row['deleted_at']).toLocal()),
              )
            : '';
        final deletedBy = _escapeCSV(row['deleted_by_full_name'] ?? '');

        csv.writeln(
          '$paidAt,$memberName,${amount.toStringAsFixed(2)},$paymentMethod,$gymName,$planName,$notes,$recordedBy,$deletedStatus,$deletedAt,$deletedBy',
        );
      }

      // Get the temporary directory
      final directory = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${directory.path}/venituri_$timestamp.csv');

      // Write CSV to file
      await file.writeAsString(csv.toString());

      // Share the file
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Export Venituri Kratos Gym - $timestamp',
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${allData.length} tranzacții exportate')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare la export: $error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  String _escapeCSV(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _deleteTransaction(RevenueLedger entry) async {
    if (entry.isDeleted) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marchează Ca ștearsă'),
        content: Text(
          'Tranzacția de ${entry.amountInCurrency} va fi marcată ca ștearsă, dar păstrată în istoric.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Marchează'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final supabase = SupabaseService.client;
      await supabase
          .from('revenue_ledger')
          .update({
            'is_deleted': true,
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
            'deleted_by': supabase.auth.currentUser?.id,
          })
          .eq('id', entry.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tranzacție marcată ca ștearsă')),
        );
        _loadRevenue(); // Reload the list
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare la ștergere: $error')));
      }
    }
  }

  Future<void> _restoreTransaction(RevenueLedger entry) async {
    if (!entry.isDeleted) return;

    try {
      final supabase = SupabaseService.client;
      await supabase
          .from('revenue_ledger')
          .update({'is_deleted': false, 'deleted_at': null, 'deleted_by': null})
          .eq('id', entry.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tranzacție restaurată cu succes')),
        );
        _loadRevenue();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare la restaurare: $error')));
      }
    }
  }

  Future<void> _editTransaction(RevenueLedger entry) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditTransactionDialog(
        entry: entry,
        gyms: _gyms,
        membershipPlans: _membershipPlans,
      ),
    );

    if (result == null) return;

    try {
      final supabase = SupabaseService.client;
      await supabase.from('revenue_ledger').update(result).eq('id', entry.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tranzacție actualizată cu succes')),
        );
        _loadRevenue(); // Reload the list
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la actualizare: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Venituri'),
        actions: [
          // Export CSV button
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download),
            onPressed: _isExporting ? null : _exportToCSV,
            tooltip: 'Exportă CSV',
          ),
          // Filter button with badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showFilterBottomSheet,
                tooltip: 'Filtre',
              ),
              if (_activeFiltersCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$_activeFiltersCount',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onError,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRevenue,
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  // Period Filter Tabs
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PeriodTab(
                            label: 'Toate Veniturile',
                            isSelected: _periodFilter == 'all',
                            onTap: () {
                              if (mounted) {
                                setState(() {
                                  _periodFilter = 'all';
                                  _customDateStart = null;
                                  _customDateEnd = null;
                                });
                              }
                              _loadRevenue();
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _PeriodTab(
                            label: 'Astăzi',
                            isSelected: _periodFilter == 'today',
                            onTap: () {
                              if (mounted) {
                                setState(() {
                                  _periodFilter = 'today';
                                  _customDateStart = null;
                                  _customDateEnd = null;
                                });
                              }
                              _loadRevenue();
                              _loadComparison();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Search Bar
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Caută după nume membru, sumă sau note...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                                _loadRevenue();
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      if (mounted) setState(() => _searchQuery = value);
                    },
                    onSubmitted: (value) {
                      _loadRevenue();
                    },
                    textInputAction: TextInputAction.search,
                  ),
                  if (_searchQuery.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: _loadRevenue,
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Caută'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Today vs Yesterday Comparison Card
                  if (_periodFilter == 'today') ...[
                    _buildComparisonCard(),
                    const SizedBox(height: 16),
                  ],

                  // Stats Cards - Dashboard Style (Column Layout)
                  _StatCard(
                    title: 'Total Venituri',
                    value: _formatCurrency(_stats['total']!),
                    icon: '💰',
                    color: const Color(0xFF8E24AA), // Purple 600
                    isCompact: true,
                  ),
                  const SizedBox(height: 6),
                  _StatCard(
                    title: 'Cash',
                    value: _formatCurrency(_stats['cash']!),
                    icon: '💵',
                    color: const Color(0xFF43A047), // Green 600
                    isCompact: true,
                  ),

                  const SizedBox(height: 6),
                  _StatCard(
                    title: 'Card',
                    value: _formatCurrency(_stats['card']!),
                    icon: '💳',
                    color: const Color(0xFF1E88E5), // Blue 600
                    isCompact: true,
                  ),
                  const SizedBox(height: 6),
                  _StatCard(
                    title: 'Tranzacții',
                    value: _totalCount.toString(),
                    icon: '🧾',
                    color: const Color(0xFFFB8C00), // Orange 600
                    isCompact: true,
                  ),

                  const SizedBox(height: 12),

                  // Analytics Button
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const RevenueAnalyticsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.analytics),
                    label: const Text('Vezi Grafice și Analiză'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Entries List Header
                  Text(
                    'Tranzacții recente',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_entries.isEmpty)
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Column(
                          children: [
                            Icon(
                              Icons.payments_outlined,
                              size: 48,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _deletedStatusFilter == 'deleted'
                                  ? 'Nicio tranzacție ștearsă'
                                  : 'Nicio tranzacție',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._entries.map((entry) {
                      final isDeleted = entry.isDeleted;
                      final deletedByLabel =
                          entry.deletedByProfile?.fullName ??
                          (entry.deletedBy == SupabaseService.currentUser?.id
                              ? 'Tu'
                              : null);
                      return Slidable(
                        key: ValueKey(entry.id),
                        endActionPane: ActionPane(
                          motion: const DrawerMotion(),
                          children: isDeleted
                              ? [
                                  SlidableAction(
                                    onPressed: (context) =>
                                        _restoreTransaction(entry),
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    icon: Icons.restore,
                                    label: 'Restore',
                                  ),
                                ]
                              : [
                                  SlidableAction(
                                    onPressed: (context) =>
                                        _editTransaction(entry),
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    icon: Icons.edit,
                                    label: 'Edit',
                                  ),
                                  SlidableAction(
                                    onPressed: (context) =>
                                        _deleteTransaction(entry),
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    icon: Icons.delete,
                                    label: 'Șterge',
                                  ),
                                ],
                        ),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isDeleted
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.error.withValues(alpha: 0.35)
                                  : Theme.of(context).colorScheme.outlineVariant
                                        .withOpacity(0.5),
                            ),
                          ),
                          child: InkWell(
                            onTap: entry.profile != null
                                ? () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            MemberDetailScreen(
                                              member: entry.profile!,
                                            ),
                                      ),
                                    );
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.profile?.fullName ?? 'Unknown',
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
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .errorContainer
                                                    .withValues(alpha: 0.45)
                                              : Colors.green.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          isDeleted
                                              ? '${entry.amountInCurrency} • ȘTERS'
                                              : '+ ${entry.amountInCurrency}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: isDeleted
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.onErrorContainer
                                                : Colors.green,
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
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.event,
                                            size: 14,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatDateTime(entry.paymentDate),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            entry.paymentMethod == 'cash'
                                                ? Icons.money
                                                : Icons.credit_card,
                                            size: 14,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            entry.paymentMethod,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                      if (entry.gym != null)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.fitness_center,
                                              size: 14,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              entry.gym!.name,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      if (entry.recordedByProfile != null)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
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
                                              'Înregistrat de ${entry.recordedByProfile!.fullName}',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
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
                                        color: Theme.of(context)
                                            .colorScheme
                                            .errorContainer
                                            .withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.delete_outline,
                                            size: 14,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onErrorContainer,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              entry.deletedAt != null
                                                  ? 'Șters la ${_formatDateTime(entry.deletedAt!)}${deletedByLabel != null ? ' de $deletedByLabel' : ''}'
                                                  : 'Marcat ca șters${deletedByLabel != null ? ' de $deletedByLabel' : ''}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onErrorContainer,
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
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.card_membership,
                                            size: 12,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            entry.membershipPlan!.name,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onPrimaryContainer,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (entry.notes != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      entry.notes!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontStyle: FontStyle.italic,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),

                  // Loading indicator for pagination
                  if (_isLoadingMore)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),

                  // End of list indicator
                  if (!_hasMoreData && _entries.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          'Toate tranzacțiile au fost încărcate',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _RevenueFetchResult {
  final List<Map<String, dynamic>> rows;
  final int totalCount;
  final int totalRevenueCents;
  final int cashRevenueCents;
  final int cardRevenueCents;
  final bool hasMoreData;

  const _RevenueFetchResult({
    required this.rows,
    required this.totalCount,
    required this.totalRevenueCents,
    required this.cashRevenueCents,
    required this.cardRevenueCents,
    required this.hasMoreData,
  });
}

// Dashboard-style StatCard with emoji icons
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String icon; // Emoji icon
  final Color color;
  final bool isCompact;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Gradient Background
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color.withOpacity(0.05), color.withOpacity(0.02)],
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: isCompact
                  ? Row(
                      children: [
                        // Icon Container
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              icon,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Value and Title
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                value,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Icon Container
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              icon,
                              style: const TextStyle(fontSize: 24),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Value
                        Text(
                          value,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Title Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Filter Bottom Sheet
class _FilterBottomSheet extends StatefulWidget {
  final String? selectedGymId;
  final String paymentMethodFilter;
  final String? selectedPlanId;
  final String amountFilter;
  final String deletedStatusFilter;
  final DateTime? customDateStart;
  final DateTime? customDateEnd;
  final List<Map<String, String>> gyms;
  final List<Map<String, String>> membershipPlans;
  final Function(String?, String, String?, String, String, DateTime?, DateTime?)
  onApplyFilters;
  final VoidCallback onClearFilters;

  const _FilterBottomSheet({
    required this.selectedGymId,
    required this.paymentMethodFilter,
    required this.selectedPlanId,
    required this.amountFilter,
    required this.deletedStatusFilter,
    required this.customDateStart,
    required this.customDateEnd,
    required this.gyms,
    required this.membershipPlans,
    required this.onApplyFilters,
    required this.onClearFilters,
  });

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late String? _selectedGymId;
  late String _paymentMethodFilter;
  late String? _selectedPlanId;
  late String _amountFilter;
  late String _deletedStatusFilter;
  late DateTime? _customDateStart;
  late DateTime? _customDateEnd;

  @override
  void initState() {
    super.initState();
    _selectedGymId = widget.selectedGymId;
    _paymentMethodFilter = widget.paymentMethodFilter;
    _selectedPlanId = widget.selectedPlanId;
    _amountFilter = widget.amountFilter;
    _deletedStatusFilter = widget.deletedStatusFilter;
    _customDateStart = widget.customDateStart;
    _customDateEnd = widget.customDateEnd;
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customDateStart != null && _customDateEnd != null
          ? DateTimeRange(start: _customDateStart!, end: _customDateEnd!)
          : null,
    );

    if (picked != null && mounted) {
      setState(() {
        _customDateStart = picked.start;
        _customDateEnd = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          margin: const EdgeInsets.only(top: 120),
          child: DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Title
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Filtre',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          TextButton(
                            onPressed: () {
                              widget.onClearFilters();
                              Navigator.pop(context);
                            },
                            child: const Text('Resetează'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Filter Content
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Gym Filter
                          Text(
                            'Sală',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                label: const Text('Toate'),
                                selected: _selectedGymId == null,
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() => _selectedGymId = null);
                                  }
                                },
                              ),
                              ...widget.gyms.map((gym) {
                                final isSelected = _selectedGymId == gym['id'];
                                return FilterChip(
                                  label: Text(gym['name']!),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    if (mounted) {
                                      setState(() {
                                        _selectedGymId = selected
                                            ? gym['id']
                                            : null;
                                      });
                                    }
                                  },
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Payment Method Filter
                          Text(
                            'Metoda de Plată',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                label: const Text('Toate'),
                                selected: _paymentMethodFilter == 'all',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(
                                      () => _paymentMethodFilter = 'all',
                                    );
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('💵 Cash'),
                                selected: _paymentMethodFilter == 'cash',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(
                                      () => _paymentMethodFilter = 'cash',
                                    );
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('💳 Card'),
                                selected: _paymentMethodFilter == 'card',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(
                                      () => _paymentMethodFilter = 'card',
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Amount Filter
                          Text(
                            'Filtrează după sumă',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                label: const Text('Toate'),
                                selected: _amountFilter == 'all',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() => _amountFilter = 'all');
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('Doar 0 RON'),
                                selected: _amountFilter == 'zero',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() => _amountFilter = 'zero');
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('Peste 0 RON'),
                                selected: _amountFilter == 'non_zero',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() => _amountFilter = 'non_zero');
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Deleted Status Filter
                          Text(
                            'Status Ștergere',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                label: const Text('Toate'),
                                selected: _deletedStatusFilter == 'all',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(
                                      () => _deletedStatusFilter = 'all',
                                    );
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('Șterse'),
                                selected: _deletedStatusFilter == 'deleted',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(
                                      () => _deletedStatusFilter = 'deleted',
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Membership Plan Filter
                          Text(
                            'Plan Abonament',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _selectedPlanId,
                            decoration: const InputDecoration(
                              labelText: 'Selectează plan',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Toate planurile'),
                              ),
                              ...widget.membershipPlans.map((plan) {
                                return DropdownMenuItem(
                                  value: plan['id'],
                                  child: Text(plan['name']!),
                                );
                              }),
                            ],
                            onChanged: (value) {
                              if (mounted) {
                                setState(() => _selectedPlanId = value);
                              }
                            },
                          ),
                          const SizedBox(height: 24),

                          // Custom Date Range
                          Text(
                            'Perioadă Personalizată',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _selectDateRange,
                            icon: const Icon(Icons.date_range),
                            label: Text(
                              _customDateStart != null && _customDateEnd != null
                                  ? '${DateFormat('dd MMM yyyy').format(_customDateStart!)} - ${DateFormat('dd MMM yyyy').format(_customDateEnd!)}'
                                  : 'Selectează perioadă',
                            ),
                          ),
                          if (_customDateStart != null &&
                              _customDateEnd != null) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                if (mounted) {
                                  setState(() {
                                    _customDateStart = null;
                                    _customDateEnd = null;
                                  });
                                }
                              },
                              icon: const Icon(Icons.clear),
                              label: const Text('Șterge perioada'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Apply Button
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              widget.onApplyFilters(
                                _selectedGymId,
                                _paymentMethodFilter,
                                _selectedPlanId,
                                _amountFilter,
                                _deletedStatusFilter,
                                _customDateStart,
                                _customDateEnd,
                              );
                              Navigator.pop(context);
                            },
                            child: const Text('Aplică Filtre'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// Edit Transaction Dialog
class _EditTransactionDialog extends StatefulWidget {
  final RevenueLedger entry;
  final List<Map<String, String>> gyms;
  final List<Map<String, String>> membershipPlans;

  const _EditTransactionDialog({
    required this.entry,
    required this.gyms,
    required this.membershipPlans,
  });

  @override
  State<_EditTransactionDialog> createState() => _EditTransactionDialogState();
}

class _EditTransactionDialogState extends State<_EditTransactionDialog> {
  late TextEditingController _amountController;
  late TextEditingController _notesController;
  late String _paymentMethod;
  late String? _selectedGymId;
  late String? _selectedPlanId;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: (widget.entry.amountCents / 100).toStringAsFixed(2),
    );
    _notesController = TextEditingController(text: widget.entry.notes ?? '');
    _paymentMethod = widget.entry.paymentMethod;
    _selectedGymId = widget.entry.gym?.id;
    _selectedPlanId = widget.entry.membershipPlan?.id;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editează Tranzacție'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Amount field
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Suma (RON)',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),

            // Payment method
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Metodă de Plată',
                prefixIcon: Icon(Icons.payment),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('💵 Cash')),
                DropdownMenuItem(value: 'card', child: Text('💳 Card')),
              ],
              onChanged: (value) {
                if (value != null) {
                  if (mounted) setState(() => _paymentMethod = value);
                }
              },
            ),
            const SizedBox(height: 16),

            // Gym selection
            DropdownButtonFormField<String>(
              value: _selectedGymId,
              decoration: const InputDecoration(
                labelText: 'Sală',
                prefixIcon: Icon(Icons.fitness_center),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Niciuna')),
                ...widget.gyms.map((gym) {
                  return DropdownMenuItem(
                    value: gym['id'],
                    child: Text(gym['name']!),
                  );
                }),
              ],
              onChanged: (value) {
                if (mounted) setState(() => _selectedGymId = value);
              },
            ),
            const SizedBox(height: 16),

            // Membership plan selection
            DropdownButtonFormField<String>(
              value: _selectedPlanId,
              decoration: const InputDecoration(
                labelText: 'Plan Abonament',
                prefixIcon: Icon(Icons.card_membership),
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Niciun plan')),
                ...widget.membershipPlans.map((plan) {
                  return DropdownMenuItem(
                    value: plan['id'],
                    child: Text(plan['name']!),
                  );
                }),
              ],
              onChanged: (value) {
                if (mounted) setState(() => _selectedPlanId = value);
              },
            ),
            const SizedBox(height: 16),

            // Notes field
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notițe (opțional)',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anulează'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amountController.text);
            if (amount == null || amount <= 0) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Suma invalidă')));
              return;
            }

            final updates = {
              'amount_cents': (amount * 100).round(),
              'payment_method': _paymentMethod,
              'gym_id': _selectedGymId,
              'plan_id': _selectedPlanId,
              'notes': _notesController.text.isEmpty
                  ? null
                  : _notesController.text,
            };

            Navigator.of(context).pop(updates);
          },
          child: const Text('Salvează'),
        ),
      ],
    );
  }
}

// Period Tab Widget
class _PeriodTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeriodTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
