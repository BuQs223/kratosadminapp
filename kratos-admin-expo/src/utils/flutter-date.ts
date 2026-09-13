/** DateTime compatibility for the Flutter admin's persisted dates and report windows.
 * Local Dart DateTime serializes without an offset; parsed offset-bearing dates stay UTC.
 * Duration(days: n) is elapsed time, including across daylight-saving transitions.
 */
import { calendarDateFromLocalDate, calendarDateToLocalDate, type CalendarDate } from '@/utils/calendar-date';

const utcDates = new WeakSet<Date>();
const microseconds = new WeakMap<Date, number>();
export const dayMilliseconds = 86_400_000;
const pad = (value: number, width = 2) => String(value).padStart(width, '0');

export function parseFlutterDate(value: string | Date): Date {
  if (value instanceof Date) return value;
  // Same accepted ISO components and overflow normalization as Dart DateTime.parse.
  const match = /^([+-]?\d{4,6})-?(\d\d)-?(\d\d)(?:[ T](\d\d)(?::?(\d\d)(?::?(\d\d)(?:[.,](\d+))?)?)?( ?[zZ]| ?([-+])(\d\d)(?::?(\d\d))?)?)?$/.exec(value);
  if (!match) throw new Error(`Invalid DateTime: ${value}`);
  const [, year, month, day, hour, minute, second, fraction, zone, sign, offsetHour, offsetMinute] = match;
  const utc = zone !== undefined;
  const micros = Number((fraction ?? '').padEnd(6, '0').slice(0, 6));
  const adjustedMinute = Number(minute ?? 0) - (sign ? (sign === '-' ? -1 : 1) * (Number(offsetHour) * 60 + Number(offsetMinute ?? 0)) : 0);
  const date = new Date(0);
  if (utc) {
    date.setUTCFullYear(Number(year), Number(month) - 1, Number(day));
    date.setUTCHours(Number(hour ?? 0), adjustedMinute, Number(second ?? 0), Math.trunc(micros / 1000));
    utcDates.add(date);
  } else {
    date.setFullYear(Number(year), Number(month) - 1, Number(day));
    date.setHours(Number(hour ?? 0), adjustedMinute, Number(second ?? 0), Math.trunc(micros / 1000));
  }
  if (!Number.isFinite(date.getTime())) throw new Error(`Invalid DateTime: ${value}`);
  microseconds.set(date, micros % 1000);
  return date;
}

export function flutterCalendarDate(date: Date): CalendarDate {
  return utcDates.has(date) ? date.toISOString().slice(0, 10) : calendarDateFromLocalDate(date);
}

export function flutterDateTimeIso(date: Date): string {
  const extra = microseconds.get(date) ?? 0;
  const suffix = extra ? pad(extra, 3) : '';
  if (utcDates.has(date)) return date.toISOString().replace('Z', `${suffix}Z`);
  return `${calendarDateFromLocalDate(date)}T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}.${pad(date.getMilliseconds(), 3)}${suffix}`;
}

export function elapsedDays(date: Date, days: number): Date {
  const result = new Date(date.getTime() + days * dayMilliseconds);
  if (utcDates.has(date)) utcDates.add(result);
  microseconds.set(result, microseconds.get(date) ?? 0);
  return result;
}
export function localMidnight(date: Date): Date { return new Date(date.getFullYear(), date.getMonth(), date.getDate()); }
export function reportStart(value: string): string { return value.length === 10 ? `${value}T00:00:00.000` : value; }
export function reportEnd(value: string, milliseconds = 999): string { return value.length === 10 ? `${value}T23:59:59.${pad(milliseconds, 3)}` : value; }
export function sqliteFlutterRange(column: string): string { return `datetime(${column}) >= datetime(?) AND datetime(${column}) <= datetime(?)`; }

export type ReportRange = { start: string; end: string };
export function revenueAnalyticsRange(range: string, customStart?: CalendarDate, customEnd?: CalendarDate, now = new Date()): ReportRange {
  let start = elapsedDays(now, range === '7days' ? -7 : range === '90days' ? -90 : -30);
  if (range === 'year') start = new Date(now.getFullYear(), 0, 1);
  if (range === 'all') start = new Date(2020, 0, 1);
  return {
    start: range === 'custom' && customStart ? reportStart(customStart) : flutterDateTimeIso(start),
    end: range === 'custom' && customEnd ? reportEnd(customEnd) : flutterDateTimeIso(now),
  };
}

export function comparisonPeriodRange(type: string, current?: ReportRange, now = new Date()): ReportRange {
  if (type === 'custom' && current) return current;
  let start: Date;
  let end: Date;
  if (type.endsWith('month')) {
    const month = now.getMonth() - (type === 'last_month' ? 1 : 0);
    start = new Date(now.getFullYear(), month, 1);
    end = new Date(now.getFullYear(), month + 1, 0, 23, 59, 59);
  } else if (type.endsWith('year')) {
    const year = now.getFullYear() - (type === 'last_year' ? 1 : 0);
    start = new Date(year, 0, 1);
    end = new Date(year, 11, 31, 23, 59, 59);
  } else {
    const monday = elapsedDays(now, -((now.getDay() + 6) % 7));
    start = localMidnight(type === 'last_week' ? elapsedDays(monday, -7) : monday);
    end = new Date(start.getTime() + 7 * dayMilliseconds - 1000);
  }
  return { start: flutterDateTimeIso(start), end: flutterDateTimeIso(end) };
}

/** end is exclusive and is captured when the user applies the preset. */
export function checkInPresetRange(preset: string, now = new Date()): ReportRange {
  let start = localMidnight(elapsedDays(now, preset === 'last7Days' ? -6 : preset === 'last30Days' ? -29 : 0));
  if (preset === 'thisMonth') start = new Date(now.getFullYear(), now.getMonth(), 1);
  return { start: flutterDateTimeIso(start), end: flutterDateTimeIso(new Date(now.getTime() + 1000)) };
}
export function checkInCustomRange(start: CalendarDate, end: CalendarDate): ReportRange {
  return { start: reportStart(start), end: flutterDateTimeIso(elapsedDays(calendarDateToLocalDate(end), 1)) };
}
