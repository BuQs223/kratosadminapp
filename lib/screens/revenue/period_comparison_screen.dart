import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/powersync_service.dart';

class PeriodComparisonScreen extends StatefulWidget {
  const PeriodComparisonScreen({super.key});

  @override
  State<PeriodComparisonScreen> createState() => _PeriodComparisonScreenState();
}

class _PeriodComparisonScreenState extends State<PeriodComparisonScreen> {
  static const _dayPassPlanIds = [
    '52f9fa66-b839-4855-936a-25e0f46165de',
    '01095869-f243-4b8c-a8ff-9730ac3ad044',
  ];

  bool _isLoading = true;
  String? _selectedGymId;
  final List<Map<String, String>> _gyms = [];

  // Period A (current/left)
  String _periodAType = 'this_month'; // this_month, this_week, custom
  DateTime? _periodAStart;
  DateTime? _periodAEnd;
  Map<String, dynamic>? _periodAStats;

  // Period B (comparison/right)
  String _periodBType = 'last_month'; // last_month, last_week, custom
  DateTime? _periodBStart;
  DateTime? _periodBEnd;
  Map<String, dynamic>? _periodBStats;

  @override
  void initState() {
    super.initState();
    _initializePeriods();
    _loadGyms();
    _loadComparison();
  }

  void _initializePeriods() {
    final now = DateTime.now();

    // Period A: This month
    _periodAStart = DateTime(now.year, now.month, 1);
    _periodAEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    // Period B: Last month
    _periodBStart = DateTime(now.year, now.month - 1, 1);
    _periodBEnd = DateTime(now.year, now.month, 0, 23, 59, 59);
  }

  void _updatePeriodDates() {
    final now = DateTime.now();

    switch (_periodAType) {
      case 'this_month':
        _periodAStart = DateTime(now.year, now.month, 1);
        _periodAEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        break;
      case 'this_week':
        final weekday = now.weekday;
        _periodAStart = now.subtract(Duration(days: weekday - 1));
        _periodAStart = DateTime(
          _periodAStart!.year,
          _periodAStart!.month,
          _periodAStart!.day,
        );
        _periodAEnd = _periodAStart!.add(
          const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
        );
        break;
      case 'this_year':
        _periodAStart = DateTime(now.year, 1, 1);
        _periodAEnd = DateTime(now.year, 12, 31, 23, 59, 59);
        break;
      case 'custom':
        // Keep existing custom dates
        break;
    }

    switch (_periodBType) {
      case 'last_month':
        _periodBStart = DateTime(now.year, now.month - 1, 1);
        _periodBEnd = DateTime(now.year, now.month, 0, 23, 59, 59);
        break;
      case 'last_week':
        final weekday = now.weekday;
        final thisWeekStart = now.subtract(Duration(days: weekday - 1));
        _periodBStart = thisWeekStart.subtract(const Duration(days: 7));
        _periodBStart = DateTime(
          _periodBStart!.year,
          _periodBStart!.month,
          _periodBStart!.day,
        );
        _periodBEnd = _periodBStart!.add(
          const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
        );
        break;
      case 'last_year':
        _periodBStart = DateTime(now.year - 1, 1, 1);
        _periodBEnd = DateTime(now.year - 1, 12, 31, 23, 59, 59);
        break;
      case 'custom':
        // Keep existing custom dates
        break;
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
      debugPrint('Error loading gyms: $error');
    }
  }

  String _buildRevenueWhereClause({
    required DateTime? start,
    required DateTime? end,
    required List<Object?> params,
  }) {
    final clauses = <String>["r.entry_kind = 'charge'"];

    if (_selectedGymId != null) {
      clauses.add('r.gym_id = ?');
      params.add(_selectedGymId);
    }
    if (start != null) {
      clauses.add('datetime(r.paid_at) >= datetime(?)');
      params.add(start.toIso8601String());
    }
    if (end != null) {
      clauses.add('datetime(r.paid_at) <= datetime(?)');
      params.add(end.toIso8601String());
    }

    return 'WHERE ${clauses.join(' AND ')}';
  }

