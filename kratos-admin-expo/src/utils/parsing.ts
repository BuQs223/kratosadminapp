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
  if (value === 1 || value === '1' || value === 'true') return true;
  if (value === 0 || value === '0' || value === 'false') return false;
  return fallback;
}

export function asDate(value: unknown, fallback = new Date()): Date {
  const parsed = value instanceof Date ? value : new Date(asString(value));
  return Number.isNaN(parsed.getTime()) ? fallback : parsed;
}

export function asNullableDate(value: unknown): Date | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = value instanceof Date ? value : new Date(asString(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export function firstRecord(value: unknown): JsonRecord {
  return Array.isArray(value) ? asRecord(value[0]) : asRecord(value);
}
