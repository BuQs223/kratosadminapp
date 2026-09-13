import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/powersync_service.dart';
import 'period_comparison_screen.dart';

class RevenueAnalyticsScreen extends StatefulWidget {
  const RevenueAnalyticsScreen({super.key});

  @override
  State<RevenueAnalyticsScreen> createState() => _RevenueAnalyticsScreenState();
}

class _RevenueAnalyticsScreenState extends State<RevenueAnalyticsScreen> {
  bool _isLoading = true;

  // Filter state
  String? _selectedGymId;
  String _timeRange = '30days'; // 7days, 30days, 90days, year, all
  DateTime? _customDateStart;
  DateTime? _customDateEnd;
  final List<Map<String, String>> _gyms = [];

  // Analytics data
  List<Map<String, dynamic>> _revenueByPlan = [];
  List<Map<String, dynamic>> _revenueByGym = [];
  List<Map<String, dynamic>> _revenueTrend = [];
  Map<String, double> _totalStats = {
    'total': 0,
    'cash': 0,
    'card': 0,
    'avgTransaction': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadGyms();
    _loadAnalytics();
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

  DateTime _getStartDateForTimeRange() {
    final now = DateTime.now();
    switch (_timeRange) {
      case '7days':
        return now.subtract(const Duration(days: 7));
      case '30days':
        return now.subtract(const Duration(days: 30));
      case '90days':
        return now.subtract(const Duration(days: 90));
      case 'year':
        return DateTime(now.year, 1, 1);
      case 'all':
        return DateTime(2020, 1, 1);
      case 'custom':
        return _customDateStart ?? now.subtract(const Duration(days: 30));
      default:
        return now.subtract(const Duration(days: 30));
    }
  }

  DateTime _getEndDateForTimeRange() {
    if (_timeRange == 'custom' && _customDateEnd != null) {
      return DateTime(
        _customDateEnd!.year,
        _customDateEnd!.month,
        _customDateEnd!.day,
        23,
        59,
        59,
        999,
      );
    }
    return DateTime.now();
  }

  String _getTrendInterval() {
    // Custom ranges are easier to understand with daily buckets.
    if (_timeRange == '7days' || _timeRange == 'custom') {
      return 'day';
    }
    return 'week';
  }

  String _buildRevenueWhereClause({
    required DateTime startDate,
    required DateTime endDate,
    required List<Object?> params,
    bool includeGymFilter = true,
  }) {
    final clauses = <String>[
      "r.entry_kind = 'charge'",
      'COALESCE(r.is_deleted, 0) = 0',
      'datetime(r.paid_at) >= datetime(?)',
      'datetime(r.paid_at) <= datetime(?)',
    ];
    params.addAll([startDate.toIso8601String(), endDate.toIso8601String()]);

    if (includeGymFilter && _selectedGymId != null) {
      clauses.add('r.gym_id = ?');
      params.add(_selectedGymId);
    }

    return 'WHERE ${clauses.join(' AND ')}';
  }

  String _revenueByPlanSql(String whereClause) {
    return '''
      SELECT
        COALESCE(mp.name, 'Fără plan') AS plan_name,
        COALESCE(SUM(r.amount_cents), 0) AS total_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'cash' THEN r.amount_cents ELSE 0 END), 0) AS cash_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'card' THEN r.amount_cents ELSE 0 END), 0) AS card_revenue,
        COUNT(*) AS transaction_count
      FROM revenue_ledger r
      LEFT JOIN membership_plans mp ON mp.id = r.plan_id
      $whereClause
      GROUP BY COALESCE(r.plan_id, ''), COALESCE(mp.name, 'Fără plan')
      ORDER BY total_revenue DESC
    ''';
  }

  String _revenueByGymSql(String whereClause) {
    return '''
      SELECT
        COALESCE(g.name, 'Fără sală') AS gym_name,
        COALESCE(SUM(r.amount_cents), 0) AS total_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'cash' THEN r.amount_cents ELSE 0 END), 0) AS cash_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'card' THEN r.amount_cents ELSE 0 END), 0) AS card_revenue,
        COUNT(*) AS transaction_count
      FROM revenue_ledger r
      LEFT JOIN gyms g ON g.id = r.gym_id
      $whereClause
      GROUP BY COALESCE(r.gym_id, ''), COALESCE(g.name, 'Fără sală')
      ORDER BY total_revenue DESC
    ''';
  }

  String _revenueTrendSql(String whereClause) {
    final periodExpression = _getTrendInterval() == 'day'
        ? 'date(r.paid_at)'
        : "date(r.paid_at, '-' || ((CAST(strftime('%w', r.paid_at) AS INTEGER) + 6) % 7) || ' days')";

    return '''
      SELECT
        $periodExpression AS period,
        COALESCE(SUM(r.amount_cents), 0) AS total_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'cash' THEN r.amount_cents ELSE 0 END), 0) AS cash_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'card' THEN r.amount_cents ELSE 0 END), 0) AS card_revenue,
        COUNT(*) AS transaction_count
      FROM revenue_ledger r
      $whereClause
      GROUP BY period
      ORDER BY datetime(period) ASC
    ''';
  }

  Future<void> _loadAnalytics() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      await PowerSyncService.connectIfAuthenticated();
      final startDate = _getStartDateForTimeRange();
      final endDate = _getEndDateForTimeRange();
      final filteredParams = <Object?>[];
      final filteredWhereClause = _buildRevenueWhereClause(
        startDate: startDate,
        endDate: endDate,
        params: filteredParams,
      );
      final gymParams = <Object?>[];
      final gymWhereClause = _buildRevenueWhereClause(
        startDate: startDate,
        endDate: endDate,
        params: gymParams,
        includeGymFilter: false,
      );

      final results = await Future.wait<List<Map<String, dynamic>>>([
        PowerSyncService.db.getAll(
          _revenueByPlanSql(filteredWhereClause),
          filteredParams,
        ),
        PowerSyncService.db.getAll(_revenueByGymSql(gymWhereClause), gymParams),
        PowerSyncService.db.getAll(
          _revenueTrendSql(filteredWhereClause),
          filteredParams,
        ),
      ]);

      final planData = results[0];
      final gymData = results[1];
      final trendData = results[2];

      // Calculate total stats
      double total = 0;
      double cash = 0;
      double card = 0;
      int transactionCount = 0;

      for (var item in trendData) {
        total += (item['total_revenue'] as num).toDouble() / 100;
        cash += (item['cash_revenue'] as num).toDouble() / 100;
        card += (item['card_revenue'] as num).toDouble() / 100;
        transactionCount += (item['transaction_count'] as num).toInt();
      }

      if (mounted) {
        setState(() {
          _revenueByPlan = planData;
          _revenueByGym = gymData;
          _revenueTrend = trendData;
          _totalStats = {
            'total': total,
            'cash': cash,
            'card': card,
            'avgTransaction': transactionCount > 0
                ? total / transactionCount
                : 0,
          };
          _isLoading = false;
        });
      }
    } catch (error) {
      print('Error loading analytics: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la încărcarea datelor: $error')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AnalyticsFilterBottomSheet(
        selectedGymId: _selectedGymId,
        timeRange: _timeRange,
        customDateStart: _customDateStart,
        customDateEnd: _customDateEnd,
        gyms: _gyms,
        onApplyFilters: (gymId, timeRange, dateStart, dateEnd) {
          if (mounted) {
            setState(() {
              _selectedGymId = gymId;
              _timeRange = timeRange;
              _customDateStart = dateStart;
              _customDateEnd = dateEnd;
            });
          }
          _loadAnalytics();
        },
        onClearFilters: () {
          if (mounted) {
            setState(() {
              _selectedGymId = null;
              _timeRange = '30days';
              _customDateStart = null;
              _customDateEnd = null;
            });
          }
          _loadAnalytics();
        },
      ),
    );
  }

  int get _activeFiltersCount {
    int count = 0;
    if (_selectedGymId != null) count++;
    if (_timeRange != '30days') count++;
    return count;
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(
      symbol: 'RON ',
      decimalDigits: 2,
    ).format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analiză Venituri'),
        actions: [
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
              onRefresh: _loadAnalytics,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Quick Actions
                  _buildQuickActions(),
                  const SizedBox(height: 24),

                  // Summary Stats
                  _buildSummaryStats(),
                  const SizedBox(height: 24),

                  // Revenue Trend Chart
                  _buildSectionHeader('Tendință Venituri'),
                  const SizedBox(height: 12),
                  _buildRevenueTrendChart(),
                  const SizedBox(height: 24),

                  // Revenue by Plan Chart
                  _buildSectionHeader('Venituri pe Plan'),
                  const SizedBox(height: 12),
                  _buildRevenueByPlanChart(),
                  const SizedBox(height: 24),

                  // Revenue by Gym Chart
                  _buildSectionHeader('Venituri pe Sală'),
                  const SizedBox(height: 12),
                  _buildRevenueByGymChart(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildQuickActions() {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const PeriodComparisonScreen(),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.compare_arrows,
                color: Colors.deepPurple.shade700,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comparație Perioade',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Compară veniturile între două perioade diferite',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.deepPurple.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStats() {
    return Column(
      children: [
        _StatCard(
          title: 'Total',
          value: _formatCurrency(_totalStats['total']!),
          icon: '💰',
          color: const Color(0xFF8E24AA),
        ),
        const SizedBox(height: 6),
        _StatCard(
          title: 'Cash',
          value: _formatCurrency(_totalStats['cash']!),
          icon: '💵',
          color: const Color(0xFF43A047),
        ),
        const SizedBox(height: 6),
        _StatCard(
          title: 'Card',
          value: _formatCurrency(_totalStats['card']!),
          icon: '💳',
          color: const Color(0xFF1E88E5),
        ),
      ],
    );
  }

  Widget _buildRevenueTrendChart() {
    if (_revenueTrend.isEmpty) {
      return _buildEmptyState('Nicio dată disponibilă');
    }

    final spots = _revenueTrend.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final revenue = (item['total_revenue'] as num).toDouble() / 100;
      return FlSpot(index.toDouble(), revenue);
    }).toList();

    // Calculate max for better scaling
    final maxRevenue = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    final trendInterval = _getTrendInterval();
    final isDaily = trendInterval == 'day';

    // Show only every nth label to avoid crowding
    final showEveryNth = _revenueTrend.length > 10
        ? 3
        : (_revenueTrend.length > 7 ? 2 : 1);

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
            // Info text explaining the graph
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF8E24AA).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Color(0xFF8E24AA),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isDaily
                          ? 'Fiecare punct = venit pentru ziua respectivă'
                          : 'Fiecare punct = total pe săptămână (Lun-Dum). Ultimul punct poate fi săptămână parțială.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF8E24AA),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 280,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    verticalInterval: 1,
                    horizontalInterval: maxRevenue / 4,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withOpacity(0.3),
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withOpacity(0.3),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 70,
                        interval: maxRevenue / 4,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox();
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              NumberFormat.compact(locale: 'ro').format(value),
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.right,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= _revenueTrend.length || index < 0) {
                            return const SizedBox();
                          }

                          // Show only every nth label
                          if (index % showEveryNth != 0) {
                            return const SizedBox();
                          }

                          final item = _revenueTrend[index];
                          final periodStart = DateTime.parse(
                            item['period'] as String,
                          );
                          final periodEnd = periodStart.add(
                            const Duration(days: 6),
                          );

                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Transform.rotate(
                              angle: -0.5,
                              child: Text(
                                isDaily
                                    ? DateFormat('dd MMM').format(periodStart)
                                    : '${DateFormat('dd/MM').format(periodStart)}-${DateFormat('dd/MM').format(periodEnd)}',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(fontSize: 10),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      bottom: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  minY: 0,
                  maxY: maxRevenue * 1.1, // Add 10% padding
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: const Color(0xFF8E24AA),
                      barWidth: 4,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Colors.white,
                            strokeWidth: 2,
                            strokeColor: const Color(0xFF8E24AA),
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF8E24AA).withOpacity(0.3),
                            const Color(0xFF8E24AA).withOpacity(0.05),
                          ],
                        ),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    enabled: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final item = _revenueTrend[spot.x.toInt()];
                          final periodStart = DateTime.parse(
                            item['period'] as String,
                          );
                          final periodEnd = periodStart.add(
                            const Duration(days: 6),
                          );
                          final revenue = spot.y;

                          return LineTooltipItem(
                            isDaily
                                ? '${DateFormat('dd MMM yyyy').format(periodStart)}\n${_formatCurrency(revenue)}'
                                : '${DateFormat('dd MMM').format(periodStart)} - ${DateFormat('dd MMM yyyy').format(periodEnd)}\n${_formatCurrency(revenue)}',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueByPlanChart() {
    if (_revenueByPlan.isEmpty) {
      return _buildEmptyState('Nicio dată disponibilă');
    }

    // Sort by revenue descending and take top 5
    final topPlans =
        ([..._revenueByPlan]..sort(
              (a, b) => (b['total_revenue'] as num).compareTo(
                a['total_revenue'] as num,
              ),
            ))
            
            .toList();

    final maxRevenue = topPlans.isEmpty
        ? 0.0
        : (topPlans.first['total_revenue'] as num).toDouble() / 100;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: topPlans.map((plan) {
            final name = plan['plan_name'] as String? ?? 'Unknown';
            final revenue = (plan['total_revenue'] as num).toDouble() / 100;
            final count = plan['transaction_count'] as num;
            final percentage = maxRevenue > 0 ? (revenue / maxRevenue) : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatCurrency(revenue),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF8E24AA),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage,
                      minHeight: 8,
                      backgroundColor: const Color(0xFF8E24AA).withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF8E24AA),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count tranzacții',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRevenueByGymChart() {
    if (_revenueByGym.isEmpty) {
      return _buildEmptyState('Nicio dată disponibilă');
    }

    final colors = [
      const Color(0xFF8E24AA),
      const Color(0xFF43A047),
      const Color(0xFF1E88E5),
      const Color(0xFFFB8C00),
      const Color(0xFFE53935),
    ];

    final sections = _revenueByGym.asMap().entries.map((entry) {
      final index = entry.key;
      final gym = entry.value;
      final revenue = (gym['total_revenue'] as num).toDouble() / 100;
      final color = colors[index % colors.length];

      return PieChartSectionData(
        value: revenue,
        title: _formatCurrency(revenue),
        color: color,
        radius: 100,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          left: 24,
          right: 24,
          top: 40,
          bottom: 24,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 250,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 40,
                  sectionsSpace: 6,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: _revenueByGym.asMap().entries.map((entry) {
                final index = entry.key;
                final gym = entry.value;
                final name = gym['gym_name'] as String? ?? 'Unknown';
                final color = colors[index % colors.length];

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(name, style: Theme.of(context).textTheme.bodySmall),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
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
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.05), color.withOpacity(0.02)],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
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
        ),
      ),
    );
  }
}

