import { describe, expect, test } from '@jest/globals';

import { checkInDuration, parseCheckIn } from '@/models/check-in';

describe('check-in parsing', () => {
  test('accepts created_at as the Flutter-compatible timestamp fallback', () => {
    const checkIn = parseCheckIn({
      id: 'c1',
      created_at: '2026-08-03T10:00:00.000Z',
      checked_out_at: '2026-08-03T11:35:00.000Z',
      shown_to_user: 1,
    });
    expect(checkIn.shownToUser).toBe(true);
    expect(checkInDuration(checkIn)).toBe('1h 35m');
  });

  test('rejects rows without a usable timestamp', () => {
    expect(() => parseCheckIn({ id: 'bad' })).toThrow('No valid timestamp');
  });
});
