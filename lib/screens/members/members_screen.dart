import 'package:flutter/material.dart';
import 'dart:async';
import '../../models/profile.dart';
import '../../services/powersync_service.dart';
import 'member_detail_screen.dart';
import '../analytics/gold_checkins_screen.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

// Helper class to hold member data with membership info
class MemberWithDetails {
  final Profile profile;
  final String? membershipStatus;
  final String? membershipPlan;
  final DateTime? lastCheckIn;
  final String? lastCheckInGym;
  final DateTime? membershipExpiry;
  final int? daysLeft; // Can be negative if expired
  final DateTime? canceledAt;

  MemberWithDetails({
    required this.profile,
    this.membershipStatus,
    this.membershipPlan,
    this.lastCheckIn,
    this.lastCheckInGym,
    this.membershipExpiry,
    this.daysLeft,
    this.canceledAt,
  });
}

class _MembersScreenState extends State<MembersScreen> {
  List<MemberWithDetails> _members = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounceTimer;

  // Pagination
  static const int _pageSize = 20;
  int _currentPage = 1;
  bool _hasMoreData = true;
  int _totalCount = 0;

  // Filters
  String? _selectedGymId;
  String _membershipStatusFilter =
      'all'; // all, active, expiring, expired, inactive
  String _frozenStatusFilter = 'all'; // all, frozen, not_frozen
  String? _selectedPlanId; // membership plan ID filter
  int?
  _expiringInDays; // null = all expiring, 0 = today, 1 = tomorrow, 2 = day after
  DateTime? _customRegistrationDateStart;
  DateTime? _customRegistrationDateEnd;
  DateTime? _customCheckInDateStart;
  DateTime? _customCheckInDateEnd;
  final List<Map<String, String>> _gyms = [];
  final List<Map<String, String>> _membershipPlans = [];

