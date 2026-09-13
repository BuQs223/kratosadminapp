import { DatabaseSync, type SQLInputValue } from 'node:sqlite';
import { afterEach, beforeEach, expect, jest, test } from '@jest/globals';
import { applyFreezeAction, getFreezeData, resumedEndDate } from './membership-freeze-repository';

let mockDatabase: DatabaseSync;
const mockSession = jest.fn(async () => ({ data: { session: { user: { id: 'admin' } } }, error: null }));
const mockTx = {
  get: async (sql: string, params: SQLInputValue[] = []) => mockDatabase.prepare(sql).get(...params),
  getOptional: async (sql: string, params: SQLInputValue[] = []) => mockDatabase.prepare(sql).get(...params) ?? null,
  getAll: async (sql: string, params: SQLInputValue[] = []) => mockDatabase.prepare(sql).all(...params),
  execute: async (sql: string, params: SQLInputValue[] = []) => mockDatabase.prepare(sql).run(...params),
};
jest.mock('@/lib/powersync/system', () => ({
  connectPowerSyncIfAuthenticated: async () => {},
  powerSync: {
    getAll: (sql: string, params: SQLInputValue[]) => mockTx.getAll(sql, params),
    writeTransaction: async (callback: (tx: typeof mockTx) => Promise<void>) => {
      mockDatabase.exec('BEGIN');
      try { await callback(mockTx); mockDatabase.exec('COMMIT'); }
      catch (error) { mockDatabase.exec('ROLLBACK'); throw error; }
    },
  },
}));
jest.mock('@/lib/supabase/client', () => ({ getSupabase: () => ({ auth: { getSession: mockSession } }) }));

beforeEach(() => {
  jest.useFakeTimers().setSystemTime(new Date(2026, 8, 14, 15, 30));
  mockDatabase = new DatabaseSync(':memory:');
  mockDatabase.exec(`
    CREATE TABLE profiles (id TEXT PRIMARY KEY, full_name TEXT);
    CREATE TABLE family_memberships (user_id TEXT, membership_id TEXT);
    CREATE TABLE membership_plans (id TEXT PRIMARY KEY, name TEXT, duration_months INTEGER);
    CREATE TABLE memberships (id TEXT PRIMARY KEY, user_id TEXT, plan_id TEXT, duration_months INTEGER,
      start_date TEXT, end_date TEXT, is_active INTEGER, is_frozen INTEGER DEFAULT 0, canceled_at TEXT,
      frozen_at TEXT, frozen_by_user_id TEXT, days_left INTEGER, days_left_when_frozen INTEGER,
      freeze_type TEXT, auto_unfreeze_at TEXT, updated_at TEXT);
    CREATE TABLE membership_events (id TEXT PRIMARY KEY, membership_id TEXT, event_type TEXT, at TEXT,
      notes TEXT, delta_days INTEGER, by_user TEXT, old_start_date TEXT, old_end_date TEXT, new_end_date TEXT, plan_id TEXT);
    CREATE TABLE membership_freeze_schedules (id TEXT PRIMARY KEY, membership_id TEXT, duration_days INTEGER,
      freeze_type TEXT, scheduled_start_date TEXT, status TEXT, created_by_user_id TEXT, canceled_by_user_id TEXT,
      canceled_at TEXT, notes TEXT, created_at TEXT, updated_at TEXT);
    INSERT INTO profiles VALUES ('admin', 'Alex');
    INSERT INTO membership_plans VALUES ('plan', 'Gold', 3);
    INSERT INTO memberships (id, user_id, plan_id, duration_months, start_date, end_date, is_active, days_left)
      VALUES ('membership', 'client', 'plan', 3, '2026-09-01', '2026-10-01', 1, 17);
  `);
});
afterEach(() => { mockDatabase.close(); jest.useRealTimers(); });
const membership = () => mockDatabase.prepare('SELECT * FROM memberships').get()!;
const events = () => mockDatabase.prepare('SELECT * FROM membership_events ORDER BY rowid').all();

