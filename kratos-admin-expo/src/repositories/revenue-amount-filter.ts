export type AmountFilter = 'all' | 'zero' | 'non_zero';

export function revenueAmountFilterClause(filter?: AmountFilter): string | undefined {
  if (filter === 'zero') return 'COALESCE(r.amount_cents, 0) = 0';
  if (filter === 'non_zero') return 'COALESCE(r.amount_cents, 0) > 0';
  return undefined;
}