// Filter Bottom Sheet for Analytics
class _AnalyticsFilterBottomSheet extends StatefulWidget {
  final String? selectedGymId;
  final String timeRange;
  final DateTime? customDateStart;
  final DateTime? customDateEnd;
  final List<Map<String, String>> gyms;
  final Function(String?, String, DateTime?, DateTime?) onApplyFilters;
  final VoidCallback onClearFilters;

  const _AnalyticsFilterBottomSheet({
    required this.selectedGymId,
    required this.timeRange,
    required this.customDateStart,
    required this.customDateEnd,
    required this.gyms,
    required this.onApplyFilters,
    required this.onClearFilters,
  });

  @override
  State<_AnalyticsFilterBottomSheet> createState() =>
      _AnalyticsFilterBottomSheetState();
}

class _AnalyticsFilterBottomSheetState
    extends State<_AnalyticsFilterBottomSheet> {
  late String? _selectedGymId;
  late String _timeRange;
  late DateTime? _customDateStart;
  late DateTime? _customDateEnd;

  @override
  void initState() {
    super.initState();
    _selectedGymId = widget.selectedGymId;
    _timeRange = widget.timeRange;
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
        _timeRange = 'custom';
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
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.7,
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
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Filtre Analiză',
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
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(
                            'Perioadă',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                label: const Text('7 zile'),
                                selected: _timeRange == '7days',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() => _timeRange = '7days');
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('30 zile'),
                                selected: _timeRange == '30days',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() => _timeRange = '30days');
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('90 zile'),
                                selected: _timeRange == '90days',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() => _timeRange = '90days');
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('An curent'),
                                selected: _timeRange == 'year',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() => _timeRange = 'year');
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('Tot timpul'),
                                selected: _timeRange == 'all',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() => _timeRange = 'all');
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _selectDateRange,
                            icon: const Icon(Icons.date_range),
                            label: Text(
                              _timeRange == 'custom' &&
                                      _customDateStart != null &&
                                      _customDateEnd != null
                                  ? '${DateFormat('dd MMM yyyy').format(_customDateStart!)} - ${DateFormat('dd MMM yyyy').format(_customDateEnd!)}'
                                  : 'Perioadă personalizată',
                            ),
                          ),
                          const SizedBox(height: 24),
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
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              widget.onApplyFilters(
                                _selectedGymId,
                                _timeRange,
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
