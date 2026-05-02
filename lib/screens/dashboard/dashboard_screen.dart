import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kratos_gym_mobile/screens/performance/performance_screen.dart';
import '../../services/supabase_service.dart';
import '../../models/profile.dart';
import '../members/member_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  final void Function(int)? onNavigateToTab;

  const DashboardScreen({super.key, this.onNavigateToTab});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _recentScans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final supabase = SupabaseService.client;
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      final monthStart = DateTime(now.year, now.month, 1);
      // Load original dashboard counts in parallel
      final countResults = await Future.wait([
        supabase.from('profiles').select('id').count(),
        supabase
            .from('check_ins')
            .select('id')
            .gte('created_at', todayStart.toIso8601String())
            .lt('created_at', todayEnd.toIso8601String())
            .count(),
      ]);

      final totalMembersCount = countResults[0];
      final todayCheckInsCount = countResults[1];

      // Load all KPI stats and recent scans in parallel
      final dataResults = await Future.wait<dynamic>([
        supabase.rpc(
          'get_members_with_filters',
          params: {
            'p_page_size': 1,
            'p_offset': 0,
            'p_status_filter': 'active',
            'p_frozen_filter': 'not_frozen',
            'p_expiring_in_days': null,
          },
        ),
        supabase.rpc(
          'get_monthly_revenue_sum',
          params: {'month_start': monthStart.toIso8601String()},
        ),
        supabase.rpc('get_admin_analytics_summary'),
        supabase
            .from('qr_scans')
            .select('id, scanned_at, method, user_id, gym_id')
            .order('scanned_at', ascending: false)
            .limit(10),
      ]);

      final activeMembersResult = dataResults[0] as List;
      final activeMembershipsCount = activeMembersResult.isNotEmpty
          ? ((activeMembersResult.first['total_count'] as num?)?.toInt() ?? 0)
          : 0;
      final monthlyRevenueCents = dataResults[1] as int;
      final analyticsResult = dataResults[2] as List;
      final analyticsSummary = analyticsResult.isNotEmpty
          ? analyticsResult.first as Map<String, dynamic>
          : <String, dynamic>{};
      final wauCount = (analyticsSummary['wau'] as num?)?.toInt() ?? 0;
      final mauCount = (analyticsSummary['mau'] as num?)?.toInt() ?? 0;
      final dauYesterdayCount =
          (analyticsSummary['yesterday_dau'] as num?)?.toInt() ?? 0;

      // Get user IDs and gym IDs from recent scans
      final recentScansData = dataResults[3] as List;
      final userIds = recentScansData
          .map((scan) => scan['user_id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      final gymIds = recentScansData
          .map((scan) => scan['gym_id'] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      // Fetch user profiles and gyms in parallel (only if needed)
      Map<String, dynamic> profilesMap = {};
      Map<String, dynamic> gymsMap = {};

      if (userIds.isNotEmpty || gymIds.isNotEmpty) {
        final detailQueries = <Future<List>>[];

        if (userIds.isNotEmpty) {
          detailQueries.add(
            supabase
                .from('profiles')
                .select('id, full_name')
                .inFilter('id', userIds),
          );
        }
        if (gymIds.isNotEmpty) {
          detailQueries.add(
            supabase.from('gyms').select('id, name').inFilter('id', gymIds),
          );
        }

        final detailResults = await Future.wait(detailQueries);

        int resultIndex = 0;
        if (userIds.isNotEmpty) {
          for (var profile in detailResults[resultIndex]) {
            profilesMap[profile['id']] = profile;
          }
          resultIndex++;
        }

        if (gymIds.isNotEmpty) {
          for (var gym in detailResults[resultIndex]) {
            gymsMap[gym['id']] = gym;
          }
        }
      }

      // Merge profile and gym data into scans
      final scansWithDetails = recentScansData.map((scan) {
        final userId = scan['user_id'] as String?;
        final gymId = scan['gym_id'] as String?;
        return <String, dynamic>{
          'id': scan['id'],
          'scanned_at': scan['scanned_at'],
          'user_id': userId,
          'gym_id': gymId,
          'method': scan['method'],
          'profile': userId != null ? profilesMap[userId] : null,
          'gym': gymId != null ? gymsMap[gymId] : null,
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _stats = {
          'totalMembers': totalMembersCount.count,
          'activeMemberships': activeMembershipsCount,
          'todayCheckIns': todayCheckInsCount.count,
          'monthlyRevenue': monthlyRevenueCents / 100,
          'wau': wauCount,
          'mau': mauCount,
          'dauYesterday': dauYesterdayCount,
        };
        _recentScans = scansWithDetails;
        _isLoading = false;
      });
    } catch (error) {
      print('Dashboard error: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare: $error')));
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatScanTime(String timestamp) {
    final scanTime = DateTime.parse(timestamp);
    final now = DateTime.now();
    final difference = now.difference(scanTime);

    if (difference.inMinutes < 1) {
      return 'Acum';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m în urmă';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h în urmă';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}z în urmă';
    } else {
      return DateFormat('dd MMM, HH:mm').format(scanTime);
    }
  }

  IconData _getMethodIcon(String? method) {
    switch (method) {
      case 'nfc':
        return Icons.nfc_rounded;
      case 'manual':
        return Icons.edit_rounded;
      case 'qr':
      default:
        return Icons.qr_code_scanner_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onLongPress: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => PerformanceScreen()),
            );
          },
          child: const Text('Dashboard'),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Deconectare',
            onPressed: () async {
              await SupabaseService.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header
                  Text(
                    'Kratos Gym',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Panou de Administrare',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Stats Grid
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 1,
                    children: [
                      _StatCard(
                        title: 'Total Membri',
                        value: _stats?['totalMembers']?.toString() ?? '0',
                        icon: '👥',
                        color: const Color(0xFF1E88E5), // Material Blue 600
                      ),
                      _StatCard(
                        title: 'Abonamente Active',
                        value: _stats?['activeMemberships']?.toString() ?? '0',
                        icon: '💳',
                        color: const Color(0xFF43A047), // Material Green 600
                      ),
                      _StatCard(
                        title: 'Check-ins Astăzi',
                        value: _stats?['todayCheckIns']?.toString() ?? '0',
                        icon: '✅',
                        color: const Color(0xFFFB8C00), // Material Orange 600
                      ),
                      _StatCard(
                        title: 'Venituri Luna',
                        value:
                            '${(_stats?['monthlyRevenue'] ?? 0).toStringAsFixed(0)} RON',
                        icon: '💰',
                        color: const Color(0xFF8E24AA), // Material Purple 600
                      ),
                      _StatCard(
                        title: 'WAU',
                        value: _stats?['wau']?.toString() ?? '0',
                        icon: '📅',
                        color: const Color(0xFF00897B), // Material Teal 600
                      ),
                      _StatCard(
                        title: 'MAU',
                        value: _stats?['mau']?.toString() ?? '0',
                        icon: '📈',
                        color: const Color(0xFF3949AB), // Material Indigo 600
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 98,
                    child: _StatCard(
                      title: 'DAU Ieri',
                      value: _stats?['dauYesterday']?.toString() ?? '0',
                      icon: '🌙',
                      color: const Color(0xFFD81B60), // Material Pink 600
                      isCompact: true,
                    ),
                  ),

                  // const SizedBox(height: 32),

                  // // Recent Scans Section
                  // Row(
                  //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  //   children: [
                  //     Text(
                  //       'Scanări Recente',
                  //       style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  //         fontWeight: FontWeight.bold,
                  //       ),
                  //     ),
                  //     TextButton(
                  //       onPressed: () {
                  //         // Navigate to check-ins tab (index 2)
                  //         widget.onNavigateToTab?.call(2);
                  //       },
                  //       style: TextButton.styleFrom(
                  //         foregroundColor: Theme.of(
                  //           context,
                  //         ).colorScheme.primary,
                  //         textStyle: const TextStyle(
                  //           fontWeight: FontWeight.w600,
                  //           fontSize: 14,
                  //         ),
                  //       ),
                  //       child: const Row(
                  //         mainAxisSize: MainAxisSize.min,
                  //         children: [
                  //           Text('Vezi tot'),
                  //           SizedBox(width: 4),
                  //           Icon(Icons.arrow_forward, size: 16),
                  //         ],
                  //       ),
                  //     ),
                  //   ],
                  // ),
                  // const SizedBox(height: 12),

                  // // Recent Scans List
                  // if (_recentScans.isEmpty)
                  //   Card(
                  //     elevation: 0,
                  //     shape: RoundedRectangleBorder(
                  //       borderRadius: BorderRadius.circular(12),
                  //       side: BorderSide(
                  //         color: Theme.of(context).colorScheme.outlineVariant,
                  //       ),
                  //     ),
                  //     child: Padding(
                  //       padding: const EdgeInsets.all(48),
                  //       child: Column(
                  //         children: [
                  //           Icon(
                  //             Icons.qr_code_scanner_rounded,
                  //             size: 48,
                  //             color: Theme.of(
                  //               context,
                  //             ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                  //           ),
                  //           const SizedBox(height: 16),
                  //           Text(
                  //             'Nicio scanare recentă',
                  //             style: Theme.of(context).textTheme.titleMedium
                  //                 ?.copyWith(
                  //                   color: Theme.of(
                  //                     context,
                  //                   ).colorScheme.onSurfaceVariant,
                  //                 ),
                  //           ),
                  //         ],
                  //       ),
                  //     ),
                  //   )
                  // else
                  //   ListView.separated(
                  //     shrinkWrap: true,
                  //     physics: const NeverScrollableScrollPhysics(),
                  //     itemCount: _recentScans.length,
                  //     separatorBuilder: (context, index) =>
                  //         const SizedBox(height: 8),
                  //     itemBuilder: (context, index) {
                  //       final scan = _recentScans[index];
                  //       final profile =
                  //           scan['profile'] as Map<String, dynamic>?;
                  //       final gym = scan['gym'] as Map<String, dynamic>?;
                  //       final method = scan['method'] as String?;
                  //       final scannedAt = scan['scanned_at'] as String?;

                  //       return Card(
                  //         elevation: 0,
                  //         shape: RoundedRectangleBorder(
                  //           borderRadius: BorderRadius.circular(12),
                  //           side: BorderSide(
                  //             color: Theme.of(
                  //               context,
                  //             ).colorScheme.outlineVariant.withOpacity(0.5),
                  //           ),
                  //         ),
                  //         child: ListTile(
                  //           contentPadding: const EdgeInsets.symmetric(
                  //             horizontal: 16,
                  //             vertical: 8,
                  //           ),
                  //           onTap: profile != null && profile['id'] != null
                  //               ? () {
                  //                   Navigator.of(context).push(
                  //                     MaterialPageRoute(
                  //                       builder: (context) =>
                  //                           MemberDetailScreen(
                  //                             member: Profile.fromJson(profile),
                  //                           ),
                  //                     ),
                  //                   );
                  //                 }
                  //               : () => print('No profile data available'),
                  //           leading: CircleAvatar(
                  //             backgroundColor: Theme.of(
                  //               context,
                  //             ).colorScheme.primaryContainer,
                  //             child: Icon(
                  //               _getMethodIcon(method),
                  //               color: Theme.of(
                  //                 context,
                  //               ).colorScheme.onPrimaryContainer,
                  //               size: 20,
                  //             ),
                  //           ),
                  //           title: Text(
                  //             profile?['full_name'] ?? 'Nume necunoscut',
                  //             style: const TextStyle(
                  //               fontWeight: FontWeight.w600,
                  //             ),
                  //           ),
                  //           subtitle: Column(
                  //             crossAxisAlignment: CrossAxisAlignment.start,
                  //             children: [
                  //               const SizedBox(height: 4),
                  //               Row(
                  //                 children: [
                  //                   Icon(
                  //                     Icons.fitness_center_rounded,
                  //                     size: 14,
                  //                     color: Theme.of(
                  //                       context,
                  //                     ).colorScheme.onSurfaceVariant,
                  //                   ),
                  //                   const SizedBox(width: 4),
                  //                   Text(
                  //                     gym?['name'] ?? 'Sală necunoscută',
                  //                     style: Theme.of(
                  //                       context,
                  //                     ).textTheme.bodySmall,
                  //                   ),
                  //                 ],
                  //               ),
                  //             ],
                  //           ),
                  //           trailing: scannedAt != null
                  //               ? Text(
                  //                   _formatScanTime(scannedAt),
                  //                   style: Theme.of(context).textTheme.bodySmall
                  //                       ?.copyWith(
                  //                         color: Theme.of(
                  //                           context,
                  //                         ).colorScheme.onSurfaceVariant,
                  //                       ),
                  //                 )
                  //               : null,
                  //         ),
                  //       );
                  //     },
                  //   ),
                ],
              ),
      ),
    );
  }
}

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
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // TODO: Navigate to detail page
        },
        child: Stack(
          children: [
            // Background gradient effect
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
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
              padding: const EdgeInsets.all(16.0),
              child: isCompact
                  ? Row(
                      children: [
                        // Icon container
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                value,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                title,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon container
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
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Value and title
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 24,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
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