  Future<Map<String, dynamic>> _fetchPeriodStats(
    DateTime? start,
    DateTime? end,
  ) async {
    final params = <Object?>[];
    final whereClause = _buildRevenueWhereClause(
      start: start,
      end: end,
      params: params,
    );

    final statsRow = await PowerSyncService.db.get(
      '''
      SELECT
        COALESCE(SUM(r.amount_cents), 0) AS total_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'cash' THEN r.amount_cents ELSE 0 END), 0) AS cash_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'card' THEN r.amount_cents ELSE 0 END), 0) AS card_revenue,
        COUNT(*) AS transaction_count,
        COALESCE(AVG(r.amount_cents), 0) AS avg_transaction,
        COUNT(DISTINCT m.user_id) AS unique_members,
        COUNT(CASE WHEN r.source = 'day_pass' THEN 1 END) AS day_pass_count,
        COUNT(CASE
          WHEN r.source IN ('membership', 'membership_sale')
            AND (r.plan_id IS NULL OR r.plan_id NOT IN (?, ?))
          THEN 1
        END) AS new_memberships_count,
        COUNT(CASE WHEN r.source = 'membership_extension' THEN 1 END) AS extensions_count,
        COUNT(CASE WHEN r.source = 'membership_upgrade' THEN 1 END) AS upgrades_count
      FROM revenue_ledger r
      LEFT JOIN memberships m ON m.id = r.membership_id
      $whereClause
    ''',
      [..._dayPassPlanIds, ...params],
    );

    final revenueByPlanRows = await PowerSyncService.db.getAll('''
      SELECT
        mp.name AS plan_name,
        COALESCE(SUM(r.amount_cents), 0) AS revenue,
        COUNT(*) AS count
      FROM revenue_ledger r
      JOIN membership_plans mp ON mp.id = r.plan_id
      $whereClause
        AND r.source <> 'product'
      GROUP BY mp.id, mp.name
      ORDER BY revenue DESC
    ''', params);

    return {
      ...Map<String, dynamic>.from(statsRow),
      'revenue_by_plan': revenueByPlanRows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
    };
  }

  Future<void> _loadComparison() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      await PowerSyncService.connectIfAuthenticated();

      // Load both periods in parallel
      final results = await Future.wait([
        _fetchPeriodStats(_periodAStart, _periodAEnd),
        _fetchPeriodStats(_periodBStart, _periodBEnd),
      ]);

