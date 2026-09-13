import { describe, expect, test } from '@jest/globals';

import { revenueAmountFilterClause } from '@/repositories/revenue-amount-filter';

describe('revenue amount filters', () => {
  test('non-zero filter keeps real transactions while excluding zero-value rows', () => {
    expect(revenueAmountFilterClause('non_zero')).toBe(
      'COALESCE(r.amount_cents, 0) > 0',
    );
  });

  test('all does not add an amount condition', () => {
    expect(revenueAmountFilterClause('all')).toBeUndefined();
  });
});
