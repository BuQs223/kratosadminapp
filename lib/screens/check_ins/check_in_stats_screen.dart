import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/powersync_service.dart';

class _HourStat {
  final int hour;
  final int checkins;

  const _HourStat({required this.hour, required this.checkins});

  String get label {
    final start = hour.toString().padLeft(2, '0');
    final end = ((hour + 1) % 24).toString().padLeft(2, '0');
    return '$start:00 - $end:00';
  }
}

class _GymStat {
  final String gymName;
  final int checkins;

  const _GymStat({required this.gymName, required this.checkins});
}

enum _TimePreset { today, last7Days, last30Days, thisMonth, custom }

class CheckInStatsScreen extends StatefulWidget {
  const CheckInStatsScreen({super.key});

  @override
  State<CheckInStatsScreen> createState() => _CheckInStatsScreenState();
}

class _CheckInStatsScreenState extends State<CheckInStatsScreen> {
  bool _isLoading = true;
  int _totalCheckIns = 0;
  List<_HourStat> _busiestHours = [];
  List<_GymStat> _topGyms = [];
  final List<Map<String, String>> _gyms = [];
  String? _selectedGymId;

  _TimePreset _preset = _TimePreset.thisMonth;
  late DateTime _startDate;
  late DateTime _endDateExclusive;

  @override
  void initState() {
    super.initState();
    _loadGyms();
    _applyPreset(_TimePreset.thisMonth, loadData: false);
    _loadStats();
  }

  Future<void> _loadGyms() async {
    try {
      await PowerSyncService.connectIfAuthenticated();
      final response = await PowerSyncService.db.getAll(
        'SELECT id, name FROM gyms ORDER BY name COLLATE NOCASE',
      );

      if (!mounted) return;
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
    } catch (_) {
      // Gym list is optional for stats loading
    }
  }

  void _applyPreset(_TimePreset preset, {bool loadData = true}) {
    final now = DateTime.now();
    late final DateTime start;
    late final DateTime endExclusive;

    switch (preset) {
      case _TimePreset.today:
        start = DateTime(now.year, now.month, now.day);
        endExclusive = now.add(const Duration(seconds: 1));
        break;
      case _TimePreset.last7Days:
        final from = now.subtract(const Duration(days: 6));
        start = DateTime(from.year, from.month, from.day);
        endExclusive = now.add(const Duration(seconds: 1));
        break;
      case _TimePreset.last30Days:
        final from = now.subtract(const Duration(days: 29));
        start = DateTime(from.year, from.month, from.day);
        endExclusive = now.add(const Duration(seconds: 1));
        break;
      case _TimePreset.thisMonth:
        start = DateTime(now.year, now.month, 1);
        endExclusive = now.add(const Duration(seconds: 1));
        break;
      case _TimePreset.custom:
        return;
    }

    setState(() {
      _preset = preset;
      _startDate = start;
      _endDateExclusive = endExclusive;
    });

    if (loadData) {
      _loadStats();
    }
  }

  Future<void> _selectCustomRange() async {
    final now = DateTime.now();
    final initialEnd = _endDateExclusive.subtract(
      const Duration(milliseconds: 1),
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _startDate,
        end: initialEnd.isAfter(now) ? now : initialEnd,
      ),
    );

    if (picked == null) return;

    final start = DateTime(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    final endExclusive = DateTime(
      picked.end.year,
      picked.end.month,
      picked.end.day,
    ).add(const Duration(days: 1));

    setState(() {
      _preset = _TimePreset.custom;
      _startDate = start;
      _endDateExclusive = endExclusive;
    });

    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);

