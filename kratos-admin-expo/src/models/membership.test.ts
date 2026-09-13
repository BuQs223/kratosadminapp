import { describe, expect, test } from '@jest/globals';

import {
  membershipDaysUntilExpiry,
  membershipIsExpired,
  membershipStatusText,
  parseMembership,
  parseOptimizedMembership,
} from '@/models/membership';

const now = new Date('2026-08-03T12:00:00.000Z');

describe('membership parity with Flutter', () => {
  test('database days_left takes precedence over the end date', () => {
    const membership = parseMembership({
      id: 'm1',
      end_date: '2030-01-01T00:00:00.000Z',
      days_left: -2,
    });
    expect(membershipIsExpired(membership, now)).toBe(true);
    expect(membershipDaysUntilExpiry(membership, now)).toBe(0);
    expect(membershipStatusText(membership)).toBe('Expirat');
  });

  test('status priority is canceled, expired, frozen, expiring, active', () => {
    const base = {
      id: 'm1',
      end_date: '2026-08-20T00:00:00.000Z',
      days_left: 5,
    };
    expect(membershipStatusText(parseMembership(base))).toBe('Expiră în 5 zile');
    expect(membershipStatusText(parseMembership({ ...base, is_frozen: 1 }))).toBe('Înghețat');
    expect(membershipStatusText(parseMembership({ ...base, canceled_at: now.toISOString() }))).toBe(
      'Anulat',
    );
  });

  test('optimized PowerSync rows include plan and sold-at gym relations', () => {
    const membership = parseOptimizedMembership({
      membership_id: 'm1',
      membership_plan_id: 'p1',
      plan_name: 'Gold',
      tier: 'gold',
      sold_at_gym_id: 'g1',
      sold_at_gym_name: 'Kratos 1',
      end_date: '2026-09-01T00:00:00.000Z',
    });
    expect(membership.plan).toMatchObject({ id: 'p1', name: 'Gold', tier: 'gold' });
    expect(membership.gym).toMatchObject({ id: 'g1', name: 'Kratos 1' });
  });
});
