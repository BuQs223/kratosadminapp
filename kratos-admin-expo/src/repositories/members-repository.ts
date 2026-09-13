import { connectPowerSyncIfAuthenticated, powerSync } from '@/lib/powersync/system';
import { getSupabase } from '@/lib/supabase/client';
import { parseCheckIn, type CheckIn } from '@/models/check-in';
import { parseGym, type Gym } from '@/models/gym';
import { parseMembershipEvent, type MembershipEvent } from '@/models/membership-event';
import { parseMembershipPlan, type MembershipPlan } from '@/models/membership-plan';
import { parseOptimizedMembership, type Membership } from '@/models/membership';
import { parseProfile, type Profile } from '@/models/profile';
import { parseRevenueLedger, type RevenueLedger } from '@/models/revenue-ledger';
import {
  asBoolean,
  asInteger,
  asNullableDate,
  asNullableString,
  asRecord,
  flutterNullableTruncatedNumber,
  asRecords,
} from '@/utils/parsing';
import { type CalendarDate } from '@/utils/calendar-date';
import { flutterDateTimeIso, reportStart, reportEnd, sqliteFlutterRange } from '@/utils/flutter-date';

type SqlValue = string | number | null;

export type MembershipStatusFilter =
  | 'all'
  | 'active'
  | 'expiring'
  | 'expired'
  | 'inactive'
  | 'canceled';
export type FrozenStatusFilter = 'all' | 'frozen' | 'not_frozen';

export interface MemberFilters {
  search?: string;
  gymId?: string;
  planId?: string;
  membershipStatus?: MembershipStatusFilter;
  frozenStatus?: FrozenStatusFilter;
  expiringInDays?: number;
  registrationStart?: CalendarDate;
  registrationEnd?: CalendarDate;
  checkInStart?: CalendarDate;
  checkInEnd?: CalendarDate;
}

export interface MemberWithDetails {
  profile: Profile;
  membershipStatus: string;
  membershipPlan: string | null;
  lastCheckIn: Date | null;
  lastCheckInGym: string | null;
  membershipExpiry: Date | null;
  daysLeft: number | null;
  canceledAt: Date | null;
}

const membersBaseCte = `
  WITH latest_membership AS (
    SELECT m.*,
      ROW_NUMBER() OVER (
        PARTITION BY m.user_id
        ORDER BY m.end_date DESC, m.created_at DESC
      ) AS rn
    FROM memberships m
  ),
  member_rows AS (
    SELECT
      p.id, p.full_name, p.email, p.phone, p.created_at, p.is_admin, p.is_employee,
      m.id AS membership_id, m.end_date AS membership_end_date,
      m.canceled_at AS membership_canceled_at,
      COALESCE(
        m.days_left,
        CAST(julianday(m.end_date) - julianday('now', 'localtime') AS INTEGER)
      ) AS membership_days_left,
      mp.name AS membership_plan_name, m.sold_at_gym_id, m.plan_id, m.is_frozen, m.is_active,
      m.start_date, m.effective_start_date
    FROM profiles p
    LEFT JOIN latest_membership m ON m.user_id = p.id AND m.rn = 1
    LEFT JOIN membership_plans mp ON mp.id = m.plan_id
  )
`;

