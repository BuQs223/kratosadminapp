import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/profile.dart';
import '../../models/membership.dart';
import '../../models/check_in.dart';
import '../../services/supabase_service.dart';
import '../../widgets/membership_form_dialog.dart';
import 'member_history_screen.dart';

class MemberDetailScreen extends StatefulWidget {
  final Profile member;

  const MemberDetailScreen({super.key, required this.member});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen>
    with SingleTickerProviderStateMixin {
  late Profile _currentMember;
  List<Membership> _memberships = [];
  List<CheckIn> _checkIns = [];
  bool _isLoadingMemberships = true;
  bool _isLoadingCheckIns = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _currentMember = widget.member;
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadMemberships(), _loadCheckIns()]);
  }

  Future<void> _loadMemberships() async {
    if (mounted) {
      setState(() => _isLoadingMemberships = true);
    }

    try {
      final supabase = SupabaseService.client;

      final response = await supabase.rpc(
        'get_user_memberships_optimized',
        params: {'p_user_id': _currentMember.id},
      );

      if (mounted) {
        setState(() {
          _memberships = (response as List)
              .map((json) => Membership.fromOptimizedJson(json))
              .toList();
          _isLoadingMemberships = false;
        });
      }
    } catch (error) {
      print('Error loading memberships: $error');
      if (mounted) {
        setState(() => _isLoadingMemberships = false);
      }
    }
  }

  Future<void> _loadCheckIns() async {
    if (mounted) {
      setState(() => _isLoadingCheckIns = true);
    }

    try {
      final supabase = SupabaseService.client;

      // Query check-ins directly for this user
      // Note: check_ins doesn't have FK to profiles, only to gyms
      final response = await supabase
          .from('check_ins')
          .select('''
            *,
            gyms!check_ins_gym_id_fkey(id, name)
          ''')
          .eq('user_id', _currentMember.id)
          .order('created_at', ascending: false)
          .limit(50);

      final checkIns = (response as List)
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
                // Manually add profile since we already have it
                'profiles': {
                  'id': _currentMember.id,
                  'full_name': _currentMember.fullName,
                },
                'gyms': row['gyms'],
              });
            } catch (e) {
              print('Error parsing check-in: $e');
              print('Row data: $row');
              return null;
            }
          })
          .whereType<CheckIn>()
          .toList();

      if (mounted) {
        setState(() {
          _checkIns = checkIns;
          _isLoadingCheckIns = false;
        });
      }
    } catch (error) {
      print('Error loading check-ins: $error');
      if (mounted) {
        setState(() => _isLoadingCheckIns = false);
      }
    }
  }

  void _showEditNameBottomSheet() {
    final controller = TextEditingController(text: _currentMember.fullName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.only(top: 120),
              child: DraggableScrollableSheet(
                initialChildSize: 0.3,
                minChildSize: 0.2,
                maxChildSize: 0.4,
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
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Editează Nume',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Divider(height: 1),
                        // Content
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.only(
                              top: 16,
                              left: 16,
                              right: 16,
                            ),
                            children: [
                              TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                  labelText: 'Nume complet',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.person_outline),
                                ),

                                textCapitalization: TextCapitalization.words,
                              ),
                            ],
                          ),
                        ),
                        // Buttons
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: 16,
                            left: 16,
                            right: 16,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Anulează'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    final newName = controller.text.trim();
                                    if (newName.isNotEmpty &&
                                        newName != _currentMember.fullName) {
                                      Navigator.pop(context);
                                      _updateMemberName(newName);
                                    }
                                  },
                                  child: const Text('Salvează'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateMemberName(String newName) async {
    try {
      await SupabaseService.client
          .from('profiles')
          .update({'full_name': newName})
          .eq('id', _currentMember.id);

      if (mounted) {
        setState(() {
          _currentMember = _currentMember.copyWith(fullName: newName);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Numele a fost actualizat'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare: $error')));
      }
    }
  }

  void _showAddMembershipDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: MembershipFormDialog(memberId: _currentMember.id),
      ),
    ).then((result) {
      if (result == true) {
        _loadMemberships();
      }
    });
  }

  void _showEditMembershipDialog(Membership membership) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: MembershipFormDialog(
          memberId: _currentMember.id,
          membership: membership,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _loadMemberships();
      }
    });
  }

  Future<void> _deleteMembership(Membership membership) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Șterge Abonament'),
        content: Text(
          'Sigur vrei să ștergi abonamentul "${membership.plan?.name ?? 'Unknown'}"?\n\nAceasta va șterge și înregistrarea din registrul de venituri.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Șterge'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final supabase = SupabaseService.client;

      // Delete revenue ledger entry first (foreign key constraint)
      await supabase
          .from('revenue_ledger')
          .delete()
          .eq('membership_id', membership.id);

      // Delete check-ins associated with this membership
      await supabase
          .from('check_ins')
          .delete()
          .eq('membership_id', membership.id);

      // Delete the membership
      await supabase.from('memberships').delete().eq('id', membership.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Abonamentul a fost șters'),
            backgroundColor: Colors.green,
          ),
        );
        _loadMemberships();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare: $error')));
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  String _formatDateTime(DateTime dateTime) {
    // Convert to local time (Bucharest timezone)
    final localDateTime = dateTime.toLocal();
    return DateFormat('dd MMM yyyy, HH:mm').format(localDateTime);
  }

  @override
  Widget build(BuildContext context) {
    // Active = not canceled and days_left >= 0
    final activeMemberships = _memberships
        .where((m) => !m.isCanceled && !m.isExpired && !m.isFrozen)
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: Column(
        children: [
          // Header with gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surfaceContainer,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // App bar
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context),
                        ),
                       
                      ],
                    ),
                  ),
                  // Member info
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              _currentMember.fullName.isNotEmpty
                                  ? _currentMember.fullName[0].toUpperCase()
                                  : '?',
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Name and status
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _currentMember.fullName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _showEditNameBottomSheet,
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Editează nume',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: activeMemberships.isNotEmpty
                                      ? Colors.green.withOpacity(0.2)
                                      : Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  activeMemberships.isNotEmpty
                                      ? '✅ ${activeMemberships.length} Activ${activeMemberships.length > 1 ? 'e' : ''}'
                                      : '⚠️ Fără abonament',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: activeMemberships.isNotEmpty
                                            ? Colors.green.shade900
                                            : Colors.orange.shade900,
                                      ),
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
          ),

          // Info Cards
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Info Row
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoCard(
                        'Membru din',
                        _formatDate(_currentMember.createdAt),
                        Icons.calendar_today,
                        const Color(0xFF8E24AA),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoCard(
                        'Client ID',
                        _currentMember.id.substring(0, 8),
                        Icons.fingerprint,
                        const Color(0xFF1E88E5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // History Page
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            MemberHistoryScreen(member: _currentMember),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.history, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Vezi istoricul complet al membrului',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Tabs
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    dividerHeight: 0,
                    labelColor: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer,
                    unselectedLabelColor: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.card_membership, size: 18),
                            const SizedBox(width: 8),
                            Text('Abonamente (${_memberships.length})'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_outline, size: 18),
                            const SizedBox(width: 8),
                            Text('Check-ins (${_checkIns.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildMembershipsTab(), _buildCheckInsTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (label == 'Client ID') {
            Clipboard.setData(ClipboardData(text: _currentMember.id));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('ID copiat')));
          }
        },
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
                    colors: [color.withOpacity(0.05), color.withOpacity(0.02)],
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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFamily: label == 'Client ID' ? 'monospace' : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color,
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

  Widget _buildMembershipsTab() {
    if (_isLoadingMemberships) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_memberships.isEmpty) {
      return Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.card_membership_outlined,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                ),
                const SizedBox(height: 24),
                Text(
                  'Niciun abonament',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Acest membru nu are abonamente',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _showAddMembershipDialog,
              child: const Icon(Icons.add),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _memberships.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final membership = _memberships[index];

            Color statusColor;
            String statusEmoji;

            if (membership.isCanceled) {
              statusColor = const Color(0xFF7B1FA2); // Purple for canceled
              statusEmoji = '🚫';
            } else if (membership.isFrozen) {
              statusColor = const Color(0xFF1E88E5); // Blue for frozen
              statusEmoji = '❄️';
            } else if (membership.isExpired) {
              statusColor = const Color(0xFFE53935); // Red for expired
              statusEmoji = '❌';
            } else {
              // Active - check days left for expiring soon
              final days = membership.daysLeft ?? membership.daysUntilExpiry;
              if (days <= 7) {
                statusColor = const Color(
                  0xFFFB8C00,
                ); // Orange for expiring soon
                statusEmoji = '⚠️';
              } else {
                statusColor = const Color(0xFF43A047); // Green for active
                statusEmoji = '✅';
              }
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
                        Row(
                          children: [
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
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    membership.plan?.name ?? 'Unknown',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    membership.statusText,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: statusColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.edit, color: statusColor),
                              onPressed: () =>
                                  _showEditMembershipDialog(membership),
                              tooltip: 'Editează',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteMembership(membership),
                              tooltip: 'Șterge',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${_formatDate(membership.actualStartDate)} - ${_formatDate(membership.endDate)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                            if (membership.gym != null)
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
                                    membership.gym!.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            if (!membership.isCanceled &&
                                !membership.isExpired &&
                                (membership.daysLeft ??
                                        membership.daysUntilExpiry) >=
                                    0)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.timer,
                                    size: 16,
                                    color:
                                        (membership.daysLeft ??
                                                membership.daysUntilExpiry) <=
                                            7
                                        ? Colors.orange
                                        : Colors.green,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${membership.daysLeft ?? membership.daysUntilExpiry}z rămase',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color:
                                              (membership.daysLeft ??
                                                      membership
                                                          .daysUntilExpiry) <=
                                                  7
                                              ? Colors.orange
                                              : Colors.green,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: _showAddMembershipDialog,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckInsTab() {
    if (_isLoadingCheckIns) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_checkIns.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'Niciun check-in',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Check-in-urile vor apărea aici',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _checkIns.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final checkIn = _checkIns[index];
        final isSuccess = checkIn.status == 'success';
        final isExpiring = checkIn.status == 'expiring';
        final isDenied =
            checkIn.status == 'denied' ||
            checkIn.status == 'expired' ||
            checkIn.status == 'no_access';

        Color statusColor;
        String statusEmoji;

        if (isSuccess) {
          statusColor = const Color(0xFF43A047);
          statusEmoji = '✅';
        } else if (isExpiring) {
          statusColor = const Color(0xFFFB8C00);
          statusEmoji = '⚠️';
        } else if (isDenied) {
          statusColor = const Color(0xFFE53935);
          statusEmoji = '❌';
        } else {
          statusColor = const Color(0xFF1E88E5);
          statusEmoji = '⏰';
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
          child: Stack(
            children: [
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
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                checkIn.gym?.name ?? 'Unknown',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDateTime(checkIn.checkedInAt),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isDenied
                                  ? Icons.error_outline
                                  : Icons.info_outline,
                              size: 16,
                              color: isDenied ? Colors.red : statusColor,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                checkIn.message!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w500),
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
        );
      },
    );
  }
}