    try {
      await PowerSyncService.connectIfAuthenticated();

      final params = <Object?>[
        _startDate.toIso8601String(),
        _endDateExclusive.toIso8601String(),
      ];
      final gymFilter = _selectedGymId == null ? '' : 'AND c.gym_id = ?';
      if (_selectedGymId != null) {
        params.add(_selectedGymId);
      }

      final totalRow = await PowerSyncService.db.get('''
        SELECT COUNT(*) AS total_checkins
        FROM check_ins c
        WHERE datetime(c.created_at) >= datetime(?)
          AND datetime(c.created_at) < datetime(?)
          $gymFilter
        ''', params);
      final totalCheckIns = (totalRow['total_checkins'] as num?)?.toInt() ?? 0;

      final busiestHoursRows = await PowerSyncService.db.getAll('''
        SELECT
          CAST(strftime('%H', datetime(c.created_at), 'localtime') AS INTEGER) AS hour,
          COUNT(*) AS checkins
        FROM check_ins c
        WHERE datetime(c.created_at) >= datetime(?)
          AND datetime(c.created_at) < datetime(?)
          $gymFilter
        GROUP BY hour
        ORDER BY checkins DESC, hour ASC
        LIMIT 5
        ''', params);
      final busiestHours = busiestHoursRows
          .map(
            (data) => _HourStat(
              hour: (data['hour'] as num?)?.toInt() ?? 0,
              checkins: (data['checkins'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();

      final topGymsRows = await PowerSyncService.db.getAll('''
        SELECT COALESCE(g.name, 'Unknown') AS gym_name, COUNT(*) AS checkins
        FROM check_ins c
        LEFT JOIN gyms g ON g.id = c.gym_id
        WHERE datetime(c.created_at) >= datetime(?)
          AND datetime(c.created_at) < datetime(?)
          $gymFilter
        GROUP BY c.gym_id, g.name
        ORDER BY checkins DESC, gym_name COLLATE NOCASE
        LIMIT 5
        ''', params);
      final topGyms = topGymsRows
          .map(
            (data) => _GymStat(
              gymName: data['gym_name'] as String? ?? 'Unknown',
              checkins: (data['checkins'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _totalCheckIns = totalCheckIns;
        _busiestHours = busiestHours;
        _topGyms = topGyms;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la încărcarea statisticilor: $error')),
      );
    }
  }

  String _formatRange() {
    final formatter = DateFormat('dd MMM yyyy');
    final endDisplay = _endDateExclusive.subtract(
      const Duration(milliseconds: 1),
    );
    return '${formatter.format(_startDate)} - ${formatter.format(endDisplay)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistici Check-ins')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildFiltersPanel(context),
                  const SizedBox(height: 16),
                  _buildTotalCheckinsCard(context),
                  const SizedBox(height: 24),
                  _buildBusiestHoursSection(context),
                  if (_selectedGymId == null) ...[
                    const SizedBox(height: 24),
                    _buildTopGymsSection(context),
                  ],
                ],
              ),
            ),
    );
  }

  String _presetLabel(_TimePreset preset) {
    switch (preset) {
      case _TimePreset.today:
        return 'Azi';
      case _TimePreset.last7Days:
        return 'Ultimele 7 zile';
      case _TimePreset.last30Days:
        return 'Ultimele 30 zile';
      case _TimePreset.thisMonth:
        return 'Luna asta';
      case _TimePreset.custom:
        return 'Custom';
    }
  }

  Widget _buildFiltersPanel(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Filtre',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<_TimePreset>(
              key: ValueKey(_preset),
              initialValue: _preset,
              dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              decoration: const InputDecoration(
                labelText: 'Perioadă',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.date_range),
              ),
              items: _TimePreset.values
                  .map(
                    (preset) => DropdownMenuItem<_TimePreset>(
                      value: preset,
                      child: Text(_presetLabel(preset)),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                if (value == _TimePreset.custom) {
                  setState(() => _preset = _TimePreset.custom);
                  await _selectCustomRange();
                  return;
                }
                _applyPreset(value);
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _selectCustomRange,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatRange(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'Schimbă',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey(_selectedGymId ?? '__all_gyms__'),
              initialValue: _selectedGymId,
              dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              decoration: const InputDecoration(
                labelText: 'Sală',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.fitness_center),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Toate sălile'),
                ),
                ..._gyms.map(
                  (gym) => DropdownMenuItem<String?>(
                    value: gym['id'],
                    child: Text(gym['name']!),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() => _selectedGymId = value);
                _loadStats();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCheckinsCard(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Check-ins',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    NumberFormat.decimalPattern().format(_totalCheckIns),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
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

  Widget _buildBusiestHoursSection(BuildContext context) {
    return _buildSectionCard(
      context: context,
      title: 'Busiest Hours',
      icon: Icons.schedule,
      child: _busiestHours.isEmpty
          ? _buildEmptyText(
              context,
              'Nu există check-ins în intervalul selectat',
            )
          : Column(
              children: List.generate(_busiestHours.length, (index) {
                final hourStat = _busiestHours[index];
                return _buildRankedRow(
                  context: context,
                  rank: index + 1,
                  label: hourStat.label,
                  value: hourStat.checkins,
                );
              }),
            ),
    );
  }

  Widget _buildTopGymsSection(BuildContext context) {
    return _buildSectionCard(
      context: context,
      title: 'Top Săli după Check-ins',
      icon: Icons.fitness_center,
      child: _topGyms.isEmpty
          ? _buildEmptyText(
              context,
              'Nu există date pentru săli în intervalul selectat',
            )
          : Column(
              children: List.generate(_topGyms.length, (index) {
                final gymStat = _topGyms[index];
                return _buildRankedRow(
                  context: context,
                  rank: index + 1,
                  label: gymStat.gymName,
                  value: gymStat.checkins,
                );
              }),
            ),
    );
  }

  Widget _buildRankedRow({
    required BuildContext context,
    required int rank,
    required String label,
    required int value,
  }) {
    final formattedValue = NumberFormat.decimalPattern().format(value);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$rank. $label',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            formattedValue,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyText(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
