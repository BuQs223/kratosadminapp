import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/supabase_service.dart';

class MembershipPlansScreen extends StatefulWidget {
  const MembershipPlansScreen({super.key});

  @override
  State<MembershipPlansScreen> createState() => _MembershipPlansScreenState();
}

class _MembershipPlansScreenState extends State<MembershipPlansScreen> {
  List<Map<String, dynamic>> _plans = [];
  bool _isLoading = true;
  String _filterStatus = 'all'; // all, active, inactive

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() => _isLoading = true);

    try {
      final supabase = SupabaseService.client;

      var queryBuilder = supabase
          .from('membership_plans')
          .select('*, gyms!membership_plans_gym_id_fkey(id, name)');

      // Apply filter
      if (_filterStatus == 'active') {
        queryBuilder = queryBuilder.eq('is_active', true);
      } else if (_filterStatus == 'inactive') {
        queryBuilder = queryBuilder.eq('is_active', false);
      }

      final response = await queryBuilder.order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _plans = (response as List).map((e) => e as Map<String, dynamic>).toList();
          _isLoading = false;
        });
      }
    } catch (error) {
      print('Error loading membership plans: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $error')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _showPlanDialog({Map<String, dynamic>? plan}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PlanFormDialog(
        plan: plan,
        onSave: () {
          _loadPlans();
        },
      ),
    );
  }

  Future<void> _togglePlanStatus(Map<String, dynamic> plan) async {
    try {
      final newStatus = !(plan['is_active'] as bool);
      
      await SupabaseService.client
          .from('membership_plans')
          .update({'is_active': newStatus})
          .eq('id', plan['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus ? 'Plan activat' : 'Plan dezactivat',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _loadPlans();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $error')),
        );
      }
    }
  }

  String _formatPrice(int cents) {
    return NumberFormat.currency(symbol: 'RON ', decimalDigits: 2)
        .format(cents / 100);
  }

  String _getPlanDuration(Map<String, dynamic> plan) {
    final months = plan['duration_months'] as int? ?? 0;
    final days = plan['duration_days'] as int? ?? 0;

    if (months > 0) {
      return '$months ${months == 1 ? 'lună' : 'luni'}';
    } else if (days > 0) {
      return '$days ${days == 1 ? 'zi' : 'zile'}';
    }
    return 'Nedefinit';
  }

  Color _getTierColor(String? tier) {
    switch (tier?.toLowerCase()) {
      case 'gold':
        return const Color(0xFFFFD700); // Gold
      case 'silver':
        return const Color(0xFFC0C0C0); // Silver
      case 'bronze':
        return const Color(0xFFCD7F32); // Bronze
      default:
        return const Color(0xFF1E88E5); // Blue
    }
  }

  String _getTierEmoji(String? tier) {
    switch (tier?.toLowerCase()) {
      case 'gold':
        return '🥇';
      case 'silver':
        return '🥈';
      case 'bronze':
        return '🥉';
      default:
        return '💳';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planuri Abonamente'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter Tabs
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: _FilterTab(
                    label: 'Toate',
                    isSelected: _filterStatus == 'all',
                    onTap: () {
                      setState(() => _filterStatus = 'all');
                      _loadPlans();
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _FilterTab(
                    label: 'Active',
                    isSelected: _filterStatus == 'active',
                    onTap: () {
                      setState(() => _filterStatus = 'active');
                      _loadPlans();
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _FilterTab(
                    label: 'Inactive',
                    isSelected: _filterStatus == 'inactive',
                    onTap: () {
                      setState(() => _filterStatus = 'inactive');
                      _loadPlans();
                    },
                  ),
                ),
              ],
            ),
          ),

          // Plans List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _plans.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.card_membership_outlined,
                              size: 80,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.3),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Niciun plan',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Adaugă primul plan de abonament',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadPlans,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _plans.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final plan = _plans[index];
                            final isActive = plan['is_active'] as bool;
                            final tier = plan['tier'] as String?;
                            final tierColor = _getTierColor(tier);
                            final tierEmoji = _getTierEmoji(tier);
                            final gym = plan['gyms'] as Map<String, dynamic>?;

                            return Card(
                              elevation: 0,
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withOpacity(0.5),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _showPlanDialog(plan: plan),
                                child: Stack(
                                  children: [
                                    // Gradient background
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              tierColor.withOpacity(0.08),
                                              tierColor.withOpacity(0.02),
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
                                          // Header Row
                                          Row(
                                            children: [
                                              // Tier Icon
                                              Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  color: tierColor
                                                      .withOpacity(0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    tierEmoji,
                                                    style: const TextStyle(
                                                        fontSize: 24),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              // Plan Name and Type
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      plan['name'] as String,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 8,
                                                            vertical: 2,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: tierColor
                                                                .withOpacity(
                                                                    0.15),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(6),
                                                          ),
                                                          child: Text(
                                                            tier?.toUpperCase() ??
                                                                'STANDARD',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: tierColor,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 8,
                                                            vertical: 2,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: isActive
                                                                ? Colors.green
                                                                    .withOpacity(
                                                                        0.15)
                                                                : Colors.red
                                                                    .withOpacity(
                                                                        0.15),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(6),
                                                          ),
                                                          child: Text(
                                                            isActive
                                                                ? 'ACTIV'
                                                                : 'INACTIV',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: isActive
                                                                  ? Colors.green
                                                                  : Colors.red,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // Toggle Button
                                              Switch(
                                                value: isActive,
                                                onChanged: (value) =>
                                                    _togglePlanStatus(plan),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          // Details
                                          Wrap(
                                            spacing: 16,
                                            runSpacing: 12,
                                            children: [
                                              // Duration
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.schedule,
                                                    size: 16,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    _getPlanDuration(plan),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                              // Price
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.payments,
                                                    size: 16,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    _formatPrice(plan[
                                                            'monthly_price_cents']
                                                        as int),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                              // Gym
                                              if (gym != null)
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.fitness_center,
                                                      size: 16,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      gym['name'] as String,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              // Special Badges
                                              if (plan['is_good_morning'] ==
                                                  true)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange
                                                        .withOpacity(0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Text('☀️',
                                                          style: TextStyle(
                                                              fontSize: 12)),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Good Morning',
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
                                              if (plan['is_family_plan'] ==
                                                  true)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.purple
                                                        .withOpacity(0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Text('👨‍👩‍👧‍👦',
                                                          style: TextStyle(
                                                              fontSize: 12)),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Familie',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.purple,
                                                        ),
                                                      ),
                                                    ],
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
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPlanDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Plan Nou'),
      ),
    );
  }
}

// Filter Tab Widget
class _FilterTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// Plan Form Dialog
class _PlanFormDialog extends StatefulWidget {
  final Map<String, dynamic>? plan;
  final VoidCallback onSave;

  const _PlanFormDialog({
    this.plan,
    required this.onSave,
  });

  @override
  State<_PlanFormDialog> createState() => _PlanFormDialogState();
}

class _PlanFormDialogState extends State<_PlanFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _durationMonthsController;
  late TextEditingController _durationDaysController;
  
  String _tier = 'silver';
  String? _selectedGymId;
  bool _isActive = true;
  bool _isFamilyPlan = false;
  bool _isGoodMorning = false;
  bool _isLoading = false;

  List<Map<String, String>> _gyms = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.plan?['name'] as String? ?? '',
    );
    _priceController = TextEditingController(
      text: widget.plan != null
          ? ((widget.plan!['monthly_price_cents'] as int) / 100).toString()
          : '',
    );
    _durationMonthsController = TextEditingController(
      text: (widget.plan?['duration_months'] as int?)?.toString() ?? '0',
    );
    _durationDaysController = TextEditingController(
      text: (widget.plan?['duration_days'] as int?)?.toString() ?? '0',
    );

    if (widget.plan != null) {
      _tier = widget.plan!['tier'] as String? ?? 'silver';
      _selectedGymId = widget.plan!['gym_id'] as String?;
      _isActive = widget.plan!['is_active'] as bool;
      _isFamilyPlan = widget.plan!['is_family_plan'] as bool? ?? false;
      _isGoodMorning = widget.plan!['is_good_morning'] as bool? ?? false;
    }

    _loadGyms();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _durationMonthsController.dispose();
    _durationDaysController.dispose();
    super.dispose();
  }

  Future<void> _loadGyms() async {
    try {
      final response = await SupabaseService.client
          .from('gyms')
          .select('id, name')
          .order('name');

      if (mounted) {
        setState(() {
          _gyms = (response as List)
              .map((gym) => {
                    'id': gym['id'] as String,
                    'name': gym['name'] as String,
                  })
              .toList();
        });
      }
    } catch (error) {
      print('Error loading gyms: $error');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final price = double.parse(_priceController.text);
      final priceCents = (price * 100).toInt();
      final durationMonths = int.parse(_durationMonthsController.text);
      final durationDays = int.parse(_durationDaysController.text);

      final data = {
        'name': _nameController.text,
        'tier': _tier,
        'gym_id': _selectedGymId,
        'monthly_price_cents': priceCents,
        'yearly_price_cents': 0,
        'student_discount_cents': 0,
        'currency': 'RON',
        'plan_kind': 'package',
        'is_active': _isActive,
        'is_family_plan': _isFamilyPlan,
        'is_good_morning': _isGoodMorning,
        'duration_months': durationMonths,
        'duration_days': durationDays,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (widget.plan == null) {
        // Create new plan
        await SupabaseService.client.from('membership_plans').insert(data);
      } else {
        // Update existing plan
        await SupabaseService.client
            .from('membership_plans')
            .update(data)
            .eq('id', widget.plan!['id']);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.plan == null
                  ? 'Plan creat cu succes'
                  : 'Plan actualizat cu succes',
            ),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSave();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare: $error')),
        );
      }
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
          margin: const EdgeInsets.only(top: 80),
          child: DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Title
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.plan == null
                                ? 'Plan Nou'
                                : 'Editează Plan',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Form
                    Expanded(
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          children: [
                            // Name
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Nume Plan',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.title),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Introduceți numele planului';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Tier
                            DropdownButtonFormField<String>(
                              value: _tier,
                              decoration: const InputDecoration(
                                labelText: 'Nivel',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.star),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'bronze', child: Text('🥉 Bronze')),
                                DropdownMenuItem(
                                    value: 'silver', child: Text('🥈 Silver')),
                                DropdownMenuItem(
                                    value: 'gold', child: Text('🥇 Gold')),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _tier = value);
                                }
                              },
                            ),
                            const SizedBox(height: 16),

                            // Price
                            TextFormField(
                              controller: _priceController,
                              decoration: const InputDecoration(
                                labelText: 'Preț (RON)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.payments),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Introduceți prețul';
                                }
                                if (double.tryParse(value) == null) {
                                  return 'Preț invalid';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Duration
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _durationMonthsController,
                                    decoration: const InputDecoration(
                                      labelText: 'Luni',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.calendar_month),
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _durationDaysController,
                                    decoration: const InputDecoration(
                                      labelText: 'Zile',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.calendar_today),
                                    ),
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Gym
                            DropdownButtonFormField<String>(
                              value: _selectedGymId,
                              decoration: const InputDecoration(
                                labelText: 'Sală (Opțional)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.fitness_center),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Toate sălile'),
                                ),
                                ..._gyms.map((gym) {
                                  return DropdownMenuItem(
                                    value: gym['id'],
                                    child: Text(gym['name']!),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                setState(() => _selectedGymId = value);
                              },
                            ),
                            const SizedBox(height: 24),

                            // Switches
                            SwitchListTile(
                              title: const Text('Plan Activ'),
                              subtitle:
                                  const Text('Vizibil pentru membri noi'),
                              value: _isActive,
                              onChanged: (value) {
                                setState(() => _isActive = value);
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Plan Familie'),
                              subtitle: const Text(
                                  'Permite multiple persoane pe același abonament'),
                              value: _isFamilyPlan,
                              onChanged: (value) {
                                setState(() => _isFamilyPlan = value);
                              },
                            ),
                            SwitchListTile(
                              title: const Text('Good Morning'),
                              subtitle: const Text(
                                  'Acces dimineața (6:00 - 12:00)'),
                              value: _isGoodMorning,
                              onChanged: (value) {
                                setState(() => _isGoodMorning = value);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Save Button
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _save,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    widget.plan == null
                                        ? 'Creează Plan'
                                        : 'Salvează Modificări',
                                  ),
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
