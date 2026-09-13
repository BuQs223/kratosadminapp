import { test, expect } from '@jest/globals';
import { parseMembership } from '@/models/membership';
import { parseCheckIn } from '@/models/check-in';
import { asBoolean, asNullableDate, flutterNullableTruncatedNumber } from './parsing';

test('malformed numeric/date values fail instead of becoming zero, null or today', () => {
  expect(() => parseMembership({ price_paid_cents: 'broken' })).toThrow('Expected an integer');
  expect(() => parseCheckIn({ created_at: '2026-09-13', days_left: 'broken' })).toThrow('Expected an integer');
  expect(() => asNullableDate('broken')).toThrow('Invalid DateTime');
  expect(() => asNullableDate('')).toThrow('Invalid DateTime');
  expect(flutterNullableTruncatedNumber(3.9)).toBe(3);
  expect(flutterNullableTruncatedNumber(null)).toBeNull();
  expect(asBoolean(2)).toBe(true);
  expect(asBoolean('TRUE')).toBe(true);
});
