import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/supabase_service.dart';

class GymCheckinStats {
  final String gymId;
  final String gymName;
  final int uniqueGoldMembers;
  final int totalGoldCheckins;
  final int uniqueSilverMembers;
  final int totalSilverCheckins;

  GymCheckinStats({
    required this.gymId,
    required this.gymName,
    required this.uniqueGoldMembers,
    required this.totalGoldCheckins,
    required this.uniqueSilverMembers,
    required this.totalSilverCheckins,
  });

  factory GymCheckinStats.fromJson(Map<String, dynamic> json) {
    return GymCheckinStats(
      gymId: json['gym_id'] as String,
      gymName: json['gym_name'] as String,
      uniqueGoldMembers: (json['unique_gold_members'] as num?)?.toInt() ?? 0,
      totalGoldCheckins: (json['total_checkins'] as num?)?.toInt() ?? 0,
      uniqueSilverMembers:
          (json['unique_silver_members'] as num?)?.toInt() ?? 0,
      totalSilverCheckins:
          (json['silver_total_checkins'] as num?)?.toInt() ?? 0,
    );
  }

  int get totalUniqueMembers => uniqueGoldMembers + uniqueSilverMembers;
  int get totalCheckins => totalGoldCheckins + totalSilverCheckins;
}

class GoldCheckinsScreen extends StatefulWidget {
  const GoldCheckinsScreen({super.key});

  @override
  State<GoldCheckinsScreen> createState() => _GoldCheckinsScreenState();
}

class _GoldCheckinsScreenState extends State<GoldCheckinsScreen> {
  List<GymCheckinStats> _stats = [];
  bool _isLoading = true;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);

    try {
      final supabase = SupabaseService.client;

      final response = await supabase.rpc(
        'get_gold_member_checkins_analytics',
        params: {
          'p_start_date': DateFormat('yyyy-MM-dd').format(_startDate),
          'p_end_date': DateFormat('yyyy-MM-dd').format(_endDate),
        },
      );

      if (mounted) {
        setState(() {
          _stats = (response as List)
              .map((json) => GymCheckinStats.fromJson(json))
              .toList();
          _isLoading = false;
        });
      }
    } catch (error) {
      print('Error loading stats: $error');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare: $error')));
      }
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadStats();
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    // Calculate totals
    final totalGoldMembers = _stats.fold<int>(
      0,
      (sum, s) => sum + s.uniqueGoldMembers,
    );
    final totalGoldCheckins = _stats.fold<int>(
      0,
      (sum, s) => sum + s.totalGoldCheckins,
    );
    final totalSilverMembers = _stats.fold<int>(
      0,
      (sum, s) => sum + s.uniqueSilverMembers,
    );
    final totalSilverCheckins = _stats.fold<int>(
      0,
      (sum, s) => sum + s.totalSilverCheckins,
    );

    // Filter only Kratos 1 and Kratos 2 for Gold usage stats
    final kratos1Stats = _stats
        .where((s) => s.gymName == 'Kratos 1')
        .firstOrNull;
    final kratos2Stats = _stats
        .where((s) => s.gymName == 'Kratos 2')
        .firstOrNull;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Gold la Kratos 1 & 2'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _selectDateRange,
            tooltip: 'Schimbă perioada',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date range indicator
                    Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 18,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_formatDate(_startDate)} - ${_formatDate(_endDate)}',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            TextButton(
                              onPressed: _selectDateRange,
                              child: const Text('Schimbă'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Gold members at Kratos 1 & 2 highlight
                    Text(
                      '🥇 Membri Gold la Kratos 1 & 2',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Membrii Gold care au folosit accesul la Kratos 1 sau Kratos 2',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Kratos 1 & 2 Gold Stats
                    Row(
                      children: [
                        Expanded(
                          child: _buildGoldGymCard(
                            'Kratos 1',
                            kratos1Stats?.uniqueGoldMembers ?? 0,
                            kratos1Stats?.totalGoldCheckins ?? 0,
                            const Color(0xFFFFB300),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildGoldGymCard(
                            'Kratos 2',
                            kratos2Stats?.uniqueGoldMembers ?? 0,
                            kratos2Stats?.totalGoldCheckins ?? 0,
                            const Color(0xFFFFA000),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Combined K1+K2 Gold stats
                    _buildCombinedGoldCard(
                      (kratos1Stats?.uniqueGoldMembers ?? 0) +
                          (kratos2Stats?.uniqueGoldMembers ?? 0),
                      (kratos1Stats?.totalGoldCheckins ?? 0) +
                          (kratos2Stats?.totalGoldCheckins ?? 0),
                    ),

                    const SizedBox(height: 32),

                    // All gyms comparison
                    Text(
                      '📊 Comparație pe toate sălile',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Summary cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryCard(
                            'Total Gold',
                            totalGoldMembers.toString(),
                            '$totalGoldCheckins check-ins',
                            const Color(0xFFFFB300),
                            Icons.workspace_premium,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSummaryCard(
                            'Total Silver',
                            totalSilverMembers.toString(),
                            '$totalSilverCheckins check-ins',
                            const Color(0xFF9E9E9E),
                            Icons.verified,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Per gym breakdown
                    ..._stats.map(
                      (stat) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildGymDetailCard(stat),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildGoldGymCard(
    String gymName,
    int uniqueMembers,
    int totalCheckins,
    Color color,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fitness_center, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    gymName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              uniqueMembers.toString(),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              'membri unici',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$totalCheckins check-ins',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color.withOpacity(0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedGoldCard(int uniqueMembers, int totalCheckins ) {
    return Card(
       elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFFFFA000).withOpacity(0.3)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [const Color(0xFFFFA000).withOpacity(0.15), const Color(0xFFFFA000).withOpacity(0.05)],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 36, 28, 7).withOpacity(0.8),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('🥇', style: TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Gold la K1 + K2',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$uniqueMembers membri unici • $totalCheckins check-ins',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFFF8F00),
                      fontWeight: FontWeight.w600,
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

  Widget _buildSummaryCard(
    String title,
    String value,
    String subtitle,
    Color color,
    IconData icon,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGymDetailCard(GymCheckinStats stat) {
    final isKratos3 = stat.gymName == 'Kratos 3';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.fitness_center,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stat.gymName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isKratos3)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Gold Only',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatColumn(
                    '🥇 Gold',
                    stat.uniqueGoldMembers.toString(),
                    '${stat.totalGoldCheckins} check-ins',
                    const Color(0xFFFFB300),
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _buildStatColumn(
                    '🥈 Silver',
                    stat.uniqueSilverMembers.toString(),
                    '${stat.totalSilverCheckins} check-ins',
                    const Color(0xFF9E9E9E),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    String label,
    String value,
    String subtitle,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
