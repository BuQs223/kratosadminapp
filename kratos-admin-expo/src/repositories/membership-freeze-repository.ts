import type { Transaction } from '@powersync/react-native';

import { connectPowerSyncIfAuthenticated, powerSync } from '@/lib/powersync/system';
import { getSupabase } from '@/lib/supabase/client';
import { type CalendarDate, calendarDateFromLocalDate, calendarDateToLocalDate, todayCalendarDate } from '@/utils/calendar-date';
import { elapsedDays, flutterCalendarDate, flutterDateTimeIso, localMidnight, parseFlutterDate } from '@/utils/flutter-date';

export type FreezeMode = 'manual' | 'auto_5_days' | 'auto_14_days';
export interface FreezeMembership {
  id: string;
  user_id: string;
  plan_id: string;
  plan_name: string;
  duration_months: number | null;
  plan_duration_months: number | null;
  is_active: number;
  is_frozen: number;
  canceled_at: string | null;
  start_date: string;
  end_date: string;
  days_left: number | null;
  days_left_when_frozen: number | null;
  freeze_type: string | null;
  auto_unfreeze_at: string | null;
}
export interface FreezeSchedule {
  id: string;
  membership_id: string;
  scheduled_start_date: CalendarDate;
  duration_days: number;
  status: string;
}
export interface FreezeData { memberships: FreezeMembership[]; schedules: FreezeSchedule[] }
export type FreezeAction =
  | { kind: 'freeze'; membershipId: string; mode: FreezeMode }
  | { kind: 'resume'; membershipId: string }
  | { kind: 'schedule'; membershipId: string; durationDays: 5 | 14; start: CalendarDate }
  | { kind: 'cancel'; membershipId: string; scheduleId: string };

const membershipSelect = `SELECT m.*, mp.name AS plan_name, mp.duration_months AS plan_duration_months
  FROM memberships m LEFT JOIN membership_plans mp ON mp.id = m.plan_id`;
// SQLite supplies UUIDs without adding a native dependency to the installed client.
const uuidSql = `SELECT lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' ||
  substr(hex(randomblob(2)), 2) || '-a' || substr(hex(randomblob(2)), 2) || '-' || hex(randomblob(6))) AS id`;

export const isThreeMonthMembership = (membership: FreezeMembership) =>
  (membership.duration_months ?? membership.plan_duration_months ?? 0) === 3;
export const canFreezeMembership = (membership: FreezeMembership) =>
  Boolean(membership.is_active) && !membership.is_frozen && !membership.canceled_at;
export const employeeTimestamp = (date: Date) => flutterDateTimeIso(date).slice(0, 19).replace('T', ' ');
export const preservedDays = (days: number | null) => Math.max(days ?? 0, 0);
export const resumedEndDate = (days: number | null, now = new Date()) =>
  calendarDateFromLocalDate(elapsedDays(localMidnight(now), preservedDays(days)));
export const scheduleMaximum = (membership: FreezeMembership) => flutterCalendarDate(parseFlutterDate(membership.end_date));

export async function getFreezeData(memberId: string): Promise<FreezeData> {
  await connectPowerSyncIfAuthenticated();
  const [memberships, schedules] = await Promise.all([
    powerSync.getAll<FreezeMembership>(`${membershipSelect} WHERE m.user_id = ? ORDER BY m.end_date DESC`, [memberId]),
    getMemberFreezeSchedules(memberId),
  ]);
  return { memberships, schedules };
}

export async function getMemberFreezeSchedules(memberId: string): Promise<FreezeSchedule[]> {
  await connectPowerSyncIfAuthenticated();
  return powerSync.getAll<FreezeSchedule>(`SELECT DISTINCT s.* FROM membership_freeze_schedules s
    JOIN memberships m ON m.id = s.membership_id
    LEFT JOIN family_memberships fm ON fm.membership_id = m.id
    WHERE (m.user_id = ? OR fm.user_id = ?) AND s.status = 'pending'
    ORDER BY s.scheduled_start_date, s.created_at`, [memberId, memberId]);
}

export function validateSchedule(membership: FreezeMembership, start: CalendarDate, duration: number, now = new Date()) {
  if (duration !== 5 && duration !== 14) throw new Error('Durata înghețării trebuie să fie 5 sau 14 zile');
  // Validate the civil date without interpreting it as a UTC instant.
  calendarDateToLocalDate(start);
  if (start <= todayCalendarDate(now)) throw new Error('Alegeți o dată viitoare pentru înghețare');
  if (!canFreezeMembership(membership)) throw new Error('Doar abonamentele active, neînghețate pot fi programate');
  if (start > scheduleMaximum(membership)) throw new Error('Data de start nu poate fi după data de expirare a abonamentului');
  if (duration === 14 && !isThreeMonthMembership(membership)) throw new Error('Înghețarea de 14 zile este disponibilă doar pentru abonamente de 3 luni');
}