  @override
  void initState() {
    super.initState();
    _loadGyms();
    _loadMembershipPlans();
    _loadMembers(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadGyms() async {
    try {
      await PowerSyncService.connectIfAuthenticated();
      final response = await PowerSyncService.db.getAll(
        'SELECT id, name FROM gyms ORDER BY name COLLATE NOCASE',
      );

      if (mounted)
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

      if (mounted)
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
    } catch (error) {
      print('Error loading membership plans: $error');
    }
  }

  Future<void> _loadMembers({bool reset = false}) async {
    if (reset) {
      if (mounted)
        setState(() {
          _currentPage = 1;
          _hasMoreData = true;
          _members.clear();
          _isLoading = true;
        });
    } else {
      if (!_hasMoreData || _isLoadingMore) return;
      if (mounted) setState(() => _isLoadingMore = true);
    }

    try {
      await PowerSyncService.connectIfAuthenticated();

      // Calculate offset for pagination
      final offset = (_currentPage - 1) * _pageSize;
      final whereParams = <Object?>[];
      final whereClause = _buildMembersWhereClause(whereParams);

      final totalRow = await PowerSyncService.db.get(
        _membersCountSql(whereClause),
        whereParams,
      );
      final totalCount = (totalRow['total_count'] as num? ?? 0).toInt();

      final members = await PowerSyncService.db.getAll(
        _membersSql(whereClause),
        [...whereParams, _pageSize, offset],
      );

      if (members.isEmpty) {
        if (mounted)
          setState(() {
            _hasMoreData = false;
            _isLoading = false;
            _isLoadingMore = false;
            _totalCount = totalCount;
          });
        return;
      }

      final newMembers = members.map((json) {
        final profile = Profile.fromJson({
          'id': json['id'],
          'full_name': json['full_name'] ?? '',
          'email': json['email'] ?? '',
          'phone': json['phone'],
          'created_at': json['created_at'],
          'is_admin': _sqliteBool(json['is_admin']),
          'is_employee': _sqliteBool(json['is_employee']),
          'role': 'client',
        });

        final int? daysLeft = (json['membership_days_left'] as num?)?.toInt();
        final DateTime? canceledAt = json['membership_canceled_at'] != null
            ? DateTime.parse(json['membership_canceled_at'])
            : null;

        final status = _getMembershipStatusFromData(
          hasMembership: json['membership_id'] != null,
          daysLeft: daysLeft,
          canceledAt: canceledAt,
        );

        return MemberWithDetails(
          profile: profile,
          membershipStatus: status,
          membershipPlan: json['membership_plan_name'],
          lastCheckIn: json['last_checkin_date'] != null
              ? DateTime.parse(json['last_checkin_date'])
              : null,
          lastCheckInGym: json['last_checkin_gym_name'],
          membershipExpiry: json['membership_end_date'] != null
              ? DateTime.parse(json['membership_end_date'])
              : null,
          daysLeft: daysLeft,
          canceledAt: canceledAt,
        );
      }).toList();

      if (mounted)
        setState(() {
          _members.addAll(newMembers);
          _currentPage++;
          _hasMoreData = offset + newMembers.length < totalCount;
          _totalCount = totalCount;
          _isLoading = false;
          _isLoadingMore = false;
        });
    } catch (error) {
      print('Error loading members: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare: $error')));
      }
      if (mounted)
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
    }
  }

  String _buildMembersWhereClause(List<Object?> params) {
    final clauses = <String>[];
    const daysLeftExpr =
        "COALESCE(m.days_left, CAST(julianday(m.end_date) - julianday('now', 'localtime') AS INTEGER))";

    if (_searchQuery.trim().isNotEmpty) {
      final search = '%${_searchQuery.trim().toLowerCase()}%';
      clauses.add('''
        (
          LOWER(COALESCE(p.full_name, '')) LIKE ?
          OR LOWER(COALESCE(p.phone, '')) LIKE ?
          OR LOWER(COALESCE(p.email, '')) LIKE ?
          OR LOWER(p.id) LIKE ?
        )
      ''');
      params.addAll([search, search, search, search]);
    }

    if (_selectedGymId != null) {
      clauses.add('m.sold_at_gym_id = ?');
      params.add(_selectedGymId);
    }

    if (_selectedPlanId != null) {
      clauses.add('m.plan_id = ?');
      params.add(_selectedPlanId);
    }

    switch (_membershipStatusFilter) {
      case 'active':
        clauses.add('m.id IS NOT NULL AND $daysLeftExpr > 7');
        break;
      case 'expiring':
        clauses.add('m.id IS NOT NULL AND $daysLeftExpr BETWEEN 0 AND 7');
        break;
      case 'expired':
        clauses.add('m.id IS NOT NULL AND $daysLeftExpr < 0');
        break;
      case 'inactive':
        clauses.add('m.id IS NULL');
        break;
    }

    switch (_frozenStatusFilter) {
      case 'frozen':
        clauses.add('COALESCE(m.is_frozen, 0) = 1');
        break;
      case 'not_frozen':
        clauses.add('(m.id IS NULL OR COALESCE(m.is_frozen, 0) = 0)');
        break;
    }

    if (_expiringInDays != null) {
      clauses.add('m.id IS NOT NULL AND $daysLeftExpr = ?');
      params.add(_expiringInDays);
    }

    if (_customRegistrationDateStart != null &&
        _customRegistrationDateEnd != null) {
      clauses.add(
        'datetime(p.created_at) >= datetime(?) AND datetime(p.created_at) <= datetime(?)',
      );
      params.add(_customRegistrationDateStart!.toIso8601String());
      params.add(_endOfDay(_customRegistrationDateEnd!).toIso8601String());
    }

    if (_customCheckInDateStart != null && _customCheckInDateEnd != null) {
      clauses.add('''
        EXISTS (
          SELECT 1
          FROM check_ins c
          WHERE c.user_id = p.id
            AND datetime(c.created_at) >= datetime(?)
            AND datetime(c.created_at) <= datetime(?)
        )
      ''');
      params.add(_customCheckInDateStart!.toIso8601String());
      params.add(_endOfDay(_customCheckInDateEnd!).toIso8601String());
    }

    return clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
  }

  String _membersBaseCte() {
    return '''
      WITH latest_membership AS (
        SELECT
          m.*,
          ROW_NUMBER() OVER (
            PARTITION BY m.user_id
            ORDER BY m.end_date DESC, m.created_at DESC
          ) AS rn
        FROM memberships m
      ),
      member_rows AS (
        SELECT
          p.id,
          p.full_name,
          p.email,
          p.phone,
          p.created_at,
          p.is_admin,
          p.is_employee,
          m.id AS membership_id,
          m.end_date AS membership_end_date,
          m.canceled_at AS membership_canceled_at,
          COALESCE(
            m.days_left,
            CAST(julianday(m.end_date) - julianday('now', 'localtime') AS INTEGER)
          ) AS membership_days_left,
          mp.name AS membership_plan_name,
          m.sold_at_gym_id,
          m.plan_id,
          m.is_frozen
        FROM profiles p
        LEFT JOIN latest_membership m ON m.user_id = p.id AND m.rn = 1
        LEFT JOIN membership_plans mp ON mp.id = m.plan_id
      )
    ''';
  }

  String _membersCountSql(String whereClause) {
    return '''
      ${_membersBaseCte()}
      SELECT COUNT(*) AS total_count
      FROM member_rows p
      LEFT JOIN memberships m ON m.id = p.membership_id
      $whereClause
    ''';
  }

  String _membersSql(String whereClause) {
    return '''
      ${_membersBaseCte()}
      ,
      page AS (
        SELECT p.*
        FROM member_rows p
        LEFT JOIN memberships m ON m.id = p.membership_id
        $whereClause
        ORDER BY
          CASE WHEN p.membership_id IS NULL THEN 1 ELSE 0 END,
          LOWER(COALESCE(p.full_name, ''))
        LIMIT ? OFFSET ?
      )
      SELECT
        page.*,
        (
          SELECT c.created_at
          FROM check_ins c
          WHERE c.user_id = page.id
          ORDER BY c.created_at DESC
          LIMIT 1
        ) AS last_checkin_date,
        (
          SELECT g.name
          FROM check_ins c
          LEFT JOIN gyms g ON g.id = c.gym_id
          WHERE c.user_id = page.id
          ORDER BY c.created_at DESC
          LIMIT 1
        ) AS last_checkin_gym_name
      FROM page
    ''';
  }

  bool _sqliteBool(Object? value) {
    return value == true || value == 1;
  }

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  // New status calculation based on days_left and canceled_at
  String _getMembershipStatusFromData({
    required bool hasMembership,
    int? daysLeft,
    DateTime? canceledAt,
  }) {
    if (!hasMembership) return 'Niciun abonament';
    if (canceledAt != null) return 'Anulat';
    if (daysLeft == null) return 'Activ';
    if (daysLeft < 0) return 'Expirat';
    if (daysLeft <= 7) return 'Expiră în curând';
    return 'Activ';
  }

  Color _getMembershipStatusColor(String? status) {
    switch (status) {
      case 'Activ':
        return Colors.green.shade100;
      case 'Expiră în curând':
        return Colors.orange.shade100;
      case 'Expirat':
        return Colors.red.shade100;
      case 'Anulat':
        return Colors.purple.shade100;
      case 'Inactiv':
      case 'Niciun abonament':
        return Colors.grey.shade100;
      default:
        return Colors.transparent;
    }
  }

  Color _getMembershipStatusTextColor(String? status) {
    switch (status) {
      case 'Activ':
        return Colors.green.shade800;
      case 'Expiră în curând':
        return Colors.orange.shade800;
      case 'Expirat':
        return Colors.red.shade800;
      case 'Anulat':
        return Colors.purple.shade800;
      case 'Inactiv':
      case 'Niciun abonament':
        return Colors.grey.shade800;
      default:
        return Colors.grey.shade600;
    }
  }

  String _formatShortDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    return '$day/$month/$year';
  }

  String _getStatusEmoji(String? status) {
    switch (status) {
      case 'Activ':
        return '✅';
      case 'Expiră în curând':
        return '⚠️';
      case 'Expirat':
        return '❌';
      case 'Anulat':
        return '🚫';
      case 'Inactiv':
      case 'Niciun abonament':
        return '⏸️';
      default:
        return '❓';
    }
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        selectedGymId: _selectedGymId,
        membershipStatusFilter: _membershipStatusFilter,
        frozenStatusFilter: _frozenStatusFilter,
        selectedPlanId: _selectedPlanId,
        expiringInDays: _expiringInDays,
        customRegistrationDateStart: _customRegistrationDateStart,
        customRegistrationDateEnd: _customRegistrationDateEnd,
        customCheckInDateStart: _customCheckInDateStart,
        customCheckInDateEnd: _customCheckInDateEnd,
        gyms: _gyms,
        membershipPlans: _membershipPlans,
        onApplyFilters:
            (
              gymId,
              statusFilter,
              frozenFilter,
              planId,
              expiringInDays,
              regDateStart,
              regDateEnd,
              checkInDateStart,
              checkInDateEnd,
            ) {
              if (mounted) {
                _selectedGymId = gymId;
                _membershipStatusFilter = statusFilter;
                _frozenStatusFilter = frozenFilter;
                _selectedPlanId = planId;
                _expiringInDays = expiringInDays;
                _customRegistrationDateStart = regDateStart;
                _customRegistrationDateEnd = regDateEnd;
                _customCheckInDateStart = checkInDateStart;
                _customCheckInDateEnd = checkInDateEnd;
              }
              ;
              _loadMembers(reset: true);
            },
        onClearFilters: () {
          if (mounted)
            setState(() {
              _selectedGymId = null;
              _membershipStatusFilter = 'all';
              _frozenStatusFilter = 'all';
              _selectedPlanId = null;
              _expiringInDays = null;
              _customRegistrationDateStart = null;
              _customRegistrationDateEnd = null;
              _customCheckInDateStart = null;
              _customCheckInDateEnd = null;
            });
          _loadMembers(reset: true);
        },
      ),
    );
  }

  int get _activeFiltersCount {
    int count = 0;
    if (_selectedGymId != null) count++;
    if (_membershipStatusFilter != 'all') count++;
    if (_expiringInDays != null) count++;
    if (_frozenStatusFilter != 'all') count++;
    if (_selectedPlanId != null) count++;
    if (_customRegistrationDateStart != null &&
        _customRegistrationDateEnd != null)
      count++;
    if (_customCheckInDateStart != null && _customCheckInDateEnd != null) {
      count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membri'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GoldCheckinsScreen(),
                ),
              );
            },
            tooltip: 'Analiză Gold Check-ins',
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Caută după nume, telefon, email sau ID...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          if (mounted) setState(() => _searchQuery = '');
                          _loadMembers(reset: true);
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                // Cancel previous timer
                _debounceTimer?.cancel();

                // Set new timer for 500ms
                _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    setState(() => _searchQuery = value);
                    _loadMembers(reset: true);
                  }
                });
              },
            ),
          ),
          // Member count display
          if (!_isLoading && _totalCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.people,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$_totalCount ${_totalCount == 1 ? 'membru găsit' : 'membri găsiți'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _members.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'Niciun membru'
                              : 'Niciun rezultat',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _loadMembers(reset: true),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _members.length + (_hasMoreData ? 1 : 0),
                      itemBuilder: (context, index) {
                        // Load more button
                        if (index == _members.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: _isLoadingMore
                                  ? const CircularProgressIndicator()
                                  : FilledButton.tonalIcon(
                                      onPressed: () => _loadMembers(),
                                      icon: const Icon(Icons.expand_more),
                                      label: const Text('Încarcă mai mult'),
                                    ),
                            ),
                          );
                        }

                        final member = _members[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MemberDetailScreen(
                                    member: member.profile,
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              children: [
                                // Subtle gradient background based on status
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          _getMembershipStatusColor(
                                            member.membershipStatus,
                                          ).withOpacity(0.05),
                                          _getMembershipStatusColor(
                                            member.membershipStatus,
                                          ).withOpacity(0.02),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Content
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Header: Avatar + Name + Status Badge
                                      Row(
                                        children: [
                                          // Avatar with emoji-style
                                          Container(
                                            width: 56,
                                            height: 56,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withOpacity(0.2),
                                                  Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withOpacity(0.1),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Center(
                                              child: Text(
                                                member
                                                        .profile
                                                        .fullName
                                                        .isNotEmpty
                                                    ? member.profile.fullName[0]
                                                          .toUpperCase()
                                                    : '?',
                                                style: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 24,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  member.profile.fullName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                // Status badge with emoji
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        _getMembershipStatusColor(
                                                          member
                                                              .membershipStatus,
                                                        ).withOpacity(0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        _getStatusEmoji(
                                                          member
                                                              .membershipStatus,
                                                        ),
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        member.membershipStatus ??
                                                            'Necunoscut',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: _getMembershipStatusTextColor(
                                                            member
                                                                .membershipStatus,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ],
                                      ),

                                      // Role badges if admin/employee
                                      if (member.profile.isAdmin ||
                                          member.profile.isEmployee) ...[
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            if (member.profile.isAdmin)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .secondary
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: Colors.orange
                                                        .withOpacity(0.3),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '👑',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    const Text(
                                                      'ADMIN',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.orange,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (member.profile.isEmployee)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .secondary
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: Colors.blue
                                                        .withOpacity(0.1),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '💼',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'ANGAJAT',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.blue,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],

                                      // Membership Plan Section
                                      if (member.membershipPlan != null) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceVariant
                                                .withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outlineVariant
                                                  .withOpacity(0.5),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withOpacity(0.075),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  '💳',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      member.membershipPlan!,
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    if (member
                                                            .membershipExpiry !=
                                                        null) ...[
                                                      const SizedBox(height: 2),
                                                      Row(
                                                        children: [
                                                          Text(
                                                            '⏰',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 10,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            'Expiră: ${_formatShortDate(member.membershipExpiry!)}',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],

                                      const SizedBox(height: 12),

                                      // Info Section: Last Check-in + Member Since
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceVariant
                                              .withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outlineVariant
                                                .withOpacity(0.5),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            // Last Check-in
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Text(
                                                    member.lastCheckIn != null
                                                        ? '✅'
                                                        : '⏸️',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Ultima vizită',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                        Text(
                                                          member.lastCheckIn !=
                                                                  null
                                                              ? _formatShortDate(
                                                                  member
                                                                      .lastCheckIn!,
                                                                )
                                                              : 'Niciodată',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Divider
                                            Container(
                                              height: 32,
                                              width: 1,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline
                                                  .withOpacity(0.2),
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                  ),
                                            ),

                                            // Member Since
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Text(
                                                    '📅',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Membru din',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                        ),
                                                        Text(
                                                          _formatShortDate(
                                                            member
                                                                .profile
                                                                .createdAt,
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
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
          ),
        ],
      ),
    );
  }
}

// Filter Bottom Sheet Widget
class _FilterBottomSheet extends StatefulWidget {
  final String? selectedGymId;
  final String membershipStatusFilter;
  final String frozenStatusFilter;
  final String? selectedPlanId;
  final int? expiringInDays;
  final DateTime? customRegistrationDateStart;
  final DateTime? customRegistrationDateEnd;
  final DateTime? customCheckInDateStart;
  final DateTime? customCheckInDateEnd;
  final List<Map<String, String>> gyms;
  final List<Map<String, String>> membershipPlans;
  final Function(
    String?,
    String,
    String,
    String?,
    int?,
    DateTime?,
    DateTime?,
    DateTime?,
    DateTime?,
  )
  onApplyFilters;
  final VoidCallback onClearFilters;

  const _FilterBottomSheet({
    required this.selectedGymId,
    required this.membershipStatusFilter,
    required this.frozenStatusFilter,
    required this.selectedPlanId,
    required this.expiringInDays,
    required this.customRegistrationDateStart,
    required this.customRegistrationDateEnd,
    required this.customCheckInDateStart,
    required this.customCheckInDateEnd,
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
  late String _membershipStatusFilter;
  late String _frozenStatusFilter;
  String? _selectedPlanId;
  int? _expiringInDays;
  DateTime? _customRegistrationDateStart;
  DateTime? _customRegistrationDateEnd;
  DateTime? _customCheckInDateStart;
  DateTime? _customCheckInDateEnd;

  @override
  void initState() {
    super.initState();
    _selectedGymId = widget.selectedGymId;
    _membershipStatusFilter = widget.membershipStatusFilter;
    _frozenStatusFilter = widget.frozenStatusFilter;
    _selectedPlanId = widget.selectedPlanId;
    _expiringInDays = widget.expiringInDays;
    _customRegistrationDateStart = widget.customRegistrationDateStart;
    _customRegistrationDateEnd = widget.customRegistrationDateEnd;
    _customCheckInDateStart = widget.customCheckInDateStart;
    _customCheckInDateEnd = widget.customCheckInDateEnd;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context), // Tap anywhere in padding to dismiss
      child: Container(
        color: Colors.transparent, // Transparent but tappable
        child: GestureDetector(
          onTap: () {}, // Prevent taps from bubbling through the content
          child: Container(
            margin: const EdgeInsets.only(
              top: 120,
            ), // Space at top for easier dismissal
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar with extra spacing for easier closing
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 12),
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),

                // Rest of content inside SafeArea
                Flexible(
                  child: SafeArea(
                    top:
                        false, // Don't apply safe area to top since we have margin
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.filter_list,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Filtre',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () {
                                  if (mounted) {
                                    setState(() {
                                      _selectedGymId = null;
                                      _membershipStatusFilter = 'all';
                                      _frozenStatusFilter = 'all';
                                      _selectedPlanId = null;
                                      _customRegistrationDateStart = null;
                                      _customRegistrationDateEnd = null;
                                      _customCheckInDateStart = null;
                                      _customCheckInDateEnd = null;
                                    });
                                  }
                                },
                                child: const Text('Resetează'),
                              ),
                            ],
                          ),
                        ),

                        const Divider(height: 1),

                        // Filter content
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Gym Filter
                                Text(
                                  'Sală',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
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
                                      showCheckmark: false,
                                    ),
                                    ...widget.gyms.map(
                                      (gym) => FilterChip(
                                        label: Text(gym['name']!),
                                        selected: _selectedGymId == gym['id'],
                                        onSelected: (selected) {
                                          if (mounted) {
                                            setState(() {
                                              _selectedGymId = selected
                                                  ? gym['id']
                                                  : null;
                                            });
                                          }
                                        },
                                        showCheckmark: false,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 32),

                                // Membership Status Filter
                                Text(
                                  'Status Abonament',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilterChip(
                                      label: const Text('Toate'),
                                      selected:
                                          _membershipStatusFilter == 'all',
                                      onSelected: (selected) {
                                        if (mounted) {
                                          setState(() {
                                            _membershipStatusFilter = 'all';
                                            _expiringInDays = null;
                                          });
                                        }
                                      },
                                      showCheckmark: false,
                                    ),
                                    FilterChip(
                                      label: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check_circle,
                                            size: 16,
                                            color: Colors.green,
                                          ),
                                          SizedBox(width: 4),
                                          Text('Activ'),
                                        ],
                                      ),
                                      selected:
                                          _membershipStatusFilter == 'active',
                                      onSelected: (selected) {
                                        if (mounted) {
                                          setState(() {
                                            _membershipStatusFilter = 'active';
                                            _expiringInDays = null;
                                          });
                                        }
                                      },
                                      showCheckmark: false,
                                    ),
                                    FilterChip(
                                      label: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.warning_amber,
                                            size: 16,
                                            color: Colors.orange,
                                          ),
                                          SizedBox(width: 4),
                                          Text('Expiră în curând'),
                                        ],
                                      ),
                                      selected:
                                          _membershipStatusFilter == 'expiring',
                                      onSelected: (selected) {
                                        if (mounted) {
                                          setState(
                                            () => _membershipStatusFilter =
                                                'expiring',
                                          );
                                        }
                                      },
                                      showCheckmark: false,
                                    ),
                                    FilterChip(
                                      label: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.cancel,
                                            size: 16,
                                            color: Colors.red,
                                          ),
                                          SizedBox(width: 4),
                                          Text('Expirat'),
                                        ],
                                      ),
                                      selected:
                                          _membershipStatusFilter == 'expired',
                                      onSelected: (selected) {
                                        if (mounted) {
                                          setState(() {
                                            _membershipStatusFilter = 'expired';
                                            _expiringInDays = null;
                                          });
                                        }
                                      },
                                      showCheckmark: false,
                                    ),
                                    FilterChip(
                                      label: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.no_accounts,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(width: 4),
                                          Text('Fără abonament'),
                                        ],
                                      ),
                                      selected:
                                          _membershipStatusFilter == 'inactive',
                                      onSelected: (selected) {
                                        if (mounted) {
                                          setState(() {
                                            _membershipStatusFilter =
                                                'inactive';
                                            _expiringInDays = null;
                                          });
                                        }
                                      },
                                      showCheckmark: false,
                                    ),
                                    FilterChip(
                                      label: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.block,
                                            size: 16,
                                            color: Colors.purple,
                                          ),
                                          SizedBox(width: 4),
                                          Text('Anulat'),
                                        ],
                                      ),
                                      selected:
                                          _membershipStatusFilter == 'canceled',
                                      onSelected: (selected) {
                                        if (mounted) {
                                          setState(() {
                                            _membershipStatusFilter =
                                                'canceled';
                                            _expiringInDays = null;
                                          });
                                        }
                                      },
                                      showCheckmark: false,
                                    ),
                                  ],
                                ),

                                // Expiring Days Filter (shown when "Expiră în curând" is selected)
                                if (_membershipStatusFilter == 'expiring') ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    'Expiră în',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilterChip(
                                        label: const Text('Toate (≤7 zile)'),
                                        selected: _expiringInDays == null,
                                        onSelected: (selected) {
                                          if (mounted) {
                                            setState(
                                              () => _expiringInDays = null,
                                            );
                                          }
                                        },
                                        showCheckmark: false,
                                      ),
                                      FilterChip(
                                        label: const Text('Azi'),
                                        selected: _expiringInDays == 0,
                                        onSelected: (selected) {
                                          if (mounted) {
                                            setState(() => _expiringInDays = 0);
                                          }
                                        },
                                        showCheckmark: false,
                                      ),
                                      FilterChip(
                                        label: const Text('Mâine'),
                                        selected: _expiringInDays == 1,
                                        onSelected: (selected) {
                                          if (mounted) {
                                            setState(() => _expiringInDays = 1);
                                          }
                                        },
                                        showCheckmark: false,
                                      ),
                                      FilterChip(
                                        label: const Text('Poimâine'),
                                        selected: _expiringInDays == 2,
                                        onSelected: (selected) {
                                          if (mounted) {
                                            setState(() => _expiringInDays = 2);
                                          }
                                        },
                                        showCheckmark: false,
                                      ),
                                      FilterChip(
                                        label: const Text('În 3 zile'),
                                        selected: _expiringInDays == 3,
                                        onSelected: (selected) {
                                          if (mounted) {
                                            setState(() => _expiringInDays = 3);
                                          }
                                        },
                                        showCheckmark: false,
                                      ),
                                    ],
                                  ),
                                ],

                                const SizedBox(height: 32),

                                // Frozen Status Filter
                                Text(
                                  'Status Îngheț',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilterChip(
                                      label: const Text('Toate'),
                                      selected: _frozenStatusFilter == 'all',
                                      onSelected: (selected) {
                                        if (mounted) {
                                          setState(
                                            () => _frozenStatusFilter = 'all',
                                          );
                                        }
                                      },
                                      showCheckmark: false,
                                    ),
                                    FilterChip(
                                      label: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.check,
                                            size: 16,
                                            color: Colors.green,
                                          ),
                                          SizedBox(width: 4),
                                          Text('Nu'),
                                        ],
                                      ),
                                      selected:
                                          _frozenStatusFilter == 'not_frozen',
                                      onSelected: (selected) {
                                        if (mounted) {
                                          setState(
                                            () => _frozenStatusFilter =
                                                'not_frozen',
                                          );
                                        }
                                      },
                                      showCheckmark: false,
                                    ),
                                    FilterChip(
                                      label: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.ac_unit,
                                            size: 16,
                                            color: Colors.blue,
                                          ),
                                          SizedBox(width: 4),
                                          Text('Da'),
                                        ],
                                      ),
                                      selected: _frozenStatusFilter == 'frozen',
                                      onSelected: (selected) {
                                        if (mounted) {
                                          setState(
                                            () =>
                                                _frozenStatusFilter = 'frozen',
                                          );
                                        }
                                      },
                                      showCheckmark: false,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 32),

                                // Membership Plan Filter
                                Text(
                                  'Tip Abonament',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  value: _selectedPlanId,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.card_membership,
                                    ),
                                  ),
                                  hint: const Text('Toate abonamentele'),
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text('Toate abonamentele'),
                                    ),
                                    ...widget.membershipPlans.map(
                                      (plan) => DropdownMenuItem<String>(
                                        value: plan['id'],
                                        child: Text(plan['name']!),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (mounted) {
                                      setState(() => _selectedPlanId = value);
                                    }
                                  },
                                ),

                                const SizedBox(height: 32),

                                // Registration Date Filter
                                Text(
                                  'Data Înregistrării',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await _selectRegistrationDateRange();
                                  },
                                  icon: const Icon(Icons.date_range),
                                  label: Text(
                                    _customRegistrationDateStart != null &&
                                            _customRegistrationDateEnd != null
                                        ? '${_formatDate(_customRegistrationDateStart!)} - ${_formatDate(_customRegistrationDateEnd!)}'
                                        : 'Selectează interval',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                if (_customRegistrationDateStart != null &&
                                    _customRegistrationDateEnd != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: TextButton.icon(
                                      onPressed: () {
                                        if (mounted) {
                                          setState(() {
                                            _customRegistrationDateStart = null;
                                            _customRegistrationDateEnd = null;
                                          });
                                        }
                                      },
                                      icon: const Icon(Icons.clear, size: 16),
                                      label: const Text('Șterge filtru'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                  ),

                                const SizedBox(height: 32),

                                // Check-in Activity Filter
                                Text(
                                  'Activitate Check-in',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await _selectCheckInDateRange();
                                  },
                                  icon: const Icon(Icons.date_range),
                                  label: Text(
                                    _customCheckInDateStart != null &&
                                            _customCheckInDateEnd != null
                                        ? '${_formatDate(_customCheckInDateStart!)} - ${_formatDate(_customCheckInDateEnd!)}'
                                        : 'Selectează interval',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                if (_customCheckInDateStart != null &&
                                    _customCheckInDateEnd != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: TextButton.icon(
                                      onPressed: () {
                                        if (mounted) {
                                          setState(() {
                                            _customCheckInDateStart = null;
                                            _customCheckInDateEnd = null;
                                          });
                                        }
                                      },
                                      icon: const Icon(Icons.clear, size: 16),
                                      label: const Text('Șterge filtru'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // Action buttons
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceVariant.withOpacity(0.3),
                            border: Border(
                              top: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    widget.onClearFilters();
                                    Navigator.pop(context);
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  child: const Text('Anulează'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    widget.onApplyFilters(
                                      _selectedGymId,
                                      _membershipStatusFilter,
                                      _frozenStatusFilter,
                                      _selectedPlanId,
                                      _expiringInDays,
                                      _customRegistrationDateStart,
                                      _customRegistrationDateEnd,
                                      _customCheckInDateStart,
                                      _customCheckInDateEnd,
                                    );
                                    Navigator.pop(context);
                                  },
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  child: const Text('Aplică Filtre'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectRegistrationDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      currentDate: DateTime.now(),
      initialDateRange:
          _customRegistrationDateStart != null &&
              _customRegistrationDateEnd != null
          ? DateTimeRange(
              start: _customRegistrationDateStart!,
              end: _customRegistrationDateEnd!,
            )
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      if (mounted) {
        setState(() {
          _customRegistrationDateStart = picked.start;
          _customRegistrationDateEnd = picked.end;
        });
      }
    }
  }

  Future<void> _selectCheckInDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      currentDate: DateTime.now(),
      initialDateRange:
          _customCheckInDateStart != null && _customCheckInDateEnd != null
          ? DateTimeRange(
              start: _customCheckInDateStart!,
              end: _customCheckInDateEnd!,
            )
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      if (mounted) {
        setState(() {
          _customCheckInDateStart = picked.start;
          _customCheckInDateEnd = picked.end;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
}