function buildMembersWhere(filters: MemberFilters): { where: string; params: SqlValue[] } {
  const clauses: string[] = [];
  const params: SqlValue[] = [];
  const daysLeft =
    "COALESCE(m.days_left, CAST(julianday(m.end_date) - julianday('now', 'localtime') AS INTEGER))";
  const search = filters.search?.trim().toLowerCase();

  if (search) {
    const like = `%${search}%`;
    clauses.push(`(
      LOWER(COALESCE(p.full_name, '')) LIKE ?
      OR LOWER(COALESCE(p.phone, '')) LIKE ?
      OR LOWER(COALESCE(p.email, '')) LIKE ?
      OR LOWER(p.id) LIKE ?
    )`);
    params.push(like, like, like, like);
  }
  if (filters.gymId) {
    clauses.push('m.sold_at_gym_id = ?');
    params.push(filters.gymId);
  }
  if (filters.planId) {
    clauses.push('m.plan_id = ?');
    params.push(filters.planId);
  }

  switch (filters.membershipStatus ?? 'all') {
    case 'active':
      clauses.push(`m.id IS NOT NULL AND ${daysLeft} > 7`);
      break;
    case 'expiring':
      clauses.push(`m.id IS NOT NULL AND ${daysLeft} BETWEEN 0 AND 7`);
      break;
    case 'expired':
      clauses.push(`m.id IS NOT NULL AND ${daysLeft} < 0`);
      break;
    case 'inactive':
      clauses.push('m.id IS NULL');
      break;
    // Flutter exposes this option but does not add a canceled predicate.
    case 'canceled':
      break;
  }

  if (filters.frozenStatus === 'frozen') clauses.push('COALESCE(m.is_frozen, 0) = 1');
  if (filters.frozenStatus === 'not_frozen') {
    clauses.push('(m.id IS NULL OR COALESCE(m.is_frozen, 0) = 0)');
  }
  if (filters.expiringInDays !== undefined) {
    clauses.push(`m.id IS NOT NULL AND ${daysLeft} = ?`);
    params.push(filters.expiringInDays);
  }
  if (filters.registrationStart && filters.registrationEnd) {
    clauses.push(sqliteFlutterRange('p.created_at'));
    params.push(reportStart(filters.registrationStart), reportEnd(filters.registrationEnd));
  }
  if (filters.checkInStart && filters.checkInEnd) {
    clauses.push(`EXISTS (
      SELECT 1 FROM check_ins c
      WHERE c.user_id = p.id
        AND ${sqliteFlutterRange('c.created_at')}
    )`);
    params.push(reportStart(filters.checkInStart), reportEnd(filters.checkInEnd));
  }
  return { where: clauses.length ? `WHERE ${clauses.join(' AND ')}` : '', params };
}

function membershipStatus(hasMembership: boolean, daysLeft: number | null, canceledAt: Date | null) {
  if (!hasMembership) return 'Niciun abonament';
  if (canceledAt) return 'Anulat';
  if (daysLeft === null) return 'Activ';
  if (daysLeft < 0) return 'Expirat';
  if (daysLeft <= 7) return 'Expiră în curând';
  return 'Activ';
}

function parseMemberRow(value: unknown): MemberWithDetails {
  const row = asRecord(value);
  const daysLeft = flutterNullableTruncatedNumber(row.membership_days_left);
  const canceledAt = asNullableDate(row.membership_canceled_at);
  return {
    profile: parseProfile({
      id: row.id,
      full_name: row.full_name,
      email: row.email,
      phone: row.phone,
      created_at: row.created_at,
      is_admin: asBoolean(row.is_admin),
      is_employee: asBoolean(row.is_employee),
      role: 'client',
    }),
    membershipStatus: membershipStatus(Boolean(row.membership_id), daysLeft, canceledAt),
    membershipPlan: asNullableString(row.membership_plan_name),
    lastCheckIn: asNullableDate(row.last_checkin_date),
    lastCheckInGym: asNullableString(row.last_checkin_gym_name),
    membershipExpiry: asNullableDate(row.membership_end_date),
    daysLeft,
    canceledAt,
  };
}

export async function getMemberProfile(memberId: string): Promise<Profile> {
  await connectPowerSyncIfAuthenticated();
  const row = await powerSync.getOptional(
    `SELECT id, full_name, email, phone, NULL AS avatar_url, 'client' AS role,
            is_admin, is_employee,
            created_at, updated_at
     FROM profiles
     WHERE id = ?
     LIMIT 1`,
    [memberId],
  );
  if (!row) throw new Error('Membrul nu a fost găsit.');
  return parseProfile(row);
}