test.each(['manual', 'auto_5_days', 'auto_14_days'] as const)('%s preserves stored days and records an attributed pause without changing expiry', async (mode) => {
  await applyFreezeAction('client', { kind: 'freeze', membershipId: 'membership', mode });
  expect(membership()).toMatchObject({ is_frozen: 1, days_left_when_frozen: 17, end_date: '2026-10-01', freeze_type: mode,
    frozen_by_user_id: 'admin', frozen_at: '2026-09-14 15:30:00',
    auto_unfreeze_at: mode === 'manual' ? null : mode === 'auto_5_days' ? '2026-09-19 15:30:00' : '2026-09-28 15:30:00' });
  expect(events()).toHaveLength(1);
  expect(events()[0]).toMatchObject({ event_type: 'paused', delta_days: 17, by_user: 'admin', plan_id: 'plan', old_end_date: '2026-10-01' });
  expect(events()[0].id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test.each([17, 0, -3, null])('resume restores %s preserved days, clears all freeze metadata, and records the new date', async (days) => {
  mockDatabase.prepare("UPDATE memberships SET is_frozen = 1, days_left_when_frozen = ?, frozen_at = '2026-09-10', frozen_by_user_id = 'admin', freeze_type = 'auto_5_days', auto_unfreeze_at = '2026-09-15'").run(days);
  await applyFreezeAction('client', { kind: 'resume', membershipId: 'membership' });
  expect(membership()).toMatchObject({ is_frozen: 0, days_left: Math.max(days ?? 0, 0), days_left_when_frozen: null,
    frozen_at: null, frozen_by_user_id: null, freeze_type: null, auto_unfreeze_at: null,
    end_date: days === 17 ? '2026-10-01' : '2026-09-14' });
  expect(events()[0]).toMatchObject({ event_type: 'resumed', new_end_date: days === 17 ? '2026-10-01' : '2026-09-14', old_end_date: '2026-10-01' });
});

test('a negative current balance freezes as zero, not a recalculation from end_date', async () => {
  mockDatabase.exec('UPDATE memberships SET days_left = -2');
  await applyFreezeAction('client', { kind: 'freeze', membershipId: 'membership', mode: 'manual' });
  expect(membership().days_left_when_frozen).toBe(0);
});

test('scheduling leaves the membership unchanged and can be canceled', async () => {
  const before = membership();
  await applyFreezeAction('client', { kind: 'schedule', membershipId: 'membership', durationDays: 14, start: '2026-10-01' });
  expect(membership()).toEqual(before);
  const data = await getFreezeData('client');
  expect(data.schedules[0]).toMatchObject({ status: 'pending', scheduled_start_date: '2026-10-01', duration_days: 14 });
  await expect(applyFreezeAction('client', { kind: 'freeze', membershipId: 'membership', mode: 'manual' })).rejects.toThrow('Anulați întâi');
  await expect(applyFreezeAction('client', { kind: 'schedule', membershipId: 'membership', durationDays: 5, start: '2026-09-20' })).rejects.toThrow('Există deja');
  await applyFreezeAction('client', { kind: 'cancel', membershipId: 'membership', scheduleId: data.schedules[0].id });
  expect((await getFreezeData('client')).schedules).toEqual([]);
  expect(mockDatabase.prepare('SELECT * FROM membership_freeze_schedules').get()).toMatchObject({ status: 'canceled', canceled_by_user_id: 'admin' });
  expect(events()).toEqual([]);
});

test.each(['2026-09-14', '2026-09-13', '2026-10-02'])('rejects schedule date %s outside tomorrow–expiry', async (start) => {
  await expect(applyFreezeAction('client', { kind: 'schedule', membershipId: 'membership', durationDays: 5, start })).rejects.toThrow();
  expect(mockDatabase.prepare('SELECT * FROM membership_freeze_schedules').all()).toEqual([]);
});

test('membership duration takes priority over plan duration for 14-day eligibility', async () => {
  mockDatabase.exec('UPDATE memberships SET duration_months = 1');
  await expect(applyFreezeAction('client', { kind: 'freeze', membershipId: 'membership', mode: 'auto_14_days' })).rejects.toThrow('3 luni');
  mockDatabase.exec('UPDATE memberships SET duration_months = NULL');
  await applyFreezeAction('client', { kind: 'freeze', membershipId: 'membership', mode: 'auto_14_days' });
  expect(membership().is_frozen).toBe(1);
});

test.each(["is_active = 0", "canceled_at = '2026-09-14'", 'is_frozen = 1'])('rejects ineligible membership: %s', async (update) => {
  mockDatabase.exec(`UPDATE memberships SET ${update}`);
  await expect(applyFreezeAction('client', { kind: 'freeze', membershipId: 'membership', mode: 'manual' })).rejects.toThrow();
  expect(events()).toEqual([]);
});

test('family dependants cannot modify the owner membership', async () => {
  expect((await getFreezeData('dependant')).memberships).toEqual([]);
  await expect(applyFreezeAction('dependant', { kind: 'freeze', membershipId: 'membership', mode: 'manual' })).rejects.toThrow('nu aparține');
});

test('a failed event insert rolls back the freeze; retry creates one complete change', async () => {
  mockDatabase.exec("CREATE TRIGGER fail_event BEFORE INSERT ON membership_events BEGIN SELECT RAISE(ABORT, 'event failed'); END");
  await expect(applyFreezeAction('client', { kind: 'freeze', membershipId: 'membership', mode: 'manual' })).rejects.toThrow('event failed');
  expect(membership().is_frozen).toBe(0);
  mockDatabase.exec('DROP TRIGGER fail_event');
  await applyFreezeAction('client', { kind: 'freeze', membershipId: 'membership', mode: 'manual' });
  expect(membership().is_frozen).toBe(1);
  expect(events()).toHaveLength(1);
});

test('resume keeps the employee elapsed-duration behavior across the autumn clock change', () => {
  const now = new Date(2026, 9, 25);
  // The Romanian fall-back day is 25 hours long: Dart Duration(days: 1)
  // reaches 23:00 on the same civil date. UTC/US zones reach the next date.
  const romanianFallBack = now.getTimezoneOffset() === -180 && new Date(2026, 9, 26).getTimezoneOffset() === -120;
  expect(resumedEndDate(1, now)).toBe(romanianFallBack ? '2026-10-25' : '2026-10-26');
});