async function insertEvent(tx: Transaction, membership: FreezeMembership, userId: string, name: string, now: Date, mode?: FreezeMode) {
  const { id } = await tx.get<{ id: string }>(uuidSql);
  const days = preservedDays(mode ? membership.days_left : membership.days_left_when_frozen);
  const autoDays = mode === 'auto_5_days' ? 5 : mode === 'auto_14_days' ? 14 : null;
  const notes = mode
    ? autoDays ? `Abonament înghețat pentru ${autoDays} zile de ${name} (${days} zile rămase)` : `Abonament înghețat manual de ${name} (${days} zile rămase)`
    : `Abonament dezghețat de ${name}`;
  await tx.execute(`INSERT INTO membership_events
    (id, membership_id, event_type, at, notes, delta_days, by_user, old_start_date, old_end_date, new_end_date, plan_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  [id, membership.id, mode ? 'paused' : 'resumed', employeeTimestamp(now), notes, days, userId,
    membership.start_date, membership.end_date, mode ? null : resumedEndDate(days, now), membership.plan_id]);
}

export async function applyFreezeAction(memberId: string, action: FreezeAction): Promise<void> {
  await connectPowerSyncIfAuthenticated();
  const { data, error } = await getSupabase().auth.getSession();
  if (error) throw error;
  const userId = data.session?.user.id;
  if (!userId) throw new Error('Autentificați-vă din nou pentru a modifica abonamentul');

  // Read eligibility and save membership + history under one local write lock.
  // PowerSync uploads the committed changes with the same mappings as the employee app.
  await powerSync.writeTransaction(async (tx) => {
    const membership = await tx.getOptional<FreezeMembership>(`${membershipSelect} WHERE m.id = ? AND m.user_id = ?`, [action.membershipId, memberId]);
    if (!membership) throw new Error('Abonamentul nu aparține acestui client');
    const pending = await tx.getOptional<FreezeSchedule>(`SELECT * FROM membership_freeze_schedules WHERE membership_id = ? AND status = 'pending' LIMIT 1`, [membership.id]);
    const now = new Date();
    const at = employeeTimestamp(now);
    if (action.kind === 'cancel') {
      if (!pending || pending.id !== action.scheduleId) throw new Error('Înghețarea programată nu mai este în așteptare');
      await tx.execute(`UPDATE membership_freeze_schedules SET status = 'canceled', canceled_at = ?, canceled_by_user_id = ?, notes = ?, updated_at = ? WHERE id = ? AND status = 'pending'`,
        [at, userId, 'Înghețare programată anulată', at, pending.id]);
      return;
    }
    if (action.kind === 'schedule') {
      validateSchedule(membership, action.start, action.durationDays, now);
      if (pending) throw new Error('Există deja o înghețare programată');
      const { id } = await tx.get<{ id: string }>(uuidSql);
      await tx.execute(`INSERT INTO membership_freeze_schedules
        (id, membership_id, duration_days, freeze_type, scheduled_start_date, status, created_by_user_id, notes, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?)`,
      [id, membership.id, action.durationDays, action.durationDays === 14 ? 'auto_14_days' : 'auto_5_days', action.start, userId,
        `Înghețare programată pentru ${action.durationDays} zile, start ${action.start}`, at, at]);
      return;
    }
    const actor = await tx.getOptional<{ full_name: string | null }>('SELECT full_name FROM profiles WHERE id = ?', [userId]);
    if (action.kind === 'freeze') {
      if (!canFreezeMembership(membership)) throw new Error('Doar abonamentele active, neînghețate pot fi înghețate');
      if (pending) throw new Error('Anulați întâi înghețarea programată');
      if (!['manual', 'auto_5_days', 'auto_14_days'].includes(action.mode)) throw new Error('Tip de înghețare invalid');
      if (action.mode === 'auto_14_days' && !isThreeMonthMembership(membership)) throw new Error('Înghețarea de 14 zile este disponibilă doar pentru abonamente de 3 luni');
      const days = action.mode === 'auto_5_days' ? 5 : action.mode === 'auto_14_days' ? 14 : null;
      await tx.execute(`UPDATE memberships SET is_frozen = 1, frozen_at = ?, frozen_by_user_id = ?, days_left_when_frozen = ?, freeze_type = ?, auto_unfreeze_at = ?, updated_at = ? WHERE id = ?`,
        [at, userId, preservedDays(membership.days_left), action.mode, days ? employeeTimestamp(elapsedDays(now, days)) : null, at, membership.id]);
      await insertEvent(tx, membership, userId, actor?.full_name ?? 'Angajat', now, action.mode);
    } else {
      if (!membership.is_frozen) throw new Error('Abonamentul nu mai este înghețat');
      const days = preservedDays(membership.days_left_when_frozen);
      await tx.execute(`UPDATE memberships SET is_frozen = 0, frozen_at = NULL, frozen_by_user_id = NULL,
        end_date = ?, days_left = ?, days_left_when_frozen = NULL, freeze_type = NULL, auto_unfreeze_at = NULL, updated_at = ? WHERE id = ?`,
      [resumedEndDate(days, now), days, at, membership.id]);
      await insertEvent(tx, membership, userId, actor?.full_name ?? 'Angajat', now);
    }
  });
}
