# Zero Amount Transaction Filter Feature

## Overview
Added a filter to the revenue screen that allows users to view transactions based on their amount, specifically to identify transactions with 0 RON amount.

## Implementation Date
January 2025

## Client Request
The client requested a way to see all transactions that have the price set to 0.

## Database Statistics
As of implementation:
- **Total charge transactions**: 1,237
- **Zero amount transactions**: 35 (2.8%)
- **Non-zero amount transactions**: 1,202 (97.2%)

## Technical Implementation

### 1. Database Changes
Created migration: `add_amount_filter_to_revenue_function`

**Function Updated**: `get_revenue_with_filters`

**New Parameter**: 
```sql
p_amount_filter text DEFAULT 'all'
```

**Filter Values**:
- `'all'` - Shows all transactions (default)
- `'zero'` - Shows only transactions with amount_cents = 0
- `'non_zero'` - Shows only transactions with amount_cents > 0

**SQL Implementation**:
```sql
WHERE 
  (p_amount_filter = 'all' OR 
   (p_amount_filter = 'zero' AND rl.amount_cents = 0) OR 
   (p_amount_filter = 'non_zero' AND rl.amount_cents > 0))
```

The filter is applied in both:
- The aggregate calculation (for stats)
- The main result query (for transaction list)

### 2. Flutter Changes

#### State Management
**File**: `lib/screens/revenue/revenue_screen.dart`

**Added State Variable**:
```dart
String _amountFilter = 'all';
```

**Clear Filters**:
```dart
onClearFilters: () {
  setState(() {
    _amountFilter = 'all';
    // ... other filter resets
  });
}
```

**Filter Count Badge**:
```dart
int get _activeFiltersCount {
  int count = 0;
  if (_amountFilter != 'all') count++;
  // ... other filter checks
  return count;
}
```

#### API Integration
**RPC Call Update**:
```dart
final response = await supabase.rpc('get_revenue_with_filters', params: {
  'p_gym_id': _selectedGymId,
  'p_payment_method': _paymentMethodFilter,
  'p_plan_id': _selectedPlanId,
  'p_amount_filter': _amountFilter,  // ← New parameter
  'p_date_start': _customDateStart?.toIso8601String(),
  'p_date_end': _customDateEnd?.toIso8601String(),
  'p_limit': _pageSize,
  'p_offset': _currentOffset,
});
```

#### User Interface
**Filter Bottom Sheet Updates**:

1. **Widget Signature**:
   - Added `final String amountFilter;` property
   - Updated callback to 6 parameters: `Function(String?, String, String?, String, DateTime?, DateTime?)`
   - Added `amountFilter` to constructor parameters

2. **State Management**:
   ```dart
   late String _amountFilter;
   
   @override
   void initState() {
     _amountFilter = widget.amountFilter;
     // ... other initializations
   }
   ```

3. **UI Controls** (Added after Payment Method Filter):
   ```dart
   // Amount Filter
   Text(
     'Filtrează după sumă',
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
         selected: _amountFilter == 'all',
         onSelected: (selected) {
           setState(() => _amountFilter = 'all');
         },
       ),
       FilterChip(
         label: const Text('Doar 0 RON'),
         selected: _amountFilter == 'zero',
         onSelected: (selected) {
           setState(() => _amountFilter = 'zero');
         },
       ),
       FilterChip(
         label: const Text('Peste 0 RON'),
         selected: _amountFilter == 'non_zero',
         onSelected: (selected) {
           setState(() => _amountFilter = 'non_zero');
         },
       ),
     ],
   ),
   ```

4. **Apply Filters Callback**:
   ```dart
   widget.onApplyFilters(
     _selectedGymId,
     _paymentMethodFilter,
     _selectedPlanId,
     _amountFilter,  // ← New parameter
     _customDateStart,
     _customDateEnd,
   );
   ```

## User Experience

