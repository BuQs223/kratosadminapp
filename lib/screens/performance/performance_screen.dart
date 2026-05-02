import 'package:flutter/material.dart';
import '../../services/performance_service.dart';
import '../../services/analytics_service.dart';
import '../../widgets/real_time_monitoring_widget.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // Data holders
  BusinessMetrics? _businessMetrics;
  List<DatabaseMetrics> _databaseMetrics = [];
  List<QueryPerformance> _slowQueries = [];
  Map<String, dynamic> _databaseSize = {};
  ConnectionMetrics? _connectionMetrics;
  Map<String, double> _cacheHitRatios = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        AnalyticsService.getBusinessMetrics(),
        DatabasePerformanceService.getTableMetrics(),
        DatabasePerformanceService.getSlowestQueries(limit: 5),
        DatabasePerformanceService.getDatabaseSizeMetrics(),
        DatabasePerformanceService.getConnectionMetrics(),
        DatabasePerformanceService.getCacheHitRatios(),
      ]);

      if (mounted) {
        _businessMetrics = results[0] as BusinessMetrics;
        _databaseMetrics = results[1] as List<DatabaseMetrics>;
        _slowQueries = results[2] as List<QueryPerformance>;
        _databaseSize = results[3] as Map<String, dynamic>;
        _connectionMetrics = results[4] as ConnectionMetrics;
        _cacheHitRatios = results[5] as Map<String, double>;
        _isLoading = false;
      };
    } catch (error) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Monitor'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAllData),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.storage), text: 'Database'),
            Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
            Tab(icon: Icon(Icons.monitor), text: 'Real-time'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildDatabaseTab(),
                _buildAnalyticsTab(),
                _buildRealTimeTab(),
              ],
            ),
    );
  }

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildBusinessMetricsCards(),
          const SizedBox(height: 16),
          _buildPerformanceSummaryCard(),
          const SizedBox(height: 16),
          _buildSystemHealthCard(),
        ],
      ),
    );
  }

  Widget _buildBusinessMetricsCards() {
    if (_businessMetrics == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Business Metrics',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _buildMetricCard(
              'Total Members',
              '${_businessMetrics!.totalMembers}',
              Icons.people,
              Colors.blue,
            ),
            _buildMetricCard(
              'Active Members',
              '${_businessMetrics!.activeMembers}',
              Icons.person_outline,
              Colors.green,
            ),
            _buildMetricCard(
              'Monthly Revenue',
              '\$${_businessMetrics!.monthlyRevenue.toStringAsFixed(2)}',
              Icons.money,
              Colors.purple,
            ),
            _buildMetricCard(
              'Check-ins Today',
              '${_businessMetrics!.checkInsToday}',
              Icons.check_circle,
              Colors.orange,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),

            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Summary',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_cacheHitRatios.isNotEmpty) ...[
              _buildProgressIndicator(
                'Buffer Cache Hit Ratio',
                _cacheHitRatios['buffer_hit_ratio'] ?? 0.0,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildProgressIndicator(
                'Index Cache Hit Ratio',
                _cacheHitRatios['index_hit_ratio'] ?? 0.0,
                Colors.green,
              ),
            ],
            if (_connectionMetrics != null) ...[
              const SizedBox(height: 12),
              _buildProgressIndicator(
                'Connection Usage',
                (_connectionMetrics!.activeConnections /
                    _connectionMetrics!.maxConnections *
                    100),
                Colors.orange,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(String label, double percentage, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text('${percentage.toStringAsFixed(1)}%')],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: percentage / 100,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ],
    );
  }

  Widget _buildSystemHealthCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'System Health',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildHealthIndicator(
              'Database Performance',
              _getDatabaseHealthStatus(),
              _getDatabaseHealthColor(),
            ),
            const SizedBox(height: 8),
            _buildHealthIndicator(
              'Connection Pool',
              _getConnectionHealthStatus(),
              _getConnectionHealthColor(),
            ),
            const SizedBox(height: 8),
            _buildHealthIndicator(
              'Cache Performance',
              _getCacheHealthStatus(),
              _getCacheHealthColor(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthIndicator(String label, String status, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            status,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  String _getDatabaseHealthStatus() {
    if (_slowQueries.isEmpty) return 'Excellent';
    final avgTime = _slowQueries.first.avgTime;
    if (avgTime < 100) return 'Good';
    if (avgTime < 500) return 'Fair';
    return 'Poor';
  }

  Color _getDatabaseHealthColor() {
    final status = _getDatabaseHealthStatus();
    switch (status) {
      case 'Excellent':
        return Colors.green;
      case 'Good':
        return Colors.lightGreen;
      case 'Fair':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  String _getConnectionHealthStatus() {
    if (_connectionMetrics == null) return 'Unknown';
    final usage =
        _connectionMetrics!.activeConnections /
        _connectionMetrics!.maxConnections;
    if (usage < 0.5) return 'Healthy';
    if (usage < 0.8) return 'Warning';
    return 'Critical';
  }

  Color _getConnectionHealthColor() {
    final status = _getConnectionHealthStatus();
    switch (status) {
      case 'Healthy':
        return Colors.green;
      case 'Warning':
        return Colors.orange;
      case 'Critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getCacheHealthStatus() {
    final bufferHit = _cacheHitRatios['buffer_hit_ratio'] ?? 0.0;
    if (bufferHit > 90) return 'Excellent';
    if (bufferHit > 80) return 'Good';
    if (bufferHit > 70) return 'Fair';
    return 'Poor';
  }

  Color _getCacheHealthColor() {
    final status = _getCacheHealthStatus();
    switch (status) {
      case 'Excellent':
        return Colors.green;
      case 'Good':
        return Colors.lightGreen;
      case 'Fair':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  Widget _buildDatabaseTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSlowQueriesCard(),
        const SizedBox(height: 16),
        _buildTableMetricsCard(),
        const SizedBox(height: 16),
        _buildDatabaseSizeCard(),
      ],
    );
  }

  Widget _buildSlowQueriesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Slowest Queries',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_slowQueries.isEmpty)
              const Text('No slow query data available')
            else
              ..._slowQueries.map((query) => _buildQueryTile(query)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildQueryTile(QueryPerformance query) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            query.query.length > 80
                ? '${query.query.substring(0, 80)}...'
                : query.query,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Avg: ${query.avgTime.toStringAsFixed(2)}ms'),
              Text('Calls: ${query.calls}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableMetricsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Table Performance',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_databaseMetrics.isEmpty)
              const Text('No table metrics available')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Table')),
                    DataColumn(label: Text('Scans')),
                    DataColumn(label: Text('Tuples Read')),
                    DataColumn(label: Text('Hit Ratio %')),
                  ],
                  rows: _databaseMetrics.take(10).map((metric) {
                    return DataRow(
                      cells: [
                        DataCell(Text(metric.tableName)),
                        DataCell(Text('${metric.totalScans}')),
                        DataCell(Text('${metric.tuplesRead}')),
                        DataCell(
                          Text('${metric.indexHitRatio.toStringAsFixed(1)}'),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseSizeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Database Size',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_databaseSize.isEmpty)
              const Text('No size data available')
            else ...[
              Text(
                'Total Size: ${_databaseSize['database_size_mb']?.toStringAsFixed(2) ?? 'N/A'} MB',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (_databaseSize['table_sizes'] != null)
                ...(_databaseSize['table_sizes'] as List).take(5).map((table) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(table['table_name'] ?? ''),
                        Text(
                          '${table['size_mb']?.toStringAsFixed(2) ?? 'N/A'} MB',
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    return const Center(
      child: Text('Analytics charts will be implemented here'),
    );
  }

  Widget _buildRealTimeTab() {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: RealTimeMonitoringWidget(),
    );
  }
}
