import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/profile.dart';
import '../../models/membership.dart';
import '../../models/check_in.dart';
import '../../services/supabase_service.dart';
import '../../widgets/membership_form_dialog.dart';

class MemberDetailScreen extends StatefulWidget {
  final Profile member;

  const MemberDetailScreen({super.key, required this.member});

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  List<Membership> _memberships = [];
  List<CheckIn> _checkIns = [];
  bool _isLoadingMemberships = true;
  bool _isLoadingCheckIns = true;
  late Profile _currentMember;

  @override
  void initState() {
    super.initState();
    _currentMember = widget.member;
    _loadMemberships();
    _loadCheckIns();
  }

  Future<void> _loadMemberships() async {
    setState(() => _isLoadingMemberships = true);

    try {
      final supabase = SupabaseService.client;

      // Try optimized RPC function first
      try {
        final response = await supabase.rpc(
          'get_user_memberships_optimized',
          params: {'p_user_id': widget.member.id},
        );

        // Debug: print raw response
        print('RPC response type: ${response.runtimeType}');
        if (response is List && response.isNotEmpty) {
          print(
            'First membership JSON keys: ${(response[0] as Map).keys.toList()}',
          );
          print('First membership sample data: ${response[0]}');
        }

        setState(() {
          _memberships = (response as List)
              .map((json) => Membership.fromOptimizedJson(json))
              .toList();
          _isLoadingMemberships = false;
        });

        // Debug logging
        print('Loaded ${_memberships.length} memberships (optimized):');
        for (var m in _memberships) {
          print(
            '  Membership ID: "${m.id}", User: "${m.userId}", Plan: "${m.planId}"',
          );
        }

        return; // Success, exit early
      } catch (rpcError) {
        print('Optimized membership query failed: $rpcError');
      }

      // Fallback to direct query with joins
      final response = await supabase
          .from('memberships')
          .select('''
            *,
            membership_plans!inner(
              id,
              name,
              plan_kind,
              tier,
              monthly_price_cents,
              is_family_plan
            ),
            gyms(
              id,
              name,
              address,
              city
            )
          ''')
          .eq('user_id', widget.member.id)
          .order('created_at', ascending: false);

      setState(() {
        _memberships = (response as List)
            .map((json) => Membership.fromJson(json))
            .toList();
        _isLoadingMemberships = false;
      });

      // Debug logging
      print('Loaded ${_memberships.length} memberships (fallback):');
      for (var m in _memberships) {
        print(
          '  Membership ID: "${m.id}", User: "${m.userId}", Plan: "${m.planId}"',
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la încărcarea abonamentelor: $error')),
        );
      }
      setState(() => _isLoadingMemberships = false);
    }
  }