export async function getMembersPage({
  filters = {},
  limit = 20,
  offset = 0,
}: {
  filters?: MemberFilters;
  limit?: number;
  offset?: number;
}) {
  await connectPowerSyncIfAuthenticated();
  const { where, params } = buildMembersWhere(filters);
  const countRow = await powerSync.get(
    `${membersBaseCte}
     SELECT COUNT(*) AS total_count
     FROM member_rows p
     LEFT JOIN memberships m ON m.id = p.membership_id
     ${where}`,
    params,
  );
  const rows = await powerSync.getAll(
    `${membersBaseCte},
     page AS (
       SELECT p.*
       FROM member_rows p
       LEFT JOIN memberships m ON m.id = p.membership_id
       ${where}
       ORDER BY CASE WHEN p.membership_id IS NULL THEN 1 ELSE 0 END,
                LOWER(COALESCE(p.full_name, ''))
       LIMIT ? OFFSET ?
     )
     SELECT page.*,
       (SELECT c.created_at FROM check_ins c WHERE c.user_id = page.id
        ORDER BY c.created_at DESC LIMIT 1) AS last_checkin_date,
       (SELECT g.name FROM check_ins c LEFT JOIN gyms g ON g.id = c.gym_id
        WHERE c.user_id = page.id ORDER BY c.created_at DESC LIMIT 1) AS last_checkin_gym_name
     FROM page`,
    [...params, limit, offset],
  );
  const items = asRecords(rows).map(parseMemberRow);
  const totalCount = asInteger(asRecord(countRow).total_count);
  return { items, totalCount, hasMore: offset + items.length < totalCount };
}

const userMembershipsSql = `
  WITH user_membership_ids AS (
    SELECT DISTINCT m.id AS membership_id
    FROM memberships m
    LEFT JOIN family_memberships fm ON fm.membership_id = m.id
    WHERE m.user_id = ? OR fm.user_id = ?
  )
  SELECT
    m.id AS membership_id, m.user_id, m.plan_id AS membership_plan_id,
    mp.name AS plan_name, mp.plan_kind, mp.tier, m.membership_type,
    m.is_student, m.start_date,
    COALESCE(m.effective_start_date, m.start_date) AS effective_start_date,
    m.end_date, m.duration_months, m.duration_days, m.is_active,
    COALESCE(
      m.days_left,
      CAST(julianday(m.end_date) - julianday('now', 'localtime') AS INTEGER)
    ) AS days_left,
    m.canceled_at, m.price_paid_cents, m.currency, m.payment_method,
    m.cancel_reason, COALESCE(mp.is_family_plan, 0) AS is_family_plan,
    mp.max_family_members, COALESCE(m.is_frozen, 0) AS is_frozen,
    m.frozen_at, m.days_left_when_frozen, m.sold_at_gym_id,
    m.freeze_type, m.auto_unfreeze_at,
    g.name AS sold_at_gym_name
  FROM memberships m
  JOIN user_membership_ids umi ON umi.membership_id = m.id
  JOIN membership_plans mp ON mp.id = m.plan_id
  LEFT JOIN gyms g ON g.id = m.sold_at_gym_id
  ORDER BY
    CASE
      WHEN m.canceled_at IS NOT NULL THEN 3
      WHEN COALESCE(
        m.days_left,
        CAST(julianday(m.end_date) - julianday('now', 'localtime') AS INTEGER)
      ) < 0 THEN 2
      ELSE 1
    END,
    m.end_date DESC
`;

export async function getMemberMemberships(memberId: string): Promise<Membership[]> {
  await connectPowerSyncIfAuthenticated();
  return asRecords(await powerSync.getAll(userMembershipsSql, [memberId, memberId])).map(
    parseOptimizedMembership,
  );
}

