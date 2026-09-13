import { describe, expect, test } from '@jest/globals';

import {
  addCalendarDays,
  assertCalendarDate,
  calendarDateFromLocalDate,
  calendarDateToLocalDate,
  expandCalendarDateRange,
  sqliteCalendarDateRangePredicate,
} from '@/utils/calendar-date';

describe('calendar-date', () => {
  test('keeps a civil calendar date intact when converting to and from a local Date', () => {
    const source = '2026-08-13';
    expect(calendarDateFromLocalDate(calendarDateToLocalDate(source))).toBe(source);
  });

  test('validates date-only input and rejects malformed or impossible values', () => {
    expect(assertCalendarDate('2024-02-29')).toBe('2024-02-29');
    expect(() => assertCalendarDate('2024-02-30')).toThrow('Dată calendaristică invalidă');
    expect(() => assertCalendarDate('2024-2-9')).toThrow('Dată calendaristică invalidă');
  });

  test('performs date arithmetic and inclusive range expansion without timestamps', () => {
    expect(addCalendarDays('2026-02-28', 1)).toBe('2026-03-01');
    expect(expandCalendarDateRange({ start: '2026-03-30', end: '2026-04-01' })).toEqual([
      '2026-03-30',
      '2026-03-31',
      '2026-04-01',
    ]);
  });

  test('builds a SQLite local-calendar predicate for timestamp filtering', () => {
    expect(sqliteCalendarDateRangePredicate('r.paid_at')).toBe(
      "date(r.paid_at, 'localtime') >= date(?) AND date(r.paid_at, 'localtime') <= date(?)",
    );
  });
});
