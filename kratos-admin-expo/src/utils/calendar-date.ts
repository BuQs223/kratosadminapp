/** A civil calendar date. It is never serialized as an instant. */
export type CalendarDate = string;

export interface CalendarDateRange {
  start: CalendarDate;
  end: CalendarDate;
}

const calendarDatePattern = /^\d{4}-(\d{2})-(\d{2})$/;

function parts(value: CalendarDate): { year: number; month: number; day: number } {
  if (!isCalendarDate(value)) throw new Error(`Dată calendaristică invalidă: ${value}`);
  return { year: Number(value.slice(0, 4)), month: Number(value.slice(5, 7)), day: Number(value.slice(8, 10)) };
}

export function isCalendarDate(value: unknown): value is CalendarDate {
  if (typeof value !== 'string' || !calendarDatePattern.test(value)) return false;
  const year = Number(value.slice(0, 4));
  const month = Number(value.slice(5, 7));
  const day = Number(value.slice(8, 10));
  const candidate = new Date(Date.UTC(year, month - 1, day));
  return candidate.getUTCFullYear() === year
    && candidate.getUTCMonth() === month - 1
    && candidate.getUTCDate() === day;
}

export function assertCalendarDate(value: unknown): CalendarDate {
  if (!isCalendarDate(value)) throw new Error(`Dată calendaristică invalidă: ${String(value)}`);
  return value;
}

export function calendarDateFromLocalDate(value: Date): CalendarDate {
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, '0');
  const day = String(value.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function todayCalendarDate(now = new Date()): CalendarDate {
  return calendarDateFromLocalDate(now);
}

export function calendarDateToLocalDate(value: CalendarDate): Date {
  const { year, month, day } = parts(value);
  return new Date(year, month - 1, day);
}

export function compareCalendarDates(left: CalendarDate, right: CalendarDate): number {
  assertCalendarDate(left);
  assertCalendarDate(right);
  return left < right ? -1 : left > right ? 1 : 0;
}

export function addCalendarDays(value: CalendarDate, days: number): CalendarDate {
  const { year, month, day } = parts(value);
  const next = new Date(Date.UTC(year, month - 1, day + days));
  return `${next.getUTCFullYear()}-${String(next.getUTCMonth() + 1).padStart(2, '0')}-${String(next.getUTCDate()).padStart(2, '0')}`;
}

export function calendarDaysBetween(start: CalendarDate, end: CalendarDate): number {
  const left = parts(start);
  const right = parts(end);
  return Math.round((Date.UTC(right.year, right.month - 1, right.day) - Date.UTC(left.year, left.month - 1, left.day)) / 86_400_000);
}

export function expandCalendarDateRange(range: CalendarDateRange): CalendarDate[] {
  if (compareCalendarDates(range.start, range.end) > 0) return [];
  const dates: CalendarDate[] = [];
  for (let value = range.start; compareCalendarDates(value, range.end) <= 0; value = addCalendarDays(value, 1)) {
    dates.push(value);
  }
  return dates;
}

export function formatCalendarDate(value: CalendarDate, options: Intl.DateTimeFormatOptions = {
  day: '2-digit', month: 'short', year: 'numeric',
}): string {
  return new Intl.DateTimeFormat('ro-RO', options).format(calendarDateToLocalDate(value));
}

export function calendarDateRangeLabel(range: CalendarDateRange): string {
  return `${formatCalendarDate(range.start)} – ${formatCalendarDate(range.end)}`;
}

/** SQL expression for timestamps whose civil day should match the device-local UI calendar. */
export function sqliteLocalCalendarDate(column: string): string {
  return `date(${column}, 'localtime')`;
}

export function sqliteCalendarDateRangePredicate(
  column: string,
  startParameter = '?',
  endParameter = '?',
): string {
  const date = sqliteLocalCalendarDate(column);
  return `${date} >= date(${startParameter}) AND ${date} <= date(${endParameter})`;
}
