import { parseFlutterDate } from '@/utils/flutter-date';

export type JsonRecord = Record<string, unknown>;

export function asRecord(value: unknown): JsonRecord {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as JsonRecord)
    : {};
}

export function asRecords(value: unknown): JsonRecord[] {
  return Array.isArray(value) ? value.map(asRecord) : [];
}

export function asString(value: unknown, fallback = ''): string {
  return value === null || value === undefined ? fallback : String(value);
}

export function asNullableString(value: unknown): string | null {
  return value === null || value === undefined ? null : String(value);
}

export function asNumber(value: unknown, fallback = 0): number {
  if (value === null || value === undefined) return fallback;
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function asInteger(value: unknown, fallback = 0): number {
  return Math.trunc(asNumber(value, fallback));
}

export function asNullableInteger(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : null;
}

export function asBoolean(value: unknown, fallback = false): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (typeof value === 'string') return value === '1' || value.toLowerCase() === 'true';
  return fallback;
}

export function asDate(value: unknown, fallback = new Date()): Date {
  return value === null || value === undefined ? fallback : parseFlutterDate(value instanceof Date ? value : asString(value));
}

export function asNullableDate(value: unknown): Date | null {
  return value === null || value === undefined ? null : parseFlutterDate(value instanceof Date ? value : asString(value));
}

export function firstRecord(value: unknown): JsonRecord {
  return Array.isArray(value) ? asRecord(value[0]) : asRecord(value);
}

export function requiredDate(value: unknown): Date {
  if (typeof value !== 'string') throw new Error('Expected a DateTime string');
  return parseFlutterDate(value);
}
export function requiredString(value: unknown): string {
  if (typeof value !== 'string') throw new Error('Expected a string');
  return value;
}
export function requiredInteger(value: unknown): number {
  if (typeof value !== 'number' || !Number.isInteger(value)) throw new Error('Expected an integer');
  return value;
}

/** Dart's casts reject malformed numeric values instead of manufacturing zero. */
export function flutterNumber(value: unknown, fallback = 0): number {
  if (value == null) return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('Expected a number');
  return value;
}
export function flutterInteger(value: unknown, fallback = 0): number {
  return value == null ? fallback : requiredInteger(value);
}
export function flutterNullableInteger(value: unknown): number | null {
  return value == null ? null : requiredInteger(value);
}
export function flutterNullableTruncatedNumber(value: unknown): number | null {
  return value == null ? null : Math.trunc(flutterNumber(value));
}