export async function getMemberCheckIns(member: Profile): Promise<CheckIn[]> {
  await connectPowerSyncIfAuthenticated();
  const rows = await powerSync.getAll(
    `SELECT c.id, c.user_id, c.gym_id, c.membership_id, c.status, c.message,
            c.days_left, c.shown_to_user, c.method, c.created_at,
            g.name AS gym_name, g.created_at AS gym_created_at
     FROM check_ins c
     LEFT JOIN gyms g ON g.id = c.gym_id
     WHERE c.user_id = ?
     ORDER BY c.created_at DESC
     LIMIT 50`,
    [member.id],
  );
  return asRecords(rows).flatMap((row) => {
    try {
      return [
        parseCheckIn({
          ...row,
          days_left: flutterNullableTruncatedNumber(row.days_left),
          profiles: { id: member.id, full_name: member.fullName },
          gyms: row.gym_name != null
            ? { id: row.gym_id, name: row.gym_name, created_at: row.gym_created_at }
            : null,
        }),
      ];
    } catch (error) {
      console.warn('Skipping malformed member check-in', error);
      return [];
    }
  });
}

export async function getMemberHistory(memberId: string): Promise<MembershipEvent[]> {
  await connectPowerSyncIfAuthenticated();
  const rows = await powerSync.getAll(
    `SELECT
       me.id, me.membership_id, me.event_type, me.at, me.by_user,
       p.full_name AS by_user_name, me.notes, me.delta_days, me.delta_cents,
       me.old_start_date, me.old_end_date, me.new_start_date, me.new_end_date,
       mp.name AS plan_name
     FROM membership_events me
     JOIN memberships m ON m.id = me.membership_id
     JOIN membership_plans mp ON mp.id = m.plan_id
     LEFT JOIN profiles p ON p.id = me.by_user
     WHERE m.user_id = ? OR me.membership_id IN (
       SELECT fm.membership_id FROM family_memberships fm WHERE fm.user_id = ?
     )
     ORDER BY datetime(me.at) DESC`,
    [memberId, memberId],
  );
  return asRecords(rows).map(parseMembershipEvent);
}

export async function getMemberRevenueHistory(member: Profile): Promise<RevenueLedger[]> {
  await connectPowerSyncIfAuthenticated();
  const rows = await powerSync.getAll(
    `WITH user_membership_ids AS (
       SELECT DISTINCT m.id AS membership_id
       FROM memberships m
       LEFT JOIN family_memberships fm ON fm.membership_id = m.id
       WHERE m.user_id = ? OR fm.user_id = ?
     )
     SELECT
       r.id, r.paid_at, r.plan_id, r.membership_id, r.gym_id, r.amount_cents,
       r.currency, r.source, r.notes, r.created_at, r.entry_kind,
       r.payment_method, r.recorded_by, r.is_deleted, r.deleted_at,
       r.deleted_by, r.client_user_id, r.client_full_name,
       COALESCE(r.client_user_id, p_client.id) AS profile_id,
       COALESCE(r.client_full_name, p_client.full_name) AS profile_full_name,
       g.name AS gym_name, mp.name AS plan_name,
       p_recorded.full_name AS recorded_by_full_name,
       p_deleted.full_name AS deleted_by_full_name
     FROM revenue_ledger r
     LEFT JOIN profiles p_client ON p_client.id = r.client_user_id
     LEFT JOIN gyms g ON g.id = r.gym_id
     LEFT JOIN membership_plans mp ON mp.id = r.plan_id
     LEFT JOIN profiles p_recorded ON p_recorded.id = r.recorded_by
     LEFT JOIN profiles p_deleted ON p_deleted.id = r.deleted_by
     WHERE r.client_user_id = ?
       OR r.membership_id IN (SELECT membership_id FROM user_membership_ids)
     ORDER BY datetime(r.paid_at) DESC`,
    [member.id, member.id, member.id],
  );
  return asRecords(rows).map((row) =>
    parseRevenueLedger({
      ...row,
      created_at: row.created_at ?? row.paid_at,
      currency: row.currency ?? 'RON',
      source: row.source ?? 'membership',
      entry_kind: row.entry_kind ?? 'charge',
      payment_method: row.payment_method ?? 'cash',
      profile: {
        id: row.profile_id ?? row.client_user_id ?? member.id,
        full_name: row.profile_full_name ?? row.client_full_name ?? member.fullName,
      },
      gym: row.gym_id != null && row.gym_name != null ? { id: row.gym_id, name: row.gym_name } : null,
      membership_plan:
        row.plan_id != null && row.plan_name != null ? { id: row.plan_id, name: row.plan_name } : null,
      recorded_by_profile:
        row.recorded_by != null && row.recorded_by_full_name != null
          ? { id: row.recorded_by, full_name: row.recorded_by_full_name }
          : null,
      deleted_by_profile:
        row.deleted_by != null && row.deleted_by_full_name != null
          ? { id: row.deleted_by, full_name: row.deleted_by_full_name }
          : null,
    }),
  );
}

