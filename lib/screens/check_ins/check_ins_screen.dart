import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/check_in.dart';
import '../../services/supabase_service.dart';
import 'check_in_stats_screen.dart';
import '../members/member_detail_screen.dart';

class CheckInsScreen extends StatefulWidget {
  const CheckInsScreen({super.key});

  @override
  State<CheckInsScreen> createState() => _CheckInsScreenState();
}

class _CheckInsScreenState extends State<CheckInsScreen> {
  List<CheckIn> _checkIns = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreData = true;

  // Pagination
  static const int _pageSize = 20;
  int _currentOffset = 0;

  // Filters
  String? _selectedGymId;
  String? _selectedStatus;
  final List<Map<String, String>> _gyms = [];

  // Scroll controller for pagination
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadGyms();
    _loadCheckIns();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.8 &&
        !_isLoadingMore &&
        _hasMoreData) {
      _loadMoreCheckIns();
    }
  }

  Future<void> _loadGyms() async {
    try {
      final supabase = SupabaseService.client;
      final response = await supabase
          .from('gyms')
          .select('id, name')
          .order('name');

      if (mounted) {
        setState(() {
          _gyms.clear();
          _gyms.addAll(
            (response as List).map(
              (gym) => {
                'id': gym['id'] as String,
                'name': gym['name'] as String,
              },
            ),
          );
        });
      }
    } catch (error) {
      print('Error loading gyms: $error');
    }
  }

  Future<void> _loadCheckIns({bool isLoadMore = false}) async {
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
      final supabase = SupabaseService.client;

      // Use optimized RPC function
      final response = await supabase.rpc(
        'get_check_ins_paginated',
        params: {
          'p_gym_id': _selectedGymId,
          'p_status': _selectedStatus,
          'p_limit': _pageSize,
          'p_offset': isLoadMore ? _currentOffset : 0,
        },
      );

      final List<dynamic> data = response as List;

      if (data.isEmpty) {
        if (mounted) {
          setState(() {
            if (!isLoadMore) {
              _checkIns = [];
            }
            _hasMoreData = false;
            _isLoading = false;
            _isLoadingMore = false;
          });
        }
        return;
      }

      // Parse check-ins from RPC response
      final checkIns = data
          .map((row) {
            try {
              return CheckIn.fromJson({
                'id': row['id'],
                'user_id': row['user_id'],
                'gym_id': row['gym_id'],
                'membership_id': row['membership_id'],
                'status': row['status'],
                'message': row['message'],
                'days_left': row['days_left'],
                'shown_to_user': row['shown_to_user'],
                'method': row['method'],
                'created_at': row['created_at'],
                'profiles': row['user_full_name'] != null
                    ? {'id': row['user_id'], 'full_name': row['user_full_name']}
                    : null,
                'gyms': row['gym_name'] != null
                    ? {'id': row['gym_id'], 'name': row['gym_name']}
                    : null,
              });
            } catch (e) {
              print('Error parsing check-in: $e');
              print('JSON: $row');
              return null;
            }
          })
          .whereType<CheckIn>()
          .toList();

      if (mounted) {
        setState(() {
          if (isLoadMore) {
            _checkIns.addAll(checkIns);
          } else {
            _checkIns = checkIns;
          }
          _currentOffset = isLoadMore
              ? _currentOffset + checkIns.length
              : checkIns.length;
          _hasMoreData = checkIns.length == _pageSize;
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (error) {
      print('Error loading check-ins: $error');
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

  Future<void> _loadMoreCheckIns() async {
    if (!_hasMoreData || _isLoadingMore) return;
    await _loadCheckIns(isLoadMore: true);
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        selectedGymId: _selectedGymId,
        selectedStatus: _selectedStatus,
        gyms: _gyms,
        onApplyFilters: (gymId, status) {
          if (mounted) {
            setState(() {
              _selectedGymId = gymId;
              _selectedStatus = status;
            });
          }
          _loadCheckIns();
        },
        onClearFilters: () {
          if (mounted) {
            setState(() {
              _selectedGymId = null;
              _selectedStatus = null;
            });
          }
          _loadCheckIns();
        },
      ),
    );
  }

  int get _activeFiltersCount {
    int count = 0;
    if (_selectedGymId != null) count++;
    if (_selectedStatus != null) count++;
    return count;
  }

  String _formatDateTime(DateTime dateTime) {
    // Convert to local time (Bucharest timezone)
    final localDateTime = dateTime.toLocal();
    return DateFormat('dd MMM yyyy, HH:mm').format(localDateTime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-ins'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.query_stats),
            tooltip: 'Statistici Check-ins',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const CheckInStatsScreen(),
                ),
              );
            },
          ),
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
          : _checkIns.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 80,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.3),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Niciun check-in',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Activitatea de check-in va apărea aici',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadCheckIns,
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount:
                    _checkIns.length +
                    (_isLoadingMore ? 1 : (_hasMoreData ? 0 : 1)),
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  // Loading indicator for pagination
                  if (index == _checkIns.length && _isLoadingMore) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  // End of list indicator
                  if (index == _checkIns.length && !_hasMoreData) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          'Toate check-in-urile au fost încărcate',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    );
                  }

                  final checkIn = _checkIns[index];
                  // Check-ins table doesn't track check-out, only status
                  final isSuccess = checkIn.status == 'success';
                  final isExpiring = checkIn.status == 'expiring';
                  final isDenied =
                      checkIn.status == 'denied' ||
                      checkIn.status == 'expired' ||
                      checkIn.status == 'no_access';
                  final isTimeRestricted = checkIn.status == 'time_restricted';

                  // Determine color scheme based on status
                  Color statusColor;
                  String statusEmoji;

                  if (isSuccess) {
                    statusColor = const Color(0xFF43A047); // Green
                    statusEmoji = '✅';
                  } else if (isExpiring) {
                    statusColor = const Color(0xFFFB8C00); // Orange
                    statusEmoji = '⚠️';
                  } else if (isTimeRestricted) {
                    statusColor = const Color(0xFF1E88E5); // Blue
                    statusEmoji = '⏰';
                  } else if (isDenied) {
                    statusColor = const Color(0xFFE53935); // Red
                    statusEmoji = '❌';
                  } else {
                    statusColor = Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant;
                    statusEmoji = '❓';
                  }

                  return Card(
                    elevation: 0,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: checkIn.profile != null
                          ? () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => MemberDetailScreen(
                                    member: checkIn.profile!,
                                  ),
                                ),
                              );
                            }
                          : null,
                      child: Stack(
                        children: [
                          // Gradient background
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    statusColor.withOpacity(0.05),
                                    statusColor.withOpacity(0.02),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Content
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header row
                                Row(
                                  children: [
                                    // Status emoji in circle
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          statusEmoji,
                                          style: const TextStyle(fontSize: 24),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Name and time
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            checkIn.profile?.fullName ??
                                                'Unknown',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatDateTime(
                                              checkIn.checkedInAt,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Status badge
                                    if (checkIn.status != null &&
                                        checkIn.status!.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          _getStatusLabel(checkIn.status!),
                                          style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // Details
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 12,
                                  children: [
                                    // Gym
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.fitness_center,
                                          size: 16,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          checkIn.gym?.name ?? 'Unknown',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                      ],
                                    ),
                                    // Days left
                                    if (checkIn.daysLeft != null)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.event_available,
                                            size: 16,
                                            color: checkIn.daysLeft! <= 7
                                                ? Colors.orange
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${checkIn.daysLeft}z rămase',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: checkIn.daysLeft! <= 7
                                                      ? Colors.orange
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                // Message
                                if (checkIn.message != null &&
                                    checkIn.message!.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isDenied
                                          ? Colors.red.withOpacity(0.1)
                                          : Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest
                                                .withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: isDenied
                                          ? Border.all(
                                              color: Colors.red.withOpacity(
                                                0.3,
                                              ),
                                              width: 1,
                                            )
                                          : null,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          isDenied
                                              ? Icons.error_outline
                                              : Icons.info_outline,
                                          size: 16,
                                          color: isDenied
                                              ? Colors.red
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            checkIn.message!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: isDenied
                                                      ? Colors.red.shade900
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                  fontWeight: FontWeight.w500,
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
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'success':
        return 'ACTIV';
      case 'expiring':
        return 'EXPIRĂ';
      case 'expired':
        return 'EXPIRAT';
      case 'denied':
        return 'REFUZAT';
      case 'no_access':
        return 'FĂRĂ ACCES';
      case 'time_restricted':
        return 'RESTRICȚIE';
      default:
        return status.toUpperCase();
    }
  }
}

// Filter Bottom Sheet
class _FilterBottomSheet extends StatefulWidget {
  final String? selectedGymId;
  final String? selectedStatus;
  final List<Map<String, String>> gyms;
  final Function(String?, String?) onApplyFilters;
  final VoidCallback onClearFilters;

  const _FilterBottomSheet({
    required this.selectedGymId,
    required this.selectedStatus,
    required this.gyms,
    required this.onApplyFilters,
    required this.onClearFilters,
  });

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late String? _selectedGymId;
  late String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedGymId = widget.selectedGymId;
    _selectedStatus = widget.selectedStatus;
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

                          // Status Filter
                          Text(
                            'Status',
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
                                selected: _selectedStatus == null,
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() => _selectedStatus = null);
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('✅ Activ'),
                                selected: _selectedStatus == 'success',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() {
                                      _selectedStatus = selected
                                          ? 'success'
                                          : null;
                                    });
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('⚠️ Expiră'),
                                selected: _selectedStatus == 'expiring',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() {
                                      _selectedStatus = selected
                                          ? 'expiring'
                                          : null;
                                    });
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('❌ Refuzat'),
                                selected: _selectedStatus == 'denied',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() {
                                      _selectedStatus = selected
                                          ? 'denied'
                                          : null;
                                    });
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('⏰ Restricție'),
                                selected: _selectedStatus == 'time_restricted',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() {
                                      _selectedStatus = selected
                                          ? 'time_restricted'
                                          : null;
                                    });
                                  }
                                },
                              ),
                              FilterChip(
                                label: const Text('🚫 Expirat'),
                                selected: _selectedStatus == 'expired',
                                onSelected: (selected) {
                                  if (mounted) {
                                    setState(() {
                                      _selectedStatus = selected
                                          ? 'expired'
                                          : null;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
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
                                _selectedStatus,
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
