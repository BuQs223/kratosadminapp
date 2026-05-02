import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/performance_service.dart';
import '../../services/analytics_service.dart';

class RealTimeMonitoringWidget extends StatefulWidget {
  const RealTimeMonitoringWidget({super.key});

  @override
  State<RealTimeMonitoringWidget> createState() =>
      _RealTimeMonitoringWidgetState();
}

class _RealTimeMonitoringWidgetState extends State<RealTimeMonitoringWidget> {
  Timer? _refreshTimer;
  final List<FlSpot> _performanceData = [];
  final List<FlSpot> _connectionData = [];
  final List<FlSpot> _cacheHitData = [];

  ConnectionMetrics? _currentConnections;
  BusinessMetrics? _currentMetrics;
  Map<String, double> _currentCacheRatio = {};

  int _dataPointIndex = 0;
  final int _maxDataPoints = 20;

  @override
  void initState() {
    super.initState();
    _startRealTimeMonitoring();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRealTimeMonitoring() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchRealTimeData();
    });
    _fetchRealTimeData(); // Initial load
  }

  Future<void> _fetchRealTimeData() async {
    try {
      final results = await Future.wait([
        DatabasePerformanceService.getConnectionMetrics(),
        AnalyticsService.getBusinessMetrics(),
        DatabasePerformanceService.getCacheHitRatios(),
      ]);

      if (mounted) {
        setState(() {
          _currentConnections = results[0] as ConnectionMetrics;
          _currentMetrics = results[1] as BusinessMetrics;
          _currentCacheRatio = results[2] as Map<String, double>;

          // Add new data points to charts
          final double x = _dataPointIndex.toDouble();

          // Connection usage percentage
          final connectionUsage =
              _currentConnections!.activeConnections /
              _currentConnections!.maxConnections *
              100;
          _addDataPoint(_connectionData, FlSpot(x, connectionUsage));

          // Cache hit ratio
          final cacheHit = _currentCacheRatio['buffer_hit_ratio'] ?? 0.0;
          _addDataPoint(_cacheHitData, FlSpot(x, cacheHit));

          // Sample performance metric (you can customize this)
          final performanceScore = _calculatePerformanceScore();
          _addDataPoint(_performanceData, FlSpot(x, performanceScore));

          _dataPointIndex++;
        });
      }
    } catch (error) {
      print('Error fetching real-time data: $error');
    }
  }

  void _addDataPoint(List<FlSpot> dataList, FlSpot newPoint) {
    dataList.add(newPoint);
    if (dataList.length > _maxDataPoints) {
      dataList.removeAt(0);
    }
  }

  double _calculatePerformanceScore() {
    // Simple performance score calculation
    final cacheHit = _currentCacheRatio['buffer_hit_ratio'] ?? 0.0;
    final connectionUsage = _currentConnections != null
        ? (_currentConnections!.activeConnections /
              _currentConnections!.maxConnections *
              100)
        : 0.0;

    // Higher cache hit = better, lower connection usage = better
    return (cacheHit - (connectionUsage * 0.5)).clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildRealTimeMetrics(),
        const SizedBox(height: 16),
        _buildPerformanceChart(),
        const SizedBox(height: 16),
        _buildConnectionChart(),
        const SizedBox(height: 16),
        _buildCacheHitChart(),
      ],
    );
  }

  Widget _buildRealTimeMetrics() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.online_prediction, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Live Metrics',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildLiveMetricTile(
                    'Active Connections',
                    '${_currentConnections?.activeConnections ?? 0}',
                    '/ ${_currentConnections?.maxConnections ?? 0}',
                    Icons.link,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildLiveMetricTile(
                    'Cache Hit Ratio',
                    '${_currentCacheRatio['buffer_hit_ratio']?.toStringAsFixed(1) ?? '0'}%',
                    '',
                    Icons.memory,
                    Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildLiveMetricTile(
                    'Check-ins Today',
                    '${_currentMetrics?.checkInsToday ?? 0}',
                    '',
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildLiveMetricTile(
                    'Active Members',
                    '${_currentMetrics?.activeMembers ?? 0}',
                    '',
                    Icons.people,
                    Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveMetricTile(
    String title,
    String value,
    String suffix,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (suffix.isNotEmpty)
                Text(
                  ' $suffix',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Score',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _buildLineChart(_performanceData, Colors.green),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection Usage (%)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _buildLineChart(_connectionData, Colors.blue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheHitChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cache Hit Ratio (%)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _buildLineChart(_cacheHitData, Colors.purple),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(List<FlSpot> data, Color color) {
    if (data.isEmpty) {
      return const Center(child: Text('Collecting data...'));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: 25,
          verticalInterval: 5,
          getDrawingHorizontalLine: (value) {
            return FlLine(color: Colors.grey[300]!, strokeWidth: 1);
          },
          getDrawingVerticalLine: (value) {
            return FlLine(color: Colors.grey[300]!, strokeWidth: 1);
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 5,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toInt()}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 25,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toInt()}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
              reservedSize: 42,
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey[300]!),
        ),
        minX: data.isNotEmpty ? data.first.x : 0,
        maxX: data.isNotEmpty ? data.last.x : 10,
        minY: 0,
        maxY: 100,
        lineBarsData: [
          LineChartBarData(
            spots: data,
            isCurved: true,
            color: color,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }
}
