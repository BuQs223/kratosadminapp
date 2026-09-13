import { describe, expect, test } from '@jest/globals';

import { parseMembershipTrendPoint } from '@/models/membership-trend';

describe('membership trend parsing', () => {
  test('parses the admin RPC fields into typed values', () => {
    const point = parseMembershipTrendPoint({
      period_start: '2026-08-01',
      period_end: '2026-08-07',
      active_people: '876',
      new_activations: 14,
      is_estimated: 'true',
      computed_at: '2026-08-08T00:15:00.000Z',
    });

    expect(point).toMatchObject({
      activePeople: 876,
      newActivations: 14,
      isEstimated: true,
    });
    expect(point.periodStart.toISOString()).toContain('2026-08-01');
  });
});
