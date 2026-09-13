import { test, expect } from '@jest/globals';
import { revenueCsv } from './revenue-csv';

test('CSV matches Flutter raw-row defaults, escaping, deletion marker, BOM and final newline', () => {
  const csv = revenueCsv([{ paid_at: '2026-09-13T10:30:00', profile_full_name: 'A, "B"', amount_cents: 1999, payment_method: 'cash', gym_name: 'Kratos 1', notes: 'first\nsecond', is_deleted: 1 }]);
  expect(csv.startsWith('\uFEFFData,Membru,')).toBe(true);
  expect(csv).toContain('13/09/2026 10:30,"A, ""B""",19.99,cash,Kratos 1,,"first\nsecond",,Șters,,\n');
});

test('invalid dates fail export instead of printing NaN', () => {
  expect(() => revenueCsv([{ paid_at: 'bad-date' }])).toThrow('Invalid DateTime');
});