  Future<void> _loadCheckIns() async {
    setState(() => _isLoadingCheckIns = true);

    try {
      final supabase = SupabaseService.client;
      final response = await supabase
          .from('check_ins')
          .select('''
            *,
            gyms!inner(
              id,
              name,
              address,
              city
            )
          ''')
          .eq('user_id', widget.member.id)
          .order('created_at', ascending: false)
          .limit(50);

      setState(() {
        _checkIns = (response as List)
            .where((json) => json != null) // Filter out null entries
            .map((json) {
              try {
                return CheckIn.fromJson(json as Map<String, dynamic>);
              } catch (e) {
                print('Error parsing check-in: $e, JSON: $json');
                return null;
              }
            })
            .where((checkIn) => checkIn != null) // Filter out failed parses
            .cast<CheckIn>()
            .toList();
        _isLoadingCheckIns = false;
      });
    } catch (error) {
      print('Check-ins loading error: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Eroare la încărcarea check-in-urilor: $error'),
          ),
        );
      }
      setState(() => _isLoadingCheckIns = false);
    }
  }

  Future<void> _showEditNameBottomSheet() async {
    final currentUser = SupabaseService.currentUser;
    if (currentUser == null) return;

    final currentProfile = await SupabaseService.client
        .from('profiles')
        .select('is_admin')
        .eq('id', currentUser.id)
        .single();

    if (!(currentProfile['is_admin'] as bool? ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Doar administratorii pot edita numele membrilor'),
          ),
        );
      }
      return;
    }

    final controller = TextEditingController(text: _currentMember.fullName);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editează Nume',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Nume complet',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Anulează'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, controller.text.trim()),
                  child: const Text('Salvează'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (result != null &&
        result.isNotEmpty &&
        result != _currentMember.fullName) {
      await _updateMemberName(result);
    }
  }

  Future<void> _updateMemberName(String newName) async {
    try {
      await SupabaseService.client
          .from('profiles')
          .update({'full_name': newName})
          .eq('id', _currentMember.id);

      setState(() {
        _currentMember = _currentMember.copyWith(fullName: newName);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Numele a fost actualizat cu succes')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la actualizarea numelui: $error')),
        );
      }
    }
  }

  Future<bool> _checkIsCurrentUserAdmin() async {
    try {
      final currentUser = SupabaseService.currentUser;
      if (currentUser == null) return false;

      final currentProfile = await SupabaseService.client
          .from('profiles')
          .select('is_admin')
          .eq('id', currentUser.id)
          .single();

      return currentProfile['is_admin'] as bool? ?? false;
    } catch (error) {
      return false;
    }
  }

  Future<void> _showAddMembershipDialog() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MembershipFormDialog(memberId: widget.member.id),
    );

    if (result == true) {
      _loadMemberships();
    }
  }

  Future<void> _showEditMembershipDialog(Membership membership) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MembershipFormDialog(
        memberId: widget.member.id,
        membership: membership,
      ),
    );

    if (result == true) {
      _loadMemberships();
    }
  }

  Future<void> _deleteMembership(Membership membership) async {
    // Debug logging
    print('Attempting to delete membership:');
    print('  ID: "${membership.id}"');
    print('  ID isEmpty: ${membership.id.isEmpty}');
    print('  ID length: ${membership.id.length}');
    print('  User ID: ${membership.userId}');
    print('  Plan ID: ${membership.planId}');

    // Validate membership ID before showing confirmation
    if (membership.id.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Eroare: ID abonament invalid'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Șterge abonament',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Sigur vrei să ștergi acest abonament? Această acțiune va șterge și toate înregistrările asociate (plăți, check-in-uri) și nu poate fi anulată.',
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Anulează'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.errorContainer,
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onErrorContainer,
                  ),
                  child: const Text('Șterge'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final supabase = SupabaseService.client;

      // Delete in proper order due to foreign key constraints
      // Only delete if membership.id is valid (not empty)
      if (membership.id.isEmpty) {
        throw Exception('Invalid membership ID');
      }

      // 1. Delete revenue ledger entries (nullable membership_id)
      try {
        // Check if records exist first
        final revenueRecords =
            await supabase
                    .from('revenue_ledger')
                    .select('id')
                    .eq('membership_id', membership.id)
                as List;

        if (revenueRecords.isNotEmpty) {
          await supabase
              .from('revenue_ledger')
              .delete()
              .eq('membership_id', membership.id);
          print('Deleted ${revenueRecords.length} revenue_ledger entries');
        }
      } catch (e) {
        print('Error deleting revenue ledger entries: $e');
        // Continue even if no revenue entries exist
      }

      // 2. Delete family memberships (may not exist)
      try {
        final familyRecords =
            await supabase
                    .from('family_memberships')
                    .select('id')
                    .eq('membership_id', membership.id)
                as List;

        if (familyRecords.isNotEmpty) {
          await supabase
              .from('family_memberships')
              .delete()
              .eq('membership_id', membership.id);
          print('Deleted ${familyRecords.length} family_memberships');
        }
      } catch (e) {
        print('Error deleting family memberships: $e');
        // Continue even if no family memberships exist
      }

      // 3. Delete check-ins associated with this membership (may not exist)
      try {
        final checkInRecords =
            await supabase
                    .from('check_ins')
                    .select('id')
                    .eq('membership_id', membership.id)
                as List;

        if (checkInRecords.isNotEmpty) {
          await supabase
              .from('check_ins')
              .delete()
              .eq('membership_id', membership.id);
          print('Deleted ${checkInRecords.length} check_ins');
        }
      } catch (e) {
        print('Error deleting check-ins: $e');
        // Continue even if no check-ins exist
      }

      // 4. Finally delete the membership itself
      await supabase.from('memberships').delete().eq('id', membership.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Abonament șters cu succes'),
            backgroundColor: Colors.green,
          ),
        );
        _loadMemberships();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Eroare la ștergerea abonamentului: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('dd MMM yyyy, HH:mm').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    final activeMemberships = _memberships.where((m) => m.isActive).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentMember.fullName),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _showAddMembershipDialog,
            icon: const Icon(Icons.add),
            tooltip: 'Adaugă abonament',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              _buildHeaderSection(activeMemberships),

              const SizedBox(height: 24),

              // Content based on screen size
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 1000) {
                    // Desktop/Tablet layout - side by side
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sidebar
                        Expanded(flex: 1, child: _buildSidebar()),
                        const SizedBox(width: 24),
                        // Main content
                        Expanded(
                          flex: 2,
                          child: _buildMainContent(activeMemberships),
                        ),
                      ],
                    );
                  } else {
                    // Mobile layout - stacked
                    return Column(
                      children: [
                        _buildSidebar(),
                        const SizedBox(height: 24),
                        _buildMainContent(activeMemberships),
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection(List<Membership> activeMemberships) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person,
                size: 40,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 20),

            // Info and Badges
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _currentMember.fullName,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      // Admin edit button
                      FutureBuilder<bool>(
                        future: _checkIsCurrentUserAdmin(),
                        builder: (context, snapshot) {
                          if (snapshot.data == true) {
                            return IconButton(
                              onPressed: _showEditNameBottomSheet,
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Editează nume',
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Profil Client și Gestionare Abonamente',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_currentMember.isAdmin)
                        const Chip(
                          avatar: Icon(
                            Icons.admin_panel_settings_outlined,
                            size: 18,
                          ),
                          label: Text('Administrator'),
                          side: BorderSide.none,
                        ),
                      if (_currentMember.isEmployee)
                        const Chip(
                          avatar: Icon(Icons.badge_outlined, size: 18),
                          label: Text('Angajat'),
                          side: BorderSide.none,
                        ),

                      // Active memberships badge
                      Chip(
                        avatar: Icon(
                          activeMemberships.isNotEmpty
                              ? Icons.workspace_premium_outlined
                              : Icons.do_not_disturb_alt_outlined,
                          size: 18,
                        ),
                        label: Text(
                          activeMemberships.isNotEmpty
                              ? '${activeMemberships.length} Abonament${activeMemberships.length > 1 ? 'e' : ''} Activ${activeMemberships.length > 1 ? 'e' : ''}'
                              : 'Fără Abonament Activ',
                        ),
                        side: BorderSide.none,
                        backgroundColor: activeMemberships.isNotEmpty
                            ? Theme.of(
                                context,
                              ).colorScheme.primaryContainer.withOpacity(0.5)
                            : Theme.of(
                                context,
                              ).colorScheme.secondaryContainer.withOpacity(0.5),
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

  Widget _buildSidebar() {
    return Column(
      children: [
        // Personal Information Card
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
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
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Informații Personale',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Contact info
                _buildContactInfo(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactInfo() {
    return Column(
      children: [
        if (_currentMember.email.isNotEmpty)
          ListTile(
            leading: Icon(
              Icons.email_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(_currentMember.email),
            contentPadding: EdgeInsets.zero,
          ),
        if (_currentMember.phone != null &&
            _currentMember.phone!.isNotEmpty) ...[
          if (_currentMember.email.isNotEmpty) const SizedBox(height: 4),
          ListTile(
            leading: Icon(
              Icons.phone_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            title: Text(_currentMember.phone!),
            contentPadding: EdgeInsets.zero,
          ),
        ],
        const Divider(height: 24),
        ListTile(
          leading: Icon(
            Icons.calendar_today_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: const Text('Membru din'),
          trailing: Text(
            _formatDate(_currentMember.createdAt),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        ListTile(
          leading: Icon(
            Icons.fingerprint_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: const Text('ID Client'),
          trailing: Text(
            '${_currentMember.id.substring(0, 8)}...',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildInlineStat({
    required BuildContext context,
    required String count,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          count,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildMainContent(List<Membership> activeMemberships) {
    return Column(
      children: [
        // Memberships Section
        _buildMembershipsSection(activeMemberships),

        const SizedBox(height: 24),

        // Check-ins Section
        _buildCheckInsSection(),
      ],
    );
  }

  Widget _buildMembershipsSection(List<Membership> activeMemberships) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Abonamente',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                FilledButton.tonalIcon(
                  onPressed: _showAddMembershipDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adaugă'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _buildInlineStat(
                  context: context,
                  count: '${activeMemberships.length}',
                  label: 'Active',
                  color: Colors.green,
                  icon: Icons.card_membership_outlined,
                ),
                _buildInlineStat(
                  context: context,
                  count: '${_memberships.length}',
                  label: 'Totale',
                  color: Colors.blue,
                  icon: Icons.history_outlined,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _isLoadingMemberships
                ? const Center(child: CircularProgressIndicator())
                : _buildMembershipsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckInsSection() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Check-ins Recente',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildInlineStat(
              context: context,
              count: '${_checkIns.length}',
              label: 'Intrări Totale',
              color: Colors.purple,
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: 12),
            _isLoadingCheckIns
                ? const Center(child: CircularProgressIndicator())
                : _buildCheckInsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildMembershipsTab() {
    if (_memberships.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.card_membership,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Niciun abonament',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Apasă "Adaugă" pentru a crea primul abonament',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _memberships.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final membership = _memberships[index];
        final isActive = membership.isActive;
        final isExpired = membership.isExpired;

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: InkWell(
            onTap: () => _showEditMembershipDialog(membership),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          membership.plan?.name ?? 'Unknown Plan',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Chip(
                        label: Text(membership.statusText),
                        labelStyle: TextStyle(
                          color: isActive
                              ? Colors.green.shade800
                              : isExpired
                              ? Colors.red.shade800
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                        backgroundColor: isActive
                            ? Colors.green.shade100
                            : isExpired
                            ? Colors.red.shade100
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        side: BorderSide.none,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatDate(membership.startDate)} - ${_formatDate(membership.endDate)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                  if (membership.daysUntilExpiry > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${membership.daysUntilExpiry} zile rămase',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                  if (membership.gym != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.fitness_center_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          membership.gym!.name,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                  const Divider(height: 32),
                  // Price and payment info
                  Row(
                    children: [
                      Icon(
                        Icons.payments_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(membership.pricePaidCents / 100).toStringAsFixed(2)} ${membership.currency} • ${membership.paymentMethod.toUpperCase()}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  // Additional membership info
                  if (membership.isStudent) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: 16,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Abonament Student',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ],
                  if (membership.isFrozen) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.ac_unit_outlined,
                          size: 16,
                          color: Colors.cyan,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Abonament Înghețat ${membership.frozenAt != null ? "de la " + _formatDate(membership.frozenAt!) : ""}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.cyan,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showEditMembershipDialog(membership),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Editează'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => _deleteMembership(membership),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Șterge'),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCheckInsTab() {
    if (_checkIns.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Niciun check-in',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Check-in-urile vor apărea aici',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _checkIns.length > 10 ? 10 : _checkIns.length, // Show max 10
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final checkIn = _checkIns[index];

        // Determine status color and icon based on check-in status
        Color statusColor;
        IconData statusIcon;
        switch (checkIn.status?.toLowerCase()) {
          case 'success':
            statusColor = Colors.green;
            statusIcon = Icons.check_circle_outline;
            break;
          case 'expiring':
            statusColor = Colors.orange;
            statusIcon = Icons.warning_amber_outlined;
            break;
          case 'expired':
          case 'denied':
          case 'no_access':
            statusColor = Colors.red;
            statusIcon = Icons.cancel_outlined;
            break;
          case 'time_restricted':
            statusColor = Colors.orange;
            statusIcon = Icons.access_time_outlined;
            break;
          default:
            statusColor = Theme.of(context).colorScheme.onSurfaceVariant;
            statusIcon = Icons.help_outline;
        }

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withOpacity(0.5),
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: statusColor.withOpacity(0.1),
              child: Icon(statusIcon, color: statusColor),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    checkIn.gym?.name ?? 'Sală Necunoscută',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Status badge
                Chip(
                  label: Text(checkIn.status?.toUpperCase() ?? 'UNKNOWN'),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                  backgroundColor: statusColor.withOpacity(0.1),
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                // Date and time
                Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateTime(checkIn.checkedInAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                // Message from check-in
                if (checkIn.message != null && checkIn.message!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.message_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          checkIn.message!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                // Days left info
                if (checkIn.daysLeft != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${checkIn.daysLeft} zile rămase',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: checkIn.daysLeft! <= 7
                              ? Colors.orange.shade800
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: checkIn.daysLeft! <= 7
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
                // Duration if available
                if (checkIn.duration != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Durată: ${checkIn.duration}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