export async function updateMemberName(memberId: string, fullName: string) {
  const { error } = await getSupabase().from('profiles').update({ full_name: fullName }).eq('id', memberId);
  if (error) throw error;
}

export async function deleteMembership(membershipId: string): Promise<void> {
  const supabase = getSupabase();
  for (const table of ['revenue_ledger', 'check_ins', 'memberships']) {
    const { error } = await supabase.from(table).delete().eq(table === 'memberships' ? 'id' : 'membership_id', membershipId);
    if (error) throw error;
  }
}

export async function getMembershipFormOptions(): Promise<{
  plans: MembershipPlan[];
  gyms: Gym[];
}> {
  const supabase = getSupabase();
  const [plansResult, gymsResult] = await Promise.all([
    supabase.from('membership_plans').select().order('name'),
    supabase.from('gyms').select().order('name'),
  ]);
  if (plansResult.error) throw plansResult.error;
  if (gymsResult.error) throw gymsResult.error;
  return {
    plans: asRecords(plansResult.data).map(parseMembershipPlan),
    gyms: asRecords(gymsResult.data).map(parseGym),
  };
}

export interface SaveMembershipInput {
  memberId: string;
  membershipId?: string;
  planId: string;
  gymId: string;
  startDate: Date;
  endDate: Date;
  originalPricePaidCents?: number;
  isActive: boolean;
  membershipType: string;
  pricePaidCents: number;
  paymentMethod: string;
}

export async function saveMembership(input: SaveMembershipInput): Promise<string> {
  const supabase = getSupabase();
  const payload = {
    user_id: input.memberId, plan_id: input.planId, sold_at_gym_id: input.gymId,
    start_date: flutterDateTimeIso(input.startDate), end_date: flutterDateTimeIso(input.endDate),
    is_active: input.isActive, membership_type: input.membershipType,
    price_paid_cents: input.pricePaidCents, payment_method: input.paymentMethod,
  };
  let membershipId = input.membershipId;
  if (membershipId) {
    const { error } = await supabase.from('memberships').update(payload).eq('id', membershipId);
    if (error) throw error;
    // Flutter only touches the ledger when the price changes, even if plan/gym/payment changed.
    if (input.pricePaidCents === input.originalPricePaidCents) return membershipId;
    const existing = await supabase.from('revenue_ledger').select('id').eq('membership_id', membershipId).maybeSingle();
    if (existing.error) throw existing.error;
    if (existing.data) {
      const { error } = await supabase.from('revenue_ledger').update({
        amount_cents: input.pricePaidCents, payment_method: input.paymentMethod, gym_id: input.gymId,
      }).eq('id', existing.data.id);
      if (error) throw error;
      return membershipId;
    }
  } else {
    const result = await supabase.from('memberships').insert(payload).select('id').single();
    if (result.error) throw result.error;
    membershipId = result.data.id as string;
  }
  const { data: sessionData } = await supabase.auth.getSession();
  const { error } = await supabase.from('revenue_ledger').insert({
    membership_id: membershipId, plan_id: input.planId, gym_id: input.gymId,
    amount_cents: input.pricePaidCents, currency: 'RON', source: 'membership', entry_kind: 'charge',
    payment_method: input.paymentMethod, recorded_by: sessionData.session?.user.id ?? null,
  });
  if (error) throw error;
  return membershipId;
}
