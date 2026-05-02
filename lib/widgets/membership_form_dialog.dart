import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/membership.dart';
import '../models/membership_plan.dart';
import '../models/gym.dart';
import '../services/supabase_service.dart';

class MembershipFormDialog extends StatefulWidget {
  final String memberId;
  final Membership? membership;

  const MembershipFormDialog({
    super.key,
    required this.memberId,
    this.membership,
  });

  @override
  State<MembershipFormDialog> createState() => _MembershipFormDialogState();
}

class _MembershipFormDialogState extends State<MembershipFormDialog> {
  final _formKey = GlobalKey<FormState>();
  List<MembershipPlan> _plans = [];
  List<Gym> _gyms = [];
  bool _isLoadingData = true;
  bool _isSaving = false;

  String? _selectedPlanId;
  String? _selectedGymId;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));
  bool _isActive = true;
  String _membershipType = 'monthly';
  int _pricePaidCents = 0;
  String _paymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoadingData = true);

    try {
      final supabase = SupabaseService.client;

      final results = await Future.wait([
        supabase.from('membership_plans').select().order('name'),
        supabase.from('gyms').select().order('name'),
      ]);

      if (mounted) setState(() {
        _plans = (results[0] as List)
            .map((json) => MembershipPlan.fromJson(json))
            .toList();
        _gyms = (results[1] as List).map((json) => Gym.fromJson(json)).toList();

        // Set initial values AFTER data is loaded
        if (widget.membership != null) {
          // Only set the values if they exist in the loaded lists
          final planExists = _plans.any(
            (p) => p.id == widget.membership!.planId,
          );
          final gymExists = _gyms.any(
            (g) => g.id == widget.membership!.soldAtGymId,
          );

          _selectedPlanId = planExists ? widget.membership!.planId : null;
          _selectedGymId = gymExists ? widget.membership!.soldAtGymId : null;
          _startDate = widget.membership!.startDate;
          _endDate = widget.membership!.endDate;
          _isActive = widget.membership!.isActive;
          _membershipType = widget.membership!.membershipType;
          _pricePaidCents = widget.membership!.pricePaidCents;
          _paymentMethod = widget.membership!.paymentMethod;
        }

        if (mounted) setState(() => _isLoadingData = false);
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare: $error')));
      }
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPlanId == null || _selectedGymId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selectează planul și sala')),
      );
      return;
    }

    if (mounted) setState(() => _isSaving = true);

    try {
      final supabase = SupabaseService.client;

      final data = {
        'user_id': widget.memberId,
        'plan_id': _selectedPlanId,
        'sold_at_gym_id': _selectedGymId,
        'start_date': _startDate.toIso8601String(),
        'end_date': _endDate.toIso8601String(),
        'is_active': _isActive,
        'membership_type': _membershipType,
        'price_paid_cents': _pricePaidCents,
        'payment_method': _paymentMethod,
      };

      String? membershipId;

      if (widget.membership == null) {
        // Create new membership
        final response = await supabase
            .from('memberships')
            .insert(data)
            .select('id')
            .single();

        membershipId = response['id'] as String;

        // Create revenue ledger entry for new membership
        await supabase.from('revenue_ledger').insert({
          'membership_id': membershipId,
          'plan_id': _selectedPlanId,
          'gym_id': _selectedGymId,
          'amount_cents': _pricePaidCents,
          'currency': 'RON',
          'source': 'membership',
          'entry_kind': 'charge',
          'payment_method': _paymentMethod,
          'recorded_by': SupabaseService.currentUser?.id,
        });
      } else {
        // Update existing membership
        await supabase
            .from('memberships')
            .update(data)
            .eq('id', widget.membership!.id);

        membershipId = widget.membership!.id;

        // Update revenue ledger entry if price changed
        if (_pricePaidCents != widget.membership!.pricePaidCents) {
          // Check if there's an existing revenue entry
          final existingRevenue = await supabase
              .from('revenue_ledger')
              .select('id')
              .eq('membership_id', membershipId)
              .maybeSingle();

          if (existingRevenue != null) {
            // Update existing entry
            await supabase
                .from('revenue_ledger')
                .update({
                  'amount_cents': _pricePaidCents,
                  'payment_method': _paymentMethod,
                  'gym_id': _selectedGymId,
                })
                .eq('id', existingRevenue['id']);
          } else {
            // Create new entry if none exists
            await supabase.from('revenue_ledger').insert({
              'membership_id': membershipId,
              'plan_id': _selectedPlanId,
              'gym_id': _selectedGymId,
              'amount_cents': _pricePaidCents,
              'currency': 'RON',
              'source': 'membership',
              'entry_kind': 'charge',
              'payment_method': _paymentMethod,
              'recorded_by': SupabaseService.currentUser?.id,
            });
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Eroare: $error')));
      }
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      if (mounted) setState(() {
        if (isStartDate) {
          _startDate = picked;
          // Auto-adjust end date if needed
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 30));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          // Header with gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  primaryColor.withOpacity(0.08),
                  primaryColor.withOpacity(0.03),
                ],
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.card_membership,
                    color: primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.membership == null
                        ? 'Abonament Nou'
                        : 'Editează Abonament',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoadingData
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: primaryColor),
                        const SizedBox(height: 16),
                        Text(
                          'Se încarcă...',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Plan Selector Card
                          _buildGradientCard(
                            context,
                            color: const Color(0xFF1E88E5),
                            icon: Icons.card_membership,
                            child: DropdownButtonFormField<String>(
                              value: _selectedPlanId,
                              decoration: InputDecoration(
                                labelText: 'Plan Abonament',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                labelStyle: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              items: _plans.map((plan) {
                                return DropdownMenuItem(
                                  value: plan.id,
                                  child: Text(plan.name),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (mounted) setState(() => _selectedPlanId = value);
                              },
                              validator: (value) =>
                                  value == null ? 'Selectează un plan' : null,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Gym Selector Card
                          _buildGradientCard(
                            context,
                            color: const Color(0xFF43A047),
                            icon: Icons.fitness_center,
                            child: DropdownButtonFormField<String>(
                              value: _selectedGymId,
                              decoration: InputDecoration(
                                labelText: 'Sală',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                                labelStyle: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              items: _gyms.map((gym) {
                                return DropdownMenuItem(
                                  value: gym.id,
                                  child: Text(gym.name),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (mounted) setState(() => _selectedGymId = value);
                              },
                              validator: (value) =>
                                  value == null ? 'Selectează o sală' : null,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Price and Payment Method Row
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: _buildGradientCard(
                                  context,
                                  color: const Color(0xFFFB8C00),
                                  icon: Icons.payments,
                                  child: TextFormField(
                                    initialValue: (_pricePaidCents / 100)
                                        .toStringAsFixed(2),
                                    decoration: InputDecoration(
                                      labelText: 'Preț (RON)',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      errorBorder: InputBorder.none,
                                      focusedErrorBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                      labelStyle: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged: (value) {
                                      final price = double.tryParse(value) ?? 0;
                                      if (mounted) setState(() {
                                        _pricePaidCents = (price * 100).round();
                                      });
                                    },
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                        ? 'Introduceți prețul'
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: _buildGradientCard(
                                  context,
                                  color: const Color(0xFF8E24AA),
                                  icon: Icons.credit_card,
                                  child: DropdownButtonFormField<String>(
                                    value: _paymentMethod,
                                    decoration: InputDecoration(
                                      labelText: 'Plată',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      errorBorder: InputBorder.none,
                                      focusedErrorBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                      labelStyle: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'cash',
                                        child: Text('Cash'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'card',
                                        child: Text('Card'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        if (mounted) setState(() => _paymentMethod = value);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Date Pickers Row
                          Row(
                            children: [
                              Expanded(
                                child: _buildDateCard(
                                  context,
                                  label: 'Data Start',
                                  date: _startDate,
                                  icon: Icons.calendar_today,
                                  color: const Color(0xFF00ACC1),
                                  onTap: () => _selectDate(context, true),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildDateCard(
                                  context,
                                  label: 'Data Sfârșit',
                                  date: _endDate,
                                  icon: Icons.event,
                                  color: const Color(0xFFE53935),
                                  onTap: () => _selectDate(context, false),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Active Toggle Card
                          _buildGradientCard(
                            context,
                            color: _isActive
                                ? const Color(0xFF43A047)
                                : const Color(0xFF757575),
                            icon: _isActive ? Icons.check_circle : Icons.cancel,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Abonament Activ',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Switch(
                                  value: _isActive,
                                  onChanged: (value) {
                                    if (mounted) setState(() => _isActive = value);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Actions
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isSaving
                                      ? null
                                      : () => Navigator.pop(context),
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
                                flex: 2,
                                child: FilledButton(
                                  onPressed: _isSaving ? null : _save,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  child: _isSaving
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          widget.membership == null
                                              ? 'Creează Abonament'
                                              : 'Salvează Modificări',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientCard(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
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
                  colors: [color.withOpacity(0.05), color.withOpacity(0.02)],
                ),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
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
                const SizedBox(width: 12),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateCard(
    BuildContext context, {
    required String label,
    required DateTime date,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
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
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: 16),
                      ),
                      const Spacer(),
                      Icon(Icons.arrow_drop_down, color: color),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(date),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
}