      if (mounted) {
        final mergedA = Map<String, dynamic>.from(results[0] as Map);
        final mergedB = Map<String, dynamic>.from(results[1] as Map);

        setState(() {
          _periodAStats = mergedA;
          _periodBStats = mergedB;
          _isLoading = false;
        });
      }
    } catch (error) {
      debugPrint('Error loading comparison: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare: $error')));
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(
      symbol: 'RON ',
      decimalDigits: 2,
    ).format(amount);
  }

  String _formatPeriodName(String type, DateTime? start, DateTime? end) {
    switch (type) {
      case 'this_month':
        return 'Luna curentă';
      case 'last_month':
        return 'Luna trecută';
      case 'this_week':
        return 'Săptămâna curentă';
      case 'last_week':
        return 'Săptămâna trecută';
      case 'this_year':
        return 'Anul curent';
      case 'last_year':
        return 'Anul trecut';
      case 'custom':
        if (start != null && end != null) {
          return '${DateFormat('dd MMM').format(start)} - ${DateFormat('dd MMM').format(end)}';
        }
        return 'Personalizat';
      default:
        return type;
    }
  }

  double _calculatePercentChange(double current, double previous) {
    if (previous == 0) {
      return current > 0 ? 100 : 0;
    }
    return ((current - previous) / previous) * 100;
  }

  void _swapPeriods() {
    if (mounted) {
      // Swap dates
      final tempStart = _periodAStart;
      final tempEnd = _periodAEnd;
      _periodAStart = _periodBStart;
      _periodAEnd = _periodBEnd;
      _periodBStart = tempStart;
      _periodBEnd = tempEnd;

      // Set both to custom since the dates are now swapped
      // and the preset names wouldn't make sense anymore
      _periodAType = 'custom';
      _periodBType = 'custom';

      // Swap stats
      final tempStats = _periodAStats;
      _periodAStats = _periodBStats;
      _periodBStats = tempStats;
    }
  }

  Future<void> _selectCustomDateRange(bool isPeriodA) async {
    final now = DateTime.now();
    // Use end of current month as lastDate to allow selecting future dates within the month
    final lastDate = DateTime(now.year, now.month + 1, 0);

    // Get initial range, but clamp end date to lastDate if needed
    DateTimeRange? initialRange;
    if (isPeriodA && _periodAStart != null && _periodAEnd != null) {
      final clampedEnd = _periodAEnd!.isAfter(lastDate)
          ? lastDate
          : _periodAEnd!;
      initialRange = DateTimeRange(start: _periodAStart!, end: clampedEnd);
    } else if (!isPeriodA && _periodBStart != null && _periodBEnd != null) {
      final clampedEnd = _periodBEnd!.isAfter(lastDate)
          ? lastDate
          : _periodBEnd!;
      initialRange = DateTimeRange(start: _periodBStart!, end: clampedEnd);
    }

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: lastDate,
      initialDateRange: initialRange,
    );

    if (picked != null) {
      if (mounted) {
        if (isPeriodA) {
          _periodAType = 'custom';
          _periodAStart = picked.start;
          _periodAEnd = DateTime(
            picked.end.year,
            picked.end.month,
            picked.end.day,
            23,
            59,
            59,
          );
        } else {
          _periodBType = 'custom';
          _periodBStart = picked.start;
          _periodBEnd = DateTime(
            picked.end.year,
            picked.end.month,
            picked.end.day,
            23,
            59,
            59,
          );
        }
      }
      _loadComparison();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comparație Perioade')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadComparison,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Current gym indicator
                  _buildGymIndicator(),
                  const SizedBox(height: 16),

                  // Period Selectors
                  _buildPeriodSelectors(),
                  const SizedBox(height: 24),

                  // Comparison Summary Card
                  _buildComparisonSummary(),
                  const SizedBox(height: 16),

                  // Side by Side Stats
                  _buildSideBySideStats(),
                  const SizedBox(height: 16),

                  // Detailed Comparison
                  _buildDetailedComparison(),
                  const SizedBox(height: 16),

                  // Top Plan Comparison
                  _buildTopPlanComparison(),
                ],
              ),
            ),
    );
  }

  Widget _buildGymIndicator() {
    final gymName = _selectedGymId == null
        ? 'Toate Sălile'
        : _gyms.firstWhere(
            (g) => g['id'] == _selectedGymId,
            orElse: () => {'name': 'Necunoscut'},
          )['name']!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.fitness_center,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comparație pentru:',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  gymName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _showGymSelector(),
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Schimbă'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }

  void _showGymSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selectează Sala',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('Toate Sălile'),
              selected: _selectedGymId == null,
              onTap: () {
                Navigator.pop(context);
                if (mounted) setState(() => _selectedGymId = null);
                _loadComparison();
              },
            ),
            ..._gyms.map(
              (gym) => ListTile(
                leading: const Icon(Icons.fitness_center),
                title: Text(gym['name']!),
                selected: _selectedGymId == gym['id'],
                onTap: () {
                  Navigator.pop(context);
                  if (mounted) setState(() => _selectedGymId = gym['id']);
                  _loadComparison();
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelectors() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selectează Perioade',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildPeriodSelector(
                    label: 'Perioada A',
                    selectedType: _periodAType,
                    options: const [
                      ('this_month', 'Luna curentă'),
                      ('this_week', 'Săpt. curentă'),
                      ('this_year', 'Anul curent'),
                      ('custom', 'Personalizat'),
                    ],
                    onChanged: (type) {
                      if (mounted) setState(() => _periodAType = type);
                      _updatePeriodDates();
                      _loadComparison();
                    },
                    onCustomTap: () => _selectCustomDateRange(true),
                    color: const Color(0xFF8E24AA),
                  ),
                ),
                const SizedBox(width: 8),
                // Swap button
                Tooltip(
                  message: 'Inversează perioadele',
                  child: InkWell(
                    onTap: _swapPeriods,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.swap_horiz,
                        size: 24,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPeriodSelector(
                    label: 'Perioada B',
                    selectedType: _periodBType,
                    options: const [
                      ('last_month', 'Luna trecută'),
                      ('last_week', 'Săpt. trecută'),
                      ('last_year', 'Anul trecut'),
                      ('custom', 'Personalizat'),
                    ],
                    onChanged: (type) {
                      if (mounted) setState(() => _periodBType = type);
                      _updatePeriodDates();
                      _loadComparison();
                    },
                    onCustomTap: () => _selectCustomDateRange(false),
                    color: const Color(0xFF1E88E5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector({
    required String label,
    required String selectedType,
    required List<(String, String)> options,
    required ValueChanged<String> onChanged,
    required VoidCallback onCustomTap,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: color,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedType,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down, color: color),
              items: options.map((option) {
                return DropdownMenuItem(
                  value: option.$1,
                  child: Text(option.$2, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: (value) {
                if (value == 'custom') {
                  onCustomTap();
                } else if (value != null) {
                  onChanged(value);
                }
              },
            ),
          ),
        ),
        // Tap to change custom dates when already selected
        if (selectedType == 'custom')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: onCustomTap,
              child: Text(
                'Apasă pentru a schimba datele',
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildComparisonSummary() {
    if (_periodAStats == null || _periodBStats == null) {
      return const SizedBox.shrink();
    }

    final periodARevenue =
        ((_periodAStats!['total_revenue'] as num?) ?? 0) / 100;
    final periodBRevenue =
        ((_periodBStats!['total_revenue'] as num?) ?? 0) / 100;
    final difference = periodARevenue - periodBRevenue;
    final percentChange = _calculatePercentChange(
      periodARevenue,
      periodBRevenue,
    );
    final isPositive = difference >= 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isPositive
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
          width: 2,
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
                    Colors.green.withValues(alpha: 0.1),
                    Colors.green.withValues(alpha: 0.02),
                  ]
                : [
                    Colors.red.withValues(alpha: 0.1),
                    Colors.red.withValues(alpha: 0.02),
                  ],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isPositive ? Icons.trending_up : Icons.trending_down,
                  color: isPositive ? Colors.green : Colors.red,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  '${isPositive ? '+' : ''}${percentChange.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${isPositive ? '+' : ''}${_formatCurrency(difference)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isPositive ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatPeriodName(_periodAType, _periodAStart, _periodAEnd)} vs ${_formatPeriodName(_periodBType, _periodBStart, _periodBEnd)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideBySideStats() {
    return Row(
      children: [
        Expanded(
          child: _buildPeriodCard(
            title: _formatPeriodName(_periodAType, _periodAStart, _periodAEnd),
            stats: _periodAStats,
            color: const Color(0xFF8E24AA),
            dateRange: _periodAStart != null && _periodAEnd != null
                ? '${DateFormat('dd/MM').format(_periodAStart!)} - ${DateFormat('dd/MM').format(_periodAEnd!)}'
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildPeriodCard(
            title: _formatPeriodName(_periodBType, _periodBStart, _periodBEnd),
            stats: _periodBStats,
            color: const Color(0xFF1E88E5),
            dateRange: _periodBStart != null && _periodBEnd != null
                ? '${DateFormat('dd/MM').format(_periodBStart!)} - ${DateFormat('dd/MM').format(_periodBEnd!)}'
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodCard({
    required String title,
    required Map<String, dynamic>? stats,
    required Color color,
    String? dateRange,
  }) {
    if (stats == null) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('Nu sunt date')),
        ),
      );
    }

    final totalRevenue = ((stats['total_revenue'] as num?) ?? 0) / 100;
    final transactionCount = (stats['transaction_count'] as num?) ?? 0;
    final avgTransaction = ((stats['avg_transaction'] as num?) ?? 0) / 100;
    final uniqueMembers = (stats['unique_members'] as num?) ?? 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.08),
              color.withValues(alpha: 0.02),
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            if (dateRange != null) ...[
              const SizedBox(height: 4),
              Text(
                dateRange,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              _formatCurrency(totalRevenue),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildStatRow('Tranzacții', transactionCount.toString()),
            _buildStatRow('Media', _formatCurrency(avgTransaction)),
            _buildStatRow('Membri', uniqueMembers.toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showInfoBottomSheet(String title, String description) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Am înțeles'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedComparison() {
    if (_periodAStats == null || _periodBStats == null) {
      return const SizedBox.shrink();
    }

    // (label, valueA, valueB, isCurrency, infoText)
    final metrics = [
      (
        'Venit Total',
        ((_periodAStats!['total_revenue'] as num?) ?? 0) / 100,
        ((_periodBStats!['total_revenue'] as num?) ?? 0) / 100,
        true, // is currency
        null, // no info
      ),
      (
        'Cash',
        ((_periodAStats!['cash_revenue'] as num?) ?? 0) / 100,
        ((_periodBStats!['cash_revenue'] as num?) ?? 0) / 100,
        true,
        null,
      ),
      (
        'Card',
        ((_periodAStats!['card_revenue'] as num?) ?? 0) / 100,
        ((_periodBStats!['card_revenue'] as num?) ?? 0) / 100,
        true,
        null,
      ),
      (
        'Nr. Tranzacții',
        ((_periodAStats!['transaction_count'] as num?) ?? 0).toDouble(),
        ((_periodBStats!['transaction_count'] as num?) ?? 0).toDouble(),
        false,
        null,
      ),
      (
        'Media/Tranzacție',
        ((_periodAStats!['avg_transaction'] as num?) ?? 0) / 100,
        ((_periodBStats!['avg_transaction'] as num?) ?? 0) / 100,
        true,
        null,
      ),
      (
        'Membri Unici',
        ((_periodAStats!['unique_members'] as num?) ?? 0).toDouble(),
        ((_periodBStats!['unique_members'] as num?) ?? 0).toDouble(),
        false,
        'Numărul de persoane unice care au efectuat plăți în această perioadă.\n\nDacă un client a plătit de 3 ori, el este numărat o singură dată.\n\nAcest indicator arată câți clienți diferiți au fost activi (au plătit) în perioada selectată.',
      ),
      (
        'Abonamente Noi',
        ((_periodAStats!['new_memberships_count'] as num?) ?? 0).toDouble(),
        ((_periodBStats!['new_memberships_count'] as num?) ?? 0).toDouble(),
        false,
        'Numărul de abonamente noi vândute în această perioadă.\n\nInclude doar vânzările de abonamente noi, nu și extensiile sau upgrade-urile.',
      ),
      (
        'Extensii Abonamente',
        ((_periodAStats!['extensions_count'] as num?) ?? 0).toDouble(),
        ((_periodBStats!['extensions_count'] as num?) ?? 0).toDouble(),
        false,
        'Numărul de abonamente extinse în această perioadă.\n\nInclude doar prelungirile de abonamente existente.',
      ),
      (
        'Upgrade-uri',
        ((_periodAStats!['upgrades_count'] as num?) ?? 0).toDouble(),
        ((_periodBStats!['upgrades_count'] as num?) ?? 0).toDouble(),
        false,
        'Numărul de upgrade-uri de abonamente în această perioadă.\n\nInclude doar schimbările de la un plan la altul mai scump.',
      ),
      (
        'Intrări Zilnice',
        ((_periodAStats!['day_pass_count'] as num?) ?? 0).toDouble(),
        ((_periodBStats!['day_pass_count'] as num?) ?? 0).toDouble(),
        false,
        'Numărul de tichete de intrare zilnică (day pass) vândute în această perioadă.',
      ),
    ];

    const colorA = Color(0xFF8E24AA); // Purple for Period A
    const colorB = Color(0xFF1E88E5); // Blue for Period B

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Comparație Detaliată',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Legend
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colorA,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'A',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colorB,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'B',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...metrics.map((metric) {
              final label = metric.$1;
              final valueA = metric.$2;
              final valueB = metric.$3;
              final isCurrency = metric.$4;
              final infoText = metric.$5;
              final percentChange = _calculatePercentChange(valueA, valueB);
              final isPositive = percentChange >= 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (infoText != null) ...[
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () =>
                                    _showInfoBottomSheet(label, infoText),
                                child: Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isPositive
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPositive
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                size: 14,
                                color: isPositive ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${isPositive ? '+' : ''}${percentChange.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isPositive ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildDualProgressBar(
                      valueA: valueA,
                      valueB: valueB,
                      colorA: colorA,
                      colorB: colorB,
                      isCurrency: isCurrency,
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDualProgressBar({
    required double valueA,
    required double valueB,
    required Color colorA,
    required Color colorB,
    required bool isCurrency,
  }) {
    final total = valueA + valueB;
    final percentA = total > 0 ? (valueA / total) : 0.5;
    final percentB = total > 0 ? (valueB / total) : 0.5;

    final labelA = isCurrency
        ? _formatCurrency(valueA)
        : valueA.toInt().toString();
    final labelB = isCurrency
        ? _formatCurrency(valueB)
        : valueB.toInt().toString();

    return Column(
      children: [
        // Single stacked progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 24,
            child: Row(
              children: [
                // Period A segment
                Expanded(
                  flex: (percentA * 1000).round().clamp(1, 999),
                  child: Container(color: colorA),
                ),
                // Period B segment
                Expanded(
                  flex: (percentB * 1000).round().clamp(1, 999),
                  child: Container(color: colorB),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Labels below the bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Period A label (left aligned)
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colorA,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$labelA (${(percentA * 100).toStringAsFixed(0)}%)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorA,
                  ),
                ),
              ],
            ),
            // Period B label (right aligned)
            Row(
              children: [
                Text(
                  '$labelB (${(percentB * 100).toStringAsFixed(0)}%)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorB,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colorB,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopPlanComparison() {
    if (_periodAStats == null || _periodBStats == null) {
      return const SizedBox.shrink();
    }

    final revenueByPlanA =
        _periodAStats!['revenue_by_plan'] as List<dynamic>? ?? [];
    final revenueByPlanB =
        _periodBStats!['revenue_by_plan'] as List<dynamic>? ?? [];

    // Get top plan for each period
    final topPlanA = revenueByPlanA.isNotEmpty ? revenueByPlanA.first : null;
    final topPlanB = revenueByPlanB.isNotEmpty ? revenueByPlanB.first : null;

    const colorA = Color(0xFF8E24AA);
    const colorB = Color(0xFF1E88E5);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Cel Mai Vândut Plan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Period A Top Plan
                Expanded(
                  child: _buildTopPlanCard(
                    periodLabel: 'Perioada A',
                    planName: topPlanA?['plan_name'] ?? 'N/A',
                    revenue: ((topPlanA?['revenue'] as num?) ?? 0) / 100,
                    count: (topPlanA?['count'] as num?)?.toInt() ?? 0,
                    color: colorA,
                  ),
                ),
                const SizedBox(width: 12),
                // Period B Top Plan
                Expanded(
                  child: _buildTopPlanCard(
                    periodLabel: 'Perioada B',
                    planName: topPlanB?['plan_name'] ?? 'N/A',
                    revenue: ((topPlanB?['revenue'] as num?) ?? 0) / 100,
                    count: (topPlanB?['count'] as num?)?.toInt() ?? 0,
                    color: colorB,
                  ),
                ),
              ],
            ),
            // Show all plans button
            if (revenueByPlanA.length > 1 || revenueByPlanB.length > 1) ...[
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: () =>
                      _showAllPlansComparison(revenueByPlanA, revenueByPlanB),
                  icon: const Icon(Icons.list, size: 18),
                  label: const Text('Vezi toate planurile'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAllPlansComparison(List<dynamic> plansA, List<dynamic> plansB) {
    const colorA = Color(0xFF8E24AA);
    const colorB = Color(0xFF1E88E5);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Vânzări pe Plan',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Legend
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colorA,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Perioada A',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorA,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colorB,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Perioada B',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorB,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              // Plans list
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    // Period A plans
                    if (plansA.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Perioada A',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorA,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      ...plansA.asMap().entries.map((entry) {
                        final index = entry.key;
                        final plan = entry.value;
                        final planName = plan['plan_name'] ?? 'N/A';
                        final revenue = ((plan['revenue'] as num?) ?? 0) / 100;
                        final count = (plan['count'] as num?)?.toInt() ?? 0;
                        final isTop = index == 0;

                        return _buildPlanListItem(
                          rank: index + 1,
                          planName: planName,
                          revenue: revenue,
                          count: count,
                          color: colorA,
                          isTop: isTop,
                        );
                      }),
                    ],
                    const SizedBox(height: 16),
                    // Period B plans
                    if (plansB.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Perioada B',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorB,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      ...plansB.asMap().entries.map((entry) {
                        final index = entry.key;
                        final plan = entry.value;
                        final planName = plan['plan_name'] ?? 'N/A';
                        final revenue = ((plan['revenue'] as num?) ?? 0) / 100;
                        final count = (plan['count'] as num?)?.toInt() ?? 0;
                        final isTop = index == 0;

                        return _buildPlanListItem(
                          rank: index + 1,
                          planName: planName,
                          revenue: revenue,
                          count: count,
                          color: colorB,
                          isTop: isTop,
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanListItem({
    required int rank,
    required String planName,
    required double revenue,
    required int count,
    required Color color,
    required bool isTop,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isTop
            ? color.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: isTop ? Border.all(color: color.withValues(alpha: 0.3)) : null,
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isTop ? Colors.amber : Colors.grey.shade300,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isTop ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Plan details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  planName,
                  style: TextStyle(
                    fontWeight: isTop ? FontWeight.bold : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count vânzări',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Revenue
          Text(
            _formatCurrency(revenue),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPlanCard({
    required String periodLabel,
    required String planName,
    required double revenue,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            periodLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            planName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            _formatCurrency(revenue),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count vânzări',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
