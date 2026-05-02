import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/product_admin_analytics.dart';
import '../../services/product_admin_analytics_service.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductFilterOption {
  final String id;
  final String name;
  final String gymName;

  const _ProductFilterOption({
    required this.id,
    required this.name,
    required this.gymName,
  });
}

class _ProductsScreenState extends State<ProductsScreen>
    with SingleTickerProviderStateMixin {
  final ProductAdminAnalyticsService _service = ProductAdminAnalyticsService();
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;

  bool _isLoading = true;
  bool _isLoadingMoreMovements = false;
  bool _hasMoreMovements = true;

  String? _selectedGymId;
  String? _selectedEmployeeId;
  String? _selectedMovementProductId;
  String _selectedReason = 'all';
  String _timeRange = 'month';
  DateTime? _customDateStart;
  DateTime? _customDateEnd;
  bool _includeInactive = true;
  bool _lowStockOnly = false;
  int _lowStockThreshold = 5;
  String _stockSortMode = 'name'; // name, highest, lowest

  List<Map<String, String>> _gyms = [];
  List<Map<String, String>> _employees = [];
  List<_ProductFilterOption> _movementProductOptions = [];

  ProductDashboardKpis _kpis = ProductDashboardKpis.empty();
  List<ProductOverviewItem> _products = [];
  List<TopSellingProduct> _topProducts = [];
  List<EmployeeProductSales> _employeeSales = [];
  Map<String, List<EmployeeProductSaleTransaction>>
  _employeeTransactionsByEmployee = {};
  List<ProductStockMovement> _movements = [];

  int _movementsTotalCount = 0;

  static const int _movementsPageSize = 50;

  List<ProductOverviewItem> get _sortedProducts {
    final sorted = List<ProductOverviewItem>.from(_products);
    switch (_stockSortMode) {
      case 'highest':
        sorted.sort((a, b) {
          final stockCmp = b.stock.compareTo(a.stock);
          if (stockCmp != 0) return stockCmp;
          return a.productName.toLowerCase().compareTo(
            b.productName.toLowerCase(),
          );
        });
        break;
      case 'lowest':
        sorted.sort((a, b) {
          final stockCmp = a.stock.compareTo(b.stock);
          if (stockCmp != 0) return stockCmp;
          return a.productName.toLowerCase().compareTo(
            b.productName.toLowerCase(),
          );
        });
        break;
      case 'name':
      default:
        sorted.sort(
          (a, b) => a.productName.toLowerCase().compareTo(
            b.productName.toLowerCase(),
          ),
        );
        break;
    }
    return sorted;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final gyms = await _service.fetchGyms();
      final employees = await _service.fetchEmployees(gymId: _selectedGymId);
      final movementProducts = await _fetchMovementProductOptions(
        gymId: _selectedGymId,
      );

      if (!mounted) return;
      setState(() {
        _gyms = gyms;
        _employees = employees;
        _movementProductOptions = movementProducts;
      });

      await _loadAnalytics(showLoader: false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la încărcarea datelor: $error')),
      );
    }
  }

  DateTime? _getDateStart() {
    final now = DateTime.now();
    switch (_timeRange) {
      case 'month':
        return DateTime(now.year, now.month, 1);
      case '7days':
        return now.subtract(const Duration(days: 7));
      case '30days':
        return now.subtract(const Duration(days: 30));
      case '90days':
        return now.subtract(const Duration(days: 90));
      case 'year':
        return DateTime(now.year, 1, 1);
      case 'custom':
        if (_customDateStart == null) return null;
        return DateTime(
          _customDateStart!.year,
          _customDateStart!.month,
          _customDateStart!.day,
        );
      case 'all':
      default:
        return null;
    }
  }

  DateTime? _getDateEnd() {
    if (_timeRange == 'custom') {
      if (_customDateEnd == null) return null;
      return DateTime(
        _customDateEnd!.year,
        _customDateEnd!.month,
        _customDateEnd!.day,
        23,
        59,
        59,
        999,
      );
    }
    return DateTime.now();
  }

  Future<void> _loadEmployees({String? gymIdOverride}) async {
    try {
      final employees = await _service.fetchEmployees(
        gymId: gymIdOverride ?? _selectedGymId,
      );

      if (!mounted) return;
      setState(() {
        _employees = employees;
        if (_selectedEmployeeId != null &&
            !_employees.any((e) => e['id'] == _selectedEmployeeId)) {
          _selectedEmployeeId = null;
        }
      });
    } catch (_) {}
  }

  Future<List<_ProductFilterOption>> _fetchMovementProductOptions({
    String? gymId,
  }) async {
    final products = await _service.fetchProductsOverview(
      gymId: gymId,
      includeInactive: true,
      limit: 500,
    );

    final byId = <String, _ProductFilterOption>{};
    for (final product in products) {
      byId.putIfAbsent(
        product.productId,
        () => _ProductFilterOption(
          id: product.productId,
          name: product.productName,
          gymName: product.gymName,
        ),
      );
    }

    final list = byId.values.toList()
      ..sort((a, b) {
        final nameCmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        if (nameCmp != 0) return nameCmp;
        return a.gymName.toLowerCase().compareTo(b.gymName.toLowerCase());
      });
    return list;
  }

  Future<String?> _showMovementProductPicker({
    required List<_ProductFilterOption> options,
    required String? selectedProductId,
  }) async {
    String query = '';
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = options.where((option) {
            if (query.trim().isEmpty) return true;
            final q = query.toLowerCase();
            return option.name.toLowerCase().contains(q) ||
                option.gymName.toLowerCase().contains(q);
          }).toList();
          final maxHeight = MediaQuery.of(context).size.height * 0.78;

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'Alege produs',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop('__all__'),
                          child: const Text('Toate'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Caută produs sau sală...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                'Niciun produs găsit',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final option = filtered[index];
                                final selected = selectedProductId == option.id;
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(option.name),
                                  subtitle: Text(option.gymName),
                                  trailing: selected
                                      ? Icon(
                                          Icons.check_circle,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        )
                                      : null,
                                  onTap: () =>
                                      Navigator.of(context).pop(option.id),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadAnalytics({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final dateStart = _getDateStart();
      final dateEnd = _getDateEnd();
      final search = _searchController.text.trim();

      final results = await Future.wait<dynamic>([
        _service.fetchDashboardKpis(
          gymId: _selectedGymId,
          dateStart: dateStart,
          dateEnd: dateEnd,
          lowStockThreshold: _lowStockThreshold,
        ),
        _service.fetchProductsOverview(
          gymId: _selectedGymId,
          searchQuery: search.isEmpty ? null : search,
          includeInactive: _includeInactive,
          lowStockThreshold: _lowStockOnly ? _lowStockThreshold : null,
          limit: 200,
        ),
        _service.fetchTopSellingProducts(
          gymId: _selectedGymId,
          dateStart: dateStart,
          dateEnd: dateEnd,
          limit: 12,
        ),
        _service.fetchEmployeeProductSales(
          gymId: _selectedGymId,
          employeeId: _selectedEmployeeId,
          dateStart: dateStart,
          dateEnd: dateEnd,
          limit: 50,
        ),
        _service.fetchEmployeeSaleTransactions(
          gymId: _selectedGymId,
          employeeId: _selectedEmployeeId,
          dateStart: dateStart,
          dateEnd: dateEnd,
          limit: 250,
        ),
        _service.fetchStockMovements(
          gymId: _selectedGymId,
          productId: _selectedMovementProductId,
          employeeId: _selectedEmployeeId,
          reason: _selectedReason == 'all' ? null : _selectedReason,
          dateStart: dateStart,
          dateEnd: dateEnd,
          searchQuery: search.isEmpty ? null : search,
          limit: _movementsPageSize,
          offset: 0,
        ),
      ]);

      final products = results[1] as List<ProductOverviewItem>;
      final employeeTransactions =
          results[4] as List<EmployeeProductSaleTransaction>;
      final movements = results[5] as List<ProductStockMovement>;
      final groupedEmployeeTransactions = _groupTransactionsByEmployee(
        employeeTransactions,
      );

      if (!mounted) return;
      setState(() {
        _kpis = results[0] as ProductDashboardKpis;
        _products = products;
        _topProducts = results[2] as List<TopSellingProduct>;
        _employeeSales = results[3] as List<EmployeeProductSales>;
        _movements = movements;
        _employeeTransactionsByEmployee = groupedEmployeeTransactions;
        _movementsTotalCount = movements.isNotEmpty
            ? movements.first.totalCount
            : 0;
        _hasMoreMovements = _movements.length < _movementsTotalCount;
        _isLoadingMoreMovements = false;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la încărcarea analizelor: $error')),
      );
    }
  }

  Future<void> _loadMoreMovements() async {
    if (_isLoading ||
        _isLoadingMoreMovements ||
        !_hasMoreMovements ||
        _movements.isEmpty) {
      return;
    }

    if (mounted) setState(() => _isLoadingMoreMovements = true);

    try {
      final dateStart = _getDateStart();
      final dateEnd = _getDateEnd();
      final search = _searchController.text.trim();

      final nextPage = await _service.fetchStockMovements(
        gymId: _selectedGymId,
        productId: _selectedMovementProductId,
        employeeId: _selectedEmployeeId,
        reason: _selectedReason == 'all' ? null : _selectedReason,
        dateStart: dateStart,
        dateEnd: dateEnd,
        searchQuery: search.isEmpty ? null : search,
        limit: _movementsPageSize,
        offset: _movements.length,
      );

      if (!mounted) return;

      final existingIds = _movements.map((m) => m.movementId).toSet();
      final uniqueNextPage = nextPage
          .where((m) => !existingIds.contains(m.movementId))
          .toList();
      final updatedMovements = [..._movements, ...uniqueNextPage];
      final totalCount = nextPage.isNotEmpty
          ? nextPage.first.totalCount
          : _movementsTotalCount;

      setState(() {
        _movements = updatedMovements;
        _movementsTotalCount = totalCount;
        _hasMoreMovements = _movements.length < _movementsTotalCount;
        _isLoadingMoreMovements = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingMoreMovements = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la încărcarea mișcărilor: $error')),
      );
    }
  }

  String _reasonLabel(String reason) {
    switch (reason) {
      case 'sale':
        return 'Vânzare';
      case 'restock':
        return 'Alimentare';
      case 'new_product':
        return 'Produs Nou';
      case 'status_change':
        return 'Status';
      case 'adjustment':
        return 'Ajustare';
      case 'verification':
        return 'Verificare';
      default:
        return reason;
    }
  }

  Color _reasonColor(BuildContext context, String reason) {
    final scheme = Theme.of(context).colorScheme;
    switch (reason) {
      case 'sale':
        return Colors.red;
      case 'restock':
        return Colors.teal;
      case 'new_product':
        return Colors.green;
      case 'status_change':
        return Colors.deepPurple;
      case 'adjustment':
        return Colors.orange;
      case 'verification':
        return Colors.blue;
      default:
        return scheme.primary;
    }
  }

  String _currencySymbol(String currency) {
    return currency == 'EUR' ? '€' : 'RON';
  }

  String _formatMoney(int cents, {String currency = 'RON'}) {
    final amount = cents / 100.0;
    return '${NumberFormat('#,##0.00').format(amount)} ${_currencySymbol(currency)}';
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('dd MMM yyyy, HH:mm').format(dt);
  }

  Map<String, List<EmployeeProductSaleTransaction>>
  _groupTransactionsByEmployee(
    List<EmployeeProductSaleTransaction> transactions,
  ) {
    final grouped = <String, List<EmployeeProductSaleTransaction>>{};
    for (final tx in transactions) {
      grouped.putIfAbsent(tx.employeeId, () => []);
      grouped[tx.employeeId]!.add(tx);
    }
    return grouped;
  }

  int get _activeFiltersCount {
    int count = 0;
    if (_selectedGymId != null) count++;
    if (_selectedEmployeeId != null) count++;
    if (_selectedReason != 'all') count++;
    if (_timeRange != 'month') count++;
    if (_lowStockOnly) count++;
    if (!_includeInactive) count++;
    return count;
  }

  Future<void> _pickDate({
    required BuildContext context,
    required DateTime? initialDate,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDate: initialDate ?? now,
    );
    if (picked != null) onPicked(picked);
  }

  void _showFilterSheet() {
    String? tempGymId = _selectedGymId;
    String? tempEmployeeId = _selectedEmployeeId;
    String tempReason = _selectedReason;
    String tempTimeRange = _timeRange;
    DateTime? tempDateStart = _customDateStart;
    DateTime? tempDateEnd = _customDateEnd;
    bool tempIncludeInactive = _includeInactive;
    bool tempLowStockOnly = _lowStockOnly;
    int tempLowStockThreshold = _lowStockThreshold;
    List<Map<String, String>> tempEmployees = List.from(_employees);
    bool tempLoadingEmployees = false;

    Future<void> reloadEmployees(
      StateSetter setModalState,
      String? gymId,
    ) async {
      setModalState(() => tempLoadingEmployees = true);
      try {
        final employees = await _service.fetchEmployees(gymId: gymId);
        setModalState(() {
          tempEmployees = employees;
          if (tempEmployeeId != null &&
              !tempEmployees.any((e) => e['id'] == tempEmployeeId)) {
            tempEmployeeId = null;
          }
          tempLoadingEmployees = false;
        });
      } catch (_) {
        setModalState(() => tempLoadingEmployees = false);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final colorScheme = Theme.of(context).colorScheme;
          final dropdownMenuColor = colorScheme.surfaceContainerHighest;
          final dropdownBorder = OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          );

          InputDecoration dropdownDecoration({
            required String labelText,
            Widget? suffixIcon,
          }) {
            return InputDecoration(
              labelText: labelText,
              suffixIcon: suffixIcon,
              filled: true,
              fillColor: colorScheme.surfaceContainerLow,
              border: dropdownBorder,
              enabledBorder: dropdownBorder,
              focusedBorder: dropdownBorder.copyWith(
                borderSide: BorderSide(
                  color: colorScheme.primary.withValues(alpha: 0.9),
                  width: 1.4,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            );
          }

          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Filtre Produse',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              tempGymId = null;
                              tempEmployeeId = null;
                              tempReason = 'all';
                              tempTimeRange = 'month';
                              tempDateStart = null;
                              tempDateEnd = null;
                              tempIncludeInactive = true;
                              tempLowStockOnly = false;
                              tempLowStockThreshold = 5;
                            });
                          },
                          child: const Text('Resetează'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      initialValue: tempGymId,
                      decoration: dropdownDecoration(labelText: 'Sală'),
                      dropdownColor: dropdownMenuColor,
                      borderRadius: BorderRadius.circular(14),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Toate sălile'),
                        ),
                        ..._gyms.map(
                          (gym) => DropdownMenuItem<String?>(
                            value: gym['id'],
                            child: Text(gym['name'] ?? ''),
                          ),
                        ),
                      ],
                      onChanged: (value) async {
                        setModalState(() {
                          tempGymId = value;
                          tempEmployeeId = null;
                        });
                        await reloadEmployees(setModalState, value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: tempEmployeeId,
                      decoration: dropdownDecoration(
                        labelText: 'Angajat',
                        suffixIcon: tempLoadingEmployees
                            ? const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      dropdownColor: dropdownMenuColor,
                      borderRadius: BorderRadius.circular(14),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Toți angajații'),
                        ),
                        ...tempEmployees.map(
                          (employee) => DropdownMenuItem<String?>(
                            value: employee['id'],
                            child: Text(employee['name'] ?? ''),
                          ),
                        ),
                      ],
                      onChanged: tempLoadingEmployees
                          ? null
                          : (value) =>
                                setModalState(() => tempEmployeeId = value),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: tempReason,
                      decoration: dropdownDecoration(
                        labelText: 'Tip operațiune stoc',
                      ),
                      dropdownColor: dropdownMenuColor,
                      borderRadius: BorderRadius.circular(14),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Toate')),
                        DropdownMenuItem(value: 'sale', child: Text('Vânzare')),
                        DropdownMenuItem(
                          value: 'restock',
                          child: Text('Alimentare'),
                        ),
                        DropdownMenuItem(
                          value: 'new_product',
                          child: Text('Produs nou'),
                        ),
                        DropdownMenuItem(
                          value: 'status_change',
                          child: Text('Status produs'),
                        ),
                        DropdownMenuItem(
                          value: 'adjustment',
                          child: Text('Ajustare'),
                        ),
                        DropdownMenuItem(
                          value: 'verification',
                          child: Text('Verificare'),
                        ),
                      ],
                      onChanged: (value) =>
                          setModalState(() => tempReason = value ?? 'all'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: tempTimeRange,
                      decoration: dropdownDecoration(labelText: 'Perioadă'),
                      dropdownColor: dropdownMenuColor,
                      borderRadius: BorderRadius.circular(14),
                      items: const [
                        DropdownMenuItem(
                          value: 'month',
                          child: Text('Luna curentă'),
                        ),
                        DropdownMenuItem(
                          value: '7days',
                          child: Text('Ultimele 7 zile'),
                        ),
                        DropdownMenuItem(
                          value: '30days',
                          child: Text('Ultimele 30 zile'),
                        ),
                        DropdownMenuItem(
                          value: '90days',
                          child: Text('Ultimele 90 zile'),
                        ),
                        DropdownMenuItem(
                          value: 'year',
                          child: Text('Anul curent'),
                        ),
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('Toată perioada'),
                        ),
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text('Perioadă custom'),
                        ),
                      ],
                      onChanged: (value) =>
                          setModalState(() => tempTimeRange = value ?? 'month'),
                    ),
                    if (tempTimeRange == 'custom') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.date_range),
                              label: Text(
                                tempDateStart == null
                                    ? 'Data start'
                                    : DateFormat(
                                        'dd.MM.yyyy',
                                      ).format(tempDateStart!),
                              ),
                              onPressed: () => _pickDate(
                                context: context,
                                initialDate: tempDateStart,
                                onPicked: (date) =>
                                    setModalState(() => tempDateStart = date),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.date_range),
                              label: Text(
                                tempDateEnd == null
                                    ? 'Data sfârșit'
                                    : DateFormat(
                                        'dd.MM.yyyy',
                                      ).format(tempDateEnd!),
                              ),
                              onPressed: () => _pickDate(
                                context: context,
                                initialDate: tempDateEnd ?? tempDateStart,
                                onPicked: (date) =>
                                    setModalState(() => tempDateEnd = date),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: tempIncludeInactive,
                      title: const Text('Include produse inactive'),
                      onChanged: (value) =>
                          setModalState(() => tempIncludeInactive = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: tempLowStockOnly,
                      title: const Text('Doar produse cu stoc mic'),
                      subtitle: Text('Prag: <= $tempLowStockThreshold bucăți'),
                      onChanged: (value) =>
                          setModalState(() => tempLowStockOnly = value),
                    ),
                    Row(
                      children: [
                        const Text('Prag stoc mic'),
                        Expanded(
                          child: Slider(
                            min: 1,
                            max: 20,
                            divisions: 19,
                            value: tempLowStockThreshold.toDouble(),
                            label: tempLowStockThreshold.toString(),
                            onChanged: (value) => setModalState(
                              () => tempLowStockThreshold = value.round(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('Aplică filtre'),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          if (!mounted) return;
                          final movementProducts =
                              await _fetchMovementProductOptions(
                                gymId: tempGymId,
                              );

                          if (!mounted) return;
                          setState(() {
                            _selectedGymId = tempGymId;
                            _selectedEmployeeId = tempEmployeeId;
                            _selectedReason = tempReason;
                            _timeRange = tempTimeRange;
                            _customDateStart = tempDateStart;
                            _customDateEnd = tempDateEnd;
                            _includeInactive = tempIncludeInactive;
                            _lowStockOnly = tempLowStockOnly;
                            _lowStockThreshold = tempLowStockThreshold;
                            _employees = tempEmployees;
                            _movementProductOptions = movementProducts;
                            if (_selectedMovementProductId != null &&
                                !_movementProductOptions.any(
                                  (p) => p.id == _selectedMovementProductId,
                                )) {
                              _selectedMovementProductId = null;
                            }
                          });
                          await _loadEmployees(gymIdOverride: _selectedGymId);
                          await _loadAnalytics();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverviewSquareStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.05),
                    color.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const Spacer(),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
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
                    color: color.withValues(alpha: 0.15),
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
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewHorizontalStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                    color.withValues(alpha: 0.05),
                    color.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
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
    );
  }

  Widget _buildEmptyCard(String text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContextChip({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (color ?? Theme.of(context).colorScheme.primary).withValues(
          alpha: 0.1,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color ?? Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color ?? Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {String? trailing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: () => _loadAnalytics(showLoader: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        children: [
          _buildSectionTitle('Sumar Operațional'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.08,
            children: [
              _buildOverviewSquareStatCard(
                title: 'Produse totale',
                value: _kpis.totalProducts.toString(),
                icon: Icons.inventory_2_outlined,
                color: const Color(0xFF1E88E5),
              ),
              _buildOverviewSquareStatCard(
                title: 'Produse active',
                value: _kpis.activeProducts.toString(),
                icon: Icons.check_circle_outline,
                color: const Color(0xFF43A047),
              ),
              _buildOverviewSquareStatCard(
                title: 'Bucăți în stoc',
                value: _kpis.totalStockUnits.toString(),
                icon: Icons.warehouse_outlined,
                color: const Color(0xFF8E24AA),
              ),
              _buildOverviewSquareStatCard(
                title: 'Vânzări produse',
                value: _kpis.salesCount.toString(),
                icon: Icons.point_of_sale_outlined,
                color: const Color(0xFF00897B),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildOverviewHorizontalStatCard(
            title: 'Venit produse',
            value: _formatMoney(_kpis.salesRevenueCents),
            icon: Icons.attach_money_outlined,
            color: const Color(0xFFFB8C00),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.08,
            children: [
              _buildOverviewSquareStatCard(
                title: 'Venit Cash',
                value: _formatMoney(_kpis.cashRevenueCents),
                icon: Icons.payments_outlined,
                color: const Color(0xFF43A047),
              ),
              _buildOverviewSquareStatCard(
                title: 'Venit Card',
                value: _formatMoney(_kpis.cardRevenueCents),
                icon: Icons.credit_card,
                color: const Color(0xFF1E88E5),
              ),
            ],
          ),

          const SizedBox(height: 8),
          _buildOverviewHorizontalStatCard(
            title: 'Valoare stoc',
            value: _formatMoney(_kpis.stockValueCents),
            icon: Icons.payments_outlined,
            color: const Color(0xFF3949AB),
          ),
          const SizedBox(height: 20),
          _buildSectionTitle(
            'Top Produse Vândute',
            trailing: '${_topProducts.length} rezultate',
          ),
          const SizedBox(height: 8),
          if (_topProducts.isEmpty)
            _buildEmptyCard('Nu există vânzări în perioada selectată.')
          else
            ..._topProducts.asMap().entries.map(
              (entry) => _buildTopProductCard(
                rank: entry.key + 1,
                product: entry.value,
              ),
            ),
        ],
      ),
    );
  }

  Color _topRankColor(int rank) {
    if (rank == 1) return const Color(0xFFFFB300);
    if (rank == 2) return const Color(0xFF90A4AE);
    if (rank == 3) return const Color(0xFFFF8A65);
    return const Color(0xFF5C6BC0);
  }

  Widget _buildTopProductCard({
    required int rank,
    required TopSellingProduct product,
  }) {
    final rankColor = _topRankColor(rank);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: rankColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: rankColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    product.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatMoney(product.totalRevenueCents),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildEmployeeDetailChip(
                  icon: Icons.fitness_center,
                  label: product.gymName,
                  color: const Color(0xFF5C6BC0),
                ),
                _buildEmployeeDetailChip(
                  icon: Icons.inventory_2_outlined,
                  label: '${product.quantitySold} buc.',
                  color: const Color(0xFF1E88E5),
                ),
                _buildEmployeeDetailChip(
                  icon: Icons.receipt_long_outlined,
                  label: '${product.salesCount} bonuri',
                  color: const Color(0xFF8E24AA),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildEmployeeDetailChip(
                  icon: Icons.payments_outlined,
                  label: 'Cash ${_formatMoney(product.cashRevenueCents)}',
                  color: const Color(0xFF43A047),
                ),
                _buildEmployeeDetailChip(
                  icon: Icons.credit_card,
                  label: 'Card ${_formatMoney(product.cardRevenueCents)}',
                  color: const Color(0xFF1E88E5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeesTab() {
    return RefreshIndicator(
      onRefresh: () => _loadAnalytics(showLoader: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        children: [
          _buildSectionTitle(
            _selectedEmployeeId == null
                ? 'Performanță Angajați'
                : 'Performanță Angajat',
          ),
          const SizedBox(height: 10),
          if (_employeeSales.isEmpty)
            _buildEmptyCard(
              'Nu există vânzări pe angajați pentru filtrele curente.',
            )
          else
            ..._employeeSales.map((row) {
              final transactions =
                  _employeeTransactionsByEmployee[row.employeeId] ??
                  const <EmployeeProductSaleTransaction>[];

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _EmployeeSalesDetailScreen(
                          row: row,
                          gymId: _selectedGymId ?? row.gymId,
                          initialTransactions: transactions,
                          initialTimeRange: _timeRange,
                          initialCustomDateStart: _customDateStart,
                          initialCustomDateEnd: _customDateEnd,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.person_outline,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row.employeeName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.fitness_center,
                                        size: 13,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          row.gymName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '+ ${_formatMoney(row.revenueCents)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 14,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildEmployeeMetricBox(
                                icon: Icons.inventory_2_outlined,
                                label: 'Bucăți',
                                value: row.itemsSold.toString(),
                                color: const Color(0xFF1E88E5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildEmployeeMetricBox(
                                icon: Icons.receipt_long_outlined,
                                label: 'Vânzări',
                                value: row.salesCount.toString(),
                                color: const Color(0xFF8E24AA),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildEmployeeDetailChip(
                              icon: Icons.payments_outlined,
                              label:
                                  'Cash ${_formatMoney(row.cashRevenueCents)}',
                              color: const Color(0xFF43A047),
                            ),
                            if (row.cardRevenueCents > 0)
                              _buildEmployeeDetailChip(
                                icon: Icons.credit_card,
                                label:
                                    'Card ${_formatMoney(row.cardRevenueCents)}',
                                color: const Color(0xFF1E88E5),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildEmployeeMetricBox({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.05),
                    color.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
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
    );
  }

  Widget _buildEmployeeDetailChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsTab() {
    return RefreshIndicator(
      onRefresh: () => _loadAnalytics(showLoader: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        children: [
          _buildSectionTitle(
            'Stoc Produse',
            trailing: '${_kpis.activeProducts} / ${_kpis.totalProducts}',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Alfabetic'),
                selected: _stockSortMode == 'name',
                onSelected: (_) => setState(() => _stockSortMode = 'name'),
              ),
              ChoiceChip(
                label: const Text('Stoc mare'),
                selected: _stockSortMode == 'highest',
                onSelected: (_) => setState(() => _stockSortMode = 'highest'),
              ),
              ChoiceChip(
                label: const Text('Stoc mic'),
                selected: _stockSortMode == 'lowest',
                onSelected: (_) => setState(() => _stockSortMode = 'lowest'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_products.isEmpty)
            _buildEmptyCard('Nu există produse pentru filtrele selectate.')
          else
            ..._sortedProducts.map((product) {
              final isLowStock = product.stock <= _lowStockThreshold;
              final stockColor = product.stock <= 0
                  ? Colors.red
                  : isLowStock
                  ? Colors.orange
                  : Colors.green;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  title: Text(
                    product.productName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildContextChip(
                          icon: Icons.storefront_outlined,
                          label: product.gymName,
                        ),
                        _buildContextChip(
                          icon: Icons.sell_outlined,
                          label: _formatMoney(
                            product.priceCents,
                            currency: product.currency,
                          ),
                        ),
                        if (!product.isActive)
                          _buildContextChip(
                            icon: Icons.pause_circle_outline,
                            label: 'Inactiv',
                            color: Colors.grey.shade700,
                          ),
                      ],
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: stockColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${product.stock} buc.',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _formatMoney(
                          product.stockValueCents,
                          currency: product.currency,
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildMovementsTab() {
    _ProductFilterOption? selectedMovementProduct;
    if (_selectedMovementProductId != null) {
      for (final option in _movementProductOptions) {
        if (option.id == _selectedMovementProductId) {
          selectedMovementProduct = option;
          break;
        }
      }
    }

    return RefreshIndicator(
      onRefresh: () => _loadAnalytics(showLoader: false),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 220) {
            _loadMoreMovements();
          }
          return false;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: [
            _buildSectionTitle('Istoric Operațiuni Stoc'),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                if (_movementProductOptions.isEmpty) {
                  final products = await _fetchMovementProductOptions(
                    gymId: _selectedGymId,
                  );
                  if (!mounted) return;
                  setState(() => _movementProductOptions = products);
                }

                final selected = await _showMovementProductPicker(
                  options: _movementProductOptions,
                  selectedProductId: _selectedMovementProductId,
                );

                if (!mounted || selected == null) return;
                final newValue = selected == '__all__' ? null : selected;
                if (newValue == _selectedMovementProductId) return;

                setState(() => _selectedMovementProductId = newValue);
                await _loadAnalytics(showLoader: false);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Filtru produs',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            selectedMovementProduct == null
                                ? 'Toate produsele'
                                : '${selectedMovementProduct.name} • ${selectedMovementProduct.gymName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedMovementProductId != null)
                      IconButton(
                        tooltip: 'Resetează produs',
                        onPressed: () async {
                          setState(() => _selectedMovementProductId = null);
                          await _loadAnalytics(showLoader: false);
                        },
                        icon: const Icon(Icons.close),
                      )
                    else
                      const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_movements.isEmpty)
              _buildEmptyCard('Nu există operațiuni în perioada selectată.')
            else
              ..._movements.map(_buildMovementCard),
            if (_movements.isNotEmpty && _isLoadingMoreMovements)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_movements.isNotEmpty &&
                !_isLoadingMoreMovements &&
                !_hasMoreMovements)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Toate operațiunile au fost încărcate',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementCard(ProductStockMovement movement) {
    final reasonColor = _reasonColor(context, movement.reason);
    final deltaLabel = movement.deltaQuantity > 0
        ? '+${movement.deltaQuantity}'
        : movement.deltaQuantity.toString();
    final deltaColor = movement.deltaQuantity >= 0 ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    movement.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: deltaColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Buc: $deltaLabel',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: deltaColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: reasonColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _reasonLabel(movement.reason),
                    style: TextStyle(
                      color: reasonColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                _buildEmployeeDetailChip(
                  icon: Icons.fitness_center,
                  label: movement.gymName,
                  color: const Color(0xFF5C6BC0),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    movement.createdByName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDateTime(movement.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.swap_horiz,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Stoc: ${movement.stockBefore} → ${movement.stockAfter}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (movement.countedStock != null)
                    Text(
                      'Numărat: ${movement.countedStock}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
            if (movement.verifiedAgainstUserName != null &&
                movement.verifiedAgainstUserName!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Verificat fata de: ${movement.verifiedAgainstUserName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (movement.notes != null &&
                movement.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  movement.notes!,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produse'),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filtre',
                onPressed: _showFilterSheet,
              ),
              if (_activeFiltersCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _activeFiltersCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reîncarcă',
            onPressed: () => _loadAnalytics(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Angajați'),
                    Tab(text: 'Produse'),
                    Tab(text: 'Mișcări Stoc'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(),
                      _buildEmployeesTab(),
                      _buildProductsTab(),
                      _buildMovementsTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _EmployeeSalesDetailScreen extends StatefulWidget {
  final EmployeeProductSales row;
  final String? gymId;
  final List<EmployeeProductSaleTransaction> initialTransactions;
  final String initialTimeRange;
  final DateTime? initialCustomDateStart;
  final DateTime? initialCustomDateEnd;

  const _EmployeeSalesDetailScreen({
    required this.row,
    required this.gymId,
    required this.initialTransactions,
    required this.initialTimeRange,
    required this.initialCustomDateStart,
    required this.initialCustomDateEnd,
  });

  @override
  State<_EmployeeSalesDetailScreen> createState() =>
      _EmployeeSalesDetailScreenState();
}

class _EmployeeProductSummary {
  final String productKey;
  final String productName;
  final int quantity;
  final int revenueCents;
  final int cashRevenueCents;
  final int cardRevenueCents;

  const _EmployeeProductSummary({
    required this.productKey,
    required this.productName,
    required this.quantity,
    required this.revenueCents,
    required this.cashRevenueCents,
    required this.cardRevenueCents,
  });
}

class _EmployeeProductFilterOption {
  final String key;
  final String label;
  final int quantity;
  final int revenueCents;

  const _EmployeeProductFilterOption({
    required this.key,
    required this.label,
    required this.quantity,
    required this.revenueCents,
  });

  _EmployeeProductFilterOption copyWith({int? quantity, int? revenueCents}) {
    return _EmployeeProductFilterOption(
      key: key,
      label: label,
      quantity: quantity ?? this.quantity,
      revenueCents: revenueCents ?? this.revenueCents,
    );
  }
}

class _FilteredEmployeeTransaction {
  final EmployeeProductSaleTransaction transaction;
  final List<ProductSaleTransactionItem> items;
  final int totalItems;
  final int totalCents;

  const _FilteredEmployeeTransaction({
    required this.transaction,
    required this.items,
    required this.totalItems,
    required this.totalCents,
  });
}

class _EmployeeSalesDetailScreenState
    extends State<_EmployeeSalesDetailScreen> {
  final ProductAdminAnalyticsService _service = ProductAdminAnalyticsService();

  late DateTime _startDate;
  late DateTime _endDate;
  bool _isLoading = false;
  late List<EmployeeProductSaleTransaction> _transactions;
  String? _selectedProductKey;

  @override
  void initState() {
    super.initState();
    final initialRange = _resolveInitialDateRange();
    _startDate = initialRange.start;
    _endDate = initialRange.end;
    _transactions = widget.initialTransactions;
  }

  DateTimeRange _resolveInitialDateRange() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    if (widget.initialTimeRange == 'custom' &&
        widget.initialCustomDateStart != null &&
        widget.initialCustomDateEnd != null) {
      return DateTimeRange(
        start: DateTime(
          widget.initialCustomDateStart!.year,
          widget.initialCustomDateStart!.month,
          widget.initialCustomDateStart!.day,
        ),
        end: DateTime(
          widget.initialCustomDateEnd!.year,
          widget.initialCustomDateEnd!.month,
          widget.initialCustomDateEnd!.day,
        ),
      );
    }

    switch (widget.initialTimeRange) {
      case 'month':
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case '7days':
        return DateTimeRange(
          start: startOfToday.subtract(const Duration(days: 6)),
          end: now,
        );
      case '30days':
        return DateTimeRange(
          start: startOfToday.subtract(const Duration(days: 29)),
          end: now,
        );
      case '90days':
        return DateTimeRange(
          start: startOfToday.subtract(const Duration(days: 89)),
          end: now,
        );
      case 'year':
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: now);
      case 'all':
        return DateTimeRange(
          start: DateTime(now.year - 5, now.month, now.day),
          end: now,
        );
      default:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
    }
  }

  DateTime _queryDateStart() =>
      DateTime(_startDate.year, _startDate.month, _startDate.day);

  DateTime _queryDateEnd() =>
      DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59, 999);

  String _formatDate(DateTime date) => DateFormat('dd MMM yyyy').format(date);

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked == null) return;
    setState(() {
      _startDate = picked.start;
      _endDate = picked.end;
    });
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final tx = await _service.fetchEmployeeSaleTransactions(
        gymId: widget.gymId,
        employeeId: widget.row.employeeId,
        dateStart: _queryDateStart(),
        dateEnd: _queryDateEnd(),
        limit: 500,
      );
      if (!mounted) return;
      setState(() {
        _transactions = tx;
        final availableKeys = <String>{};
        for (final sale in tx) {
          for (final item in sale.items) {
            availableKeys.add(_productKeyFromItem(item));
          }
        }
        if (_selectedProductKey != null &&
            !availableKeys.contains(_selectedProductKey)) {
          _selectedProductKey = null;
        }
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la încărcarea tranzacțiilor: $error')),
      );
    }
  }

  String _formatMoney(int cents, {String currency = 'RON'}) {
    final symbol = currency == 'EUR' ? '€' : 'RON';
    final amount = cents / 100.0;
    return '${NumberFormat('#,##0.00').format(amount)} $symbol';
  }

  String _paymentMethodLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Cash';
      case 'card':
        return 'Card';
      case 'bank':
        return 'Transfer';
      case 'stripe':
        return 'Stripe';
      default:
        return method;
    }
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('dd MMM yyyy, HH:mm').format(dt);
  }

  String _sanitizeProductName(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Produs necunoscut' : trimmed;
  }

  String _productKeyFromItem(ProductSaleTransactionItem item) {
    final productId = item.productId.trim();
    if (productId.isNotEmpty) {
      return 'id:$productId';
    }
    return 'name:${_sanitizeProductName(item.productName).toLowerCase()}';
  }

  List<_EmployeeProductFilterOption> _buildProductFilterOptions() {
    final map = <String, _EmployeeProductFilterOption>{};
    for (final tx in _transactions) {
      for (final item in tx.items) {
        final key = _productKeyFromItem(item);
        final label = _sanitizeProductName(item.productName);
        final current = map[key];
        if (current == null) {
          map[key] = _EmployeeProductFilterOption(
            key: key,
            label: label,
            quantity: item.quantity,
            revenueCents: item.lineTotalCents,
          );
        } else {
          map[key] = current.copyWith(
            quantity: current.quantity + item.quantity,
            revenueCents: current.revenueCents + item.lineTotalCents,
          );
        }
      }
    }

    final list = map.values.toList();
    list.sort((a, b) {
      final qtyCmp = b.quantity.compareTo(a.quantity);
      if (qtyCmp != 0) return qtyCmp;
      final revCmp = b.revenueCents.compareTo(a.revenueCents);
      if (revCmp != 0) return revCmp;
      return a.label.compareTo(b.label);
    });
    return list;
  }

  List<_FilteredEmployeeTransaction> _buildFilteredTransactions() {
    final list = <_FilteredEmployeeTransaction>[];

    for (final tx in _transactions) {
      final items = tx.items.where((item) {
        if (_selectedProductKey == null) return true;
        return _productKeyFromItem(item) == _selectedProductKey;
      }).toList();

      if (items.isEmpty) continue;

      list.add(
        _FilteredEmployeeTransaction(
          transaction: tx,
          items: items,
          totalItems: items.fold<int>(0, (sum, item) => sum + item.quantity),
          totalCents: items.fold<int>(
            0,
            (sum, item) => sum + item.lineTotalCents,
          ),
        ),
      );
    }

    return list;
  }

  List<_EmployeeProductSummary> _buildProductsSummary(
    List<_FilteredEmployeeTransaction> filteredTransactions,
  ) {
    final map = <String, _EmployeeProductSummary>{};
    for (final tx in filteredTransactions) {
      final method = tx.transaction.paymentMethod;
      for (final item in tx.items) {
        final key = _productKeyFromItem(item);
        final name = _sanitizeProductName(item.productName);
        final cashRevenue = method == 'cash' ? item.lineTotalCents : 0;
        final cardRevenue = method == 'card' ? item.lineTotalCents : 0;
        final current = map[key];
        if (current == null) {
          map[key] = _EmployeeProductSummary(
            productKey: key,
            productName: name,
            quantity: item.quantity,
            revenueCents: item.lineTotalCents,
            cashRevenueCents: cashRevenue,
            cardRevenueCents: cardRevenue,
          );
        } else {
          map[key] = _EmployeeProductSummary(
            productKey: key,
            productName: current.productName,
            quantity: current.quantity + item.quantity,
            revenueCents: current.revenueCents + item.lineTotalCents,
            cashRevenueCents: current.cashRevenueCents + cashRevenue,
            cardRevenueCents: current.cardRevenueCents + cardRevenue,
          );
        }
      }
    }
    final list = map.values.toList();
    list.sort((a, b) {
      final qtyCmp = b.quantity.compareTo(a.quantity);
      if (qtyCmp != 0) return qtyCmp;
      return b.revenueCents.compareTo(a.revenueCents);
    });
    return list;
  }

  Widget _buildProductDetailChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _productRankColor(int rank) {
    if (rank == 1) return const Color(0xFFFFB300);
    if (rank == 2) return const Color(0xFF90A4AE);
    if (rank == 3) return const Color(0xFFFF8A65);
    return const Color(0xFF5C6BC0);
  }

  Widget _buildEmployeeProductSummaryCard({
    required int index,
    required _EmployeeProductSummary summary,
    required int totalItems,
  }) {
    final rank = index + 1;
    final rankColor = _productRankColor(rank);
    final quantityShare = totalItems > 0
        ? (summary.quantity / totalItems) * 100
        : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: rankColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '#$rank',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: rankColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    summary.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatMoney(summary.revenueCents),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 14,
                    color: Color(0xFF1E88E5),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${summary.quantity} bucăți vândute',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${quantityShare.toStringAsFixed(quantityShare >= 10 ? 0 : 1)}%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E88E5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildProductDetailChip(
                  icon: Icons.payments_outlined,
                  label: 'Cash ${_formatMoney(summary.cashRevenueCents)}',
                  color: const Color(0xFF43A047),
                ),
                _buildProductDetailChip(
                  icon: Icons.credit_card,
                  label: 'Card ${_formatMoney(summary.cardRevenueCents)}',
                  color: const Color(0xFF1E88E5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productOptions = _buildProductFilterOptions();
    final filteredTransactions = _buildFilteredTransactions();
    final totalRevenue = filteredTransactions.fold<int>(
      0,
      (sum, tx) => sum + tx.totalCents,
    );
    final totalItems = filteredTransactions.fold<int>(
      0,
      (sum, tx) => sum + tx.totalItems,
    );
    final salesCount = filteredTransactions.length;
    final cashRevenue = filteredTransactions
        .where((tx) => tx.transaction.paymentMethod == 'cash')
        .fold<int>(0, (sum, tx) => sum + tx.totalCents);
    final cardRevenue = filteredTransactions
        .where((tx) => tx.transaction.paymentMethod == 'card')
        .fold<int>(0, (sum, tx) => sum + tx.totalCents);
    final productsSummary = _buildProductsSummary(filteredTransactions);
    final hasProductFilter = _selectedProductKey != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.row.employeeName),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Schimbă perioada',
            onPressed: _selectDateRange,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reîncarcă',
            onPressed: _loadTransactions,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
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
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_formatDate(_startDate)} - ${_formatDate(_endDate)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
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
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<String?>(
                initialValue: _selectedProductKey,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Filtru produs',
                  prefixIcon: const Icon(Icons.inventory_2_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                  suffixIcon: _selectedProductKey == null
                      ? null
                      : IconButton(
                          tooltip: 'Resetează filtrul',
                          icon: const Icon(Icons.clear),
                          onPressed: () =>
                              setState(() => _selectedProductKey = null),
                        ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Toate produsele'),
                  ),
                  ...productOptions.map((option) {
                    final label = '${option.label} (${option.quantity})';
                    return DropdownMenuItem<String?>(
                      value: option.key,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
                onChanged: (value) =>
                    setState(() => _selectedProductKey = value),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.row.gymName,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatMoney(totalRevenue),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Column(
                    children: [
                      _EmployeeStatCard(
                        title: 'Bucăți vândute',
                        value: '$totalItems',
                        icon: '📦',
                        color: const Color(0xFF1E88E5),
                      ),
                      const SizedBox(height: 8),
                      _EmployeeStatCard(
                        title: 'Vânzări',
                        value: '$salesCount',
                        icon: '🧾',
                        color: const Color(0xFF43A047),
                      ),
                      const SizedBox(height: 8),
                      _EmployeeStatCard(
                        title: 'Cash',
                        value: _formatMoney(cashRevenue),
                        icon: '💵',
                        color: const Color(0xFFFB8C00),
                      ),
                      const SizedBox(height: 8),
                      _EmployeeStatCard(
                        title: 'Card',
                        value: _formatMoney(cardRevenue),
                        icon: '💳',
                        color: const Color(0xFF8E24AA),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Produse Vândute (${productsSummary.length})',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (productsSummary.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  hasProductFilter
                      ? 'Nu există produse vândute pentru filtrul selectat.'
                      : 'Nu există produse vândute în perioada selectată.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...productsSummary
                .take(15)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) => _buildEmployeeProductSummaryCard(
                    index: entry.key,
                    summary: entry.value,
                    totalItems: totalItems,
                  ),
                ),
          if (productsSummary.length > 15)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(
                'Se afișează primele 15 produse.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Tranzacții (${filteredTransactions.length})',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_isLoading)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (filteredTransactions.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  hasProductFilter
                      ? 'Nu există tranzacții pentru produsul selectat în intervalul curent.'
                      : 'Nu există tranzacții detaliate pentru acest angajat în intervalul selectat.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ...filteredTransactions.map((filteredTx) {
              final tx = filteredTx.transaction;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {},
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
                                '${_formatDateTime(tx.soldAt)} • ${filteredTx.totalItems} buc.',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '+ ${_formatMoney(filteredTx.totalCents)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  tx.paymentMethod == 'cash'
                                      ? Icons.money
                                      : Icons.credit_card,
                                  size: 14,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _paymentMethodLabel(tx.paymentMethod),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fitness_center,
                                  size: 14,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  tx.gymName,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: filteredTx.items
                                .map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${item.productName} x${item.quantity}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          _formatMoney(item.lineTotalCents),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EmployeeStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String icon;
  final Color color;

  const _EmployeeStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
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
                      color.withValues(alpha: 0.05),
                      color.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(icon, style: const TextStyle(fontSize: 24)),
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
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: color,
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
  }
}