### Accessing the Filter
1. Navigate to **Revenue** screen
2. Tap the **Filter** button (funnel icon in app bar)
3. Scroll to the **"Filtrează după sumă"** section
4. Select one of three options:
   - **"Toate"** - View all transactions (default)
   - **"Doar 0 RON"** - View only zero-amount transactions
   - **"Peste 0 RON"** - View only non-zero transactions
5. Tap **"Aplică Filtre"** button

### Filter Badge
When the amount filter is active (not set to "Toate"), a badge counter appears on the filter button showing the number of active filters.

### Clear Filters
Tap **"Șterge Filtre"** button to reset all filters, including the amount filter, to their default values.

## Use Cases

### Why Zero-Amount Transactions?
Zero-amount transactions typically represent:
- **Promotional memberships** (free trials)
- **Complimentary access** (staff, VIPs, influencers)
- **Test transactions** (data entry testing)
- **Data corrections** (adjustments made during migration)
- **Special arrangements** (barter deals, sponsorships)

### Business Value
- **Audit trail**: Track which members have free/promotional memberships
- **Financial reporting**: Separate paid vs complimentary memberships
- **Promotion management**: Monitor usage of free trial offers
- **Data quality**: Identify potential data entry errors
- **Compliance**: Document non-revenue generating memberships

## Combining Filters
The amount filter can be combined with other filters:
- **Gym**: View zero-amount transactions for a specific location
- **Payment Method**: Not applicable for zero-amount (will show empty results)
- **Plan**: View which membership plans have zero-amount transactions
- **Date Range**: View zero-amount transactions within a time period

Example: "Show me all free trial memberships (0 RON) for the Downtown gym in January 2025"

## Performance
The filter is applied at the database level, so:
- ✅ Efficient query execution (indexed columns)
- ✅ Reduced data transfer (only matching rows returned)
- ✅ Accurate pagination (offset/limit applied after filtering)
- ✅ Correct statistics (aggregate functions respect filter)

## Statistics Impact
When amount filter is active, the statistics cards update to reflect only the filtered transactions:
- **Total Încasări**: Sum of filtered transactions
- **Total Tranzacții**: Count of filtered transactions
- **Medie per Tranzacție**: Average of filtered amounts

Note: For zero-amount filter, all stats will show 0 RON (except transaction count).

## Testing Checklist
- [x] Database function accepts amount_filter parameter
- [x] Database function filters correctly for 'zero' value
- [x] Database function filters correctly for 'non_zero' value
- [x] Flutter RPC call passes parameter
- [x] Filter UI displays correctly
- [x] Filter state persists during session
- [x] Filter badge counts include amount filter
- [x] Clear filters resets amount filter
- [x] Compilation succeeds with no errors
- [ ] Manual UI testing (requires running app)
- [ ] Verify zero-amount transactions display (35 expected)
- [ ] Verify statistics update correctly
- [ ] Test pagination with filter active
- [ ] Test combining with other filters

## Related Features
- **Swipe-to-edit/delete**: Zero-amount transactions can be edited or deleted like any other transaction
- **Revenue Dashboard**: Dashboard shows total revenue (including or excluding zero-amount based on use case)
- **Membership Plans**: Some plans may be configured with 0 RON price for promotional purposes

## Future Enhancements
Possible improvements:
1. **Custom amount ranges**: Filter by amount > X or between X-Y
2. **Refund filter**: Separate filter for entry_kind = 'refund'
3. **Negative amounts**: Special handling for refunds/corrections
4. **Amount presets**: Quick filters like "< 50 RON", "50-100 RON", "> 100 RON"
5. **Export filtered data**: CSV/PDF export with amount filter applied
6. **Analytics**: Chart showing distribution of zero vs non-zero transactions over time

## Notes
- The filter defaults to "all" to maintain existing behavior
- Zero-amount transactions are valid and intentional (not errors)
- The implementation follows the same pattern as other filters (payment method, gym, plan)
- Server-side filtering prevents client-side performance issues with large datasets
