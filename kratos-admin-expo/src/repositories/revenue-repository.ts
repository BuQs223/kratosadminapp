import { connectPowerSyncIfAuthenticated, powerSync } from '@/lib/powersync/system';
import { getSupabase } from '@/lib/supabase/client';
import { parseRevenueLedger, type RevenueLedger } from '@/models/revenue-ledger';
import {
  revenueAmountFilterClause,
  type AmountFilter,
} from '@/repositories/revenue-amount-filter';
import {
  asInteger,
  asNumber,
  asRecord,
  asRecords,
  type JsonRecord,
} from '@/utils/parsing';
import {
  addCalendarDays,
  calendarDateFromLocalDate,
  sqliteCalendarDateRangePredicate,
  sqliteLocalCalendarDate,
  type CalendarDate,
} from '@/utils/calendar-date';

type SqlValue = string | number | null;
export type PaymentMethodFilter = 'all' | 'cash' | 'card';
export type DeletedStatusFilter = 'all' | 'active' | 'deleted';
export type { AmountFilter } from '@/repositories/revenue-amount-filter';

export interface RevenueFilters {
  gymId?: string;
  paymentMethod?: PaymentMethodFilter;
  planId?: string;
  amount?: AmountFilter;
  deletedStatus?: DeletedStatusFilter;
  dateStart?: CalendarDate;
  dateEnd?: CalendarDate;
  search?: string;
}

export interface RevenuePage {
  items: RevenueLedger[];
  rows: JsonRecord[];
  totalCount: number;
  totalRevenueCents: number;
  cashRevenueCents: number;
  cardRevenueCents: number;
  hasMore: boolean;
}

function escapeLike(input: string): string {
  return input.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
}

function buildRevenueWhere(filters: RevenueFilters): { where: string; params: SqlValue[] } {
  const clauses = ["r.entry_kind = 'charge'"];
  const params: SqlValue[] = [];
  if (filters.deletedStatus === 'deleted') clauses.push('COALESCE(r.is_deleted, 0) = 1');
  else clauses.push('COALESCE(r.is_deleted, 0) = 0');
  if (filters.gymId) {
    clauses.push('r.gym_id = ?');
    params.push(filters.gymId);
  }
  if (filters.paymentMethod && filters.paymentMethod !== 'all') {
    clauses.push('r.payment_method = ?');
    params.push(filters.paymentMethod);
  }
  if (filters.planId) {
    clauses.push('r.plan_id = ?');
    params.push(filters.planId);
  }
  const amountClause = revenueAmountFilterClause(filters.amount);
  if (amountClause) clauses.push(amountClause);
  if (filters.dateStart) {
    clauses.push(`${sqliteLocalCalendarDate('r.paid_at')} >= date(?)`);
    params.push(filters.dateStart);
  }
  if (filters.dateEnd) {
    clauses.push(`${sqliteLocalCalendarDate('r.paid_at')} <= date(?)`);
    params.push(filters.dateEnd);
  }

  const search = filters.search?.trim().toLowerCase();
  if (search) {
    const like = `%${escapeLike(search)}%`;
    clauses.push(`(
      LOWER(COALESCE(r.notes, '')) LIKE ? ESCAPE '\\'
      OR LOWER(COALESCE(r.client_full_name, '')) LIKE ? ESCAPE '\\'
      OR LOWER(COALESCE(p_client.full_name, '')) LIKE ? ESCAPE '\\'
      OR LOWER(COALESCE(r.source, '')) LIKE ? ESCAPE '\\'
      OR CAST(COALESCE(r.amount_cents, 0) / 100.0 AS TEXT) LIKE ? ESCAPE '\\'
    )`);
    params.push(like, like, like, like, like);
  }
  return { where: `WHERE ${clauses.join(' AND ')}`, params };
}

function revenueRowsSql(where: string) {
  return `SELECT
    r.id, r.paid_at, r.plan_id, r.membership_id, r.gym_id, r.amount_cents,
    r.currency, r.source, r.notes, r.created_at, r.entry_kind,
    r.payment_method, r.idempotency_key, r.recorded_by, r.is_deleted,
    r.deleted_at, r.deleted_by, r.client_user_id, r.client_full_name,
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
   ${where}
   ORDER BY datetime(r.paid_at) DESC
   LIMIT ? OFFSET ?`;
}

function parseRevenueRow(row: JsonRecord): RevenueLedger {
  return parseRevenueLedger({
    ...row,
    profile: row.profile_id
      ? { id: row.profile_id, full_name: row.profile_full_name ?? 'Necunoscut' }
      : null,
    gym: row.gym_id && row.gym_name ? { id: row.gym_id, name: row.gym_name } : null,
    membership_plan:
      row.plan_id && row.plan_name ? { id: row.plan_id, name: row.plan_name } : null,
    recorded_by_profile:
      row.recorded_by && row.recorded_by_full_name
        ? { id: row.recorded_by, full_name: row.recorded_by_full_name }
        : null,
    deleted_by_profile:
      row.deleted_by && row.deleted_by_full_name
        ? { id: row.deleted_by, full_name: row.deleted_by_full_name }
        : null,
  });
}

export async function getRevenuePage({
  filters = {},
  limit = 20,
  offset = 0,
}: {
  filters?: RevenueFilters;
  limit?: number;
  offset?: number;
}): Promise<RevenuePage> {
  await connectPowerSyncIfAuthenticated();
  const { where, params } = buildRevenueWhere(filters);
  const [stats, data] = await Promise.all([
    powerSync.get(
      `SELECT COUNT(*) AS total_count,
        COALESCE(SUM(r.amount_cents), 0) AS total_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'cash'
          THEN r.amount_cents ELSE 0 END), 0) AS cash_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'card'
          THEN r.amount_cents ELSE 0 END), 0) AS card_revenue
       FROM revenue_ledger r
       LEFT JOIN profiles p_client ON p_client.id = r.client_user_id
       ${where}`,
      params,
    ),
    powerSync.getAll(revenueRowsSql(where), [...params, limit, offset]),
  ]);
  const rows = asRecords(data);
  const statsRow = asRecord(stats);
  const totalCount = asInteger(statsRow.total_count);
  return {
    items: rows.map(parseRevenueRow),
    rows,
    totalCount,
    totalRevenueCents: asInteger(statsRow.total_revenue),
    cashRevenueCents: asInteger(statsRow.cash_revenue),
    cardRevenueCents: asInteger(statsRow.card_revenue),
    hasMore: offset + rows.length < totalCount,
  };
}

export interface RevenueTodayComparison {
  todayRevenueCents: number;
  yesterdayRevenueCents: number;
  lastWeekSameDayRevenueCents: number;
  todayCount: number;
  yesterdayCount: number;
}

export async function getRevenueTodayComparison(gymId?: string, now = new Date()) {
  await connectPowerSyncIfAuthenticated();
  const today = calendarDateFromLocalDate(now);
  const yesterday = addCalendarDays(today, -1);
  const lastWeek = addCalendarDays(today, -7);
  const params: SqlValue[] = [
    today, yesterday, lastWeek, today, yesterday,
  ];
  if (gymId) params.push(gymId);
  const row = asRecord(
    await powerSync.get(
      `SELECT
        COALESCE(SUM(CASE WHEN ${sqliteLocalCalendarDate('paid_at')} = date(?) THEN amount_cents ELSE 0 END), 0) AS today_revenue,
        COALESCE(SUM(CASE WHEN ${sqliteLocalCalendarDate('paid_at')} = date(?) THEN amount_cents ELSE 0 END), 0) AS yesterday_revenue,
        COALESCE(SUM(CASE WHEN ${sqliteLocalCalendarDate('paid_at')} = date(?) THEN amount_cents ELSE 0 END), 0) AS last_week_same_day_revenue,
        COUNT(CASE WHEN ${sqliteLocalCalendarDate('paid_at')} = date(?) THEN 1 END) AS today_count,
        COUNT(CASE WHEN ${sqliteLocalCalendarDate('paid_at')} = date(?) THEN 1 END) AS yesterday_count
       FROM revenue_ledger
       WHERE entry_kind = 'charge' AND COALESCE(is_deleted, 0) = 0
       ${gymId ? 'AND gym_id = ?' : ''}`,
      params,
    ),
  );
  return {
    todayRevenueCents: asInteger(row.today_revenue),
    yesterdayRevenueCents: asInteger(row.yesterday_revenue),
    lastWeekSameDayRevenueCents: asInteger(row.last_week_same_day_revenue),
    todayCount: asInteger(row.today_count),
    yesterdayCount: asInteger(row.yesterday_count),
  } satisfies RevenueTodayComparison;
}

export type RevenueTrendInterval = 'day' | 'week';

export async function getRevenueAnalytics({
  startDate,
  endDate,
  gymId,
  trendInterval,
}: {
  startDate: CalendarDate;
  endDate: CalendarDate;
  gymId?: string;
  trendInterval: RevenueTrendInterval;
}) {
  await connectPowerSyncIfAuthenticated();
  const filteredParams: SqlValue[] = [startDate, endDate];
  const base = [
    "r.entry_kind = 'charge'",
    'COALESCE(r.is_deleted, 0) = 0',
    sqliteCalendarDateRangePredicate('r.paid_at'),
  ];
  if (gymId) {
    base.push('r.gym_id = ?');
    filteredParams.push(gymId);
  }
  const filteredWhere = `WHERE ${base.join(' AND ')}`;
  const gymWhere = `WHERE r.entry_kind = 'charge'
    AND COALESCE(r.is_deleted, 0) = 0
    AND ${sqliteCalendarDateRangePredicate('r.paid_at')}`;
  const groupedFields = `
    COALESCE(SUM(r.amount_cents), 0) AS total_revenue,
    COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'cash' THEN r.amount_cents ELSE 0 END), 0) AS cash_revenue,
    COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'card' THEN r.amount_cents ELSE 0 END), 0) AS card_revenue,
    COUNT(*) AS transaction_count`;
  const periodExpression =
    trendInterval === 'day'
      ? sqliteLocalCalendarDate('r.paid_at')
      : "date(r.paid_at, 'localtime', '-' || ((CAST(strftime('%w', r.paid_at, 'localtime') AS INTEGER) + 6) % 7) || ' days')";

  const [byPlanRaw, byGymRaw, trendRaw] = await Promise.all([
    powerSync.getAll(
      `SELECT COALESCE(mp.name, 'Fără plan') AS plan_name, ${groupedFields}
       FROM revenue_ledger r
       LEFT JOIN membership_plans mp ON mp.id = r.plan_id
       ${filteredWhere}
       GROUP BY COALESCE(r.plan_id, ''), COALESCE(mp.name, 'Fără plan')
       ORDER BY total_revenue DESC`,
      filteredParams,
    ),
    powerSync.getAll(
      `SELECT COALESCE(g.name, 'Fără sală') AS gym_name, ${groupedFields}
       FROM revenue_ledger r
       LEFT JOIN gyms g ON g.id = r.gym_id
       ${gymWhere}
       GROUP BY COALESCE(r.gym_id, ''), COALESCE(g.name, 'Fără sală')
       ORDER BY total_revenue DESC`,
      [startDate, endDate],
    ),
    powerSync.getAll(
      `SELECT ${periodExpression} AS period, ${groupedFields}
       FROM revenue_ledger r
       ${filteredWhere}
       GROUP BY period ORDER BY datetime(period) ASC`,
      filteredParams,
    ),
  ]);
  const byPlan = asRecords(byPlanRaw);
  const byGym = asRecords(byGymRaw);
  const trend = asRecords(trendRaw);
  const stats = trend.reduce<{
    totalCents: number;
    cashCents: number;
    cardCents: number;
    transactionCount: number;
  }>(
    (acc, row) => ({
      totalCents: acc.totalCents + asInteger(row.total_revenue),
      cashCents: acc.cashCents + asInteger(row.cash_revenue),
      cardCents: acc.cardCents + asInteger(row.card_revenue),
      transactionCount: acc.transactionCount + asInteger(row.transaction_count),
    }),
    { totalCents: 0, cashCents: 0, cardCents: 0, transactionCount: 0 },
  );
  return {
    byPlan,
    byGym,
    trend,
    stats: {
      ...stats,
      averageTransactionCents: stats.transactionCount ? stats.totalCents / stats.transactionCount : 0,
    },
  };
}

const dayPassPlanIds = [
  '52f9fa66-b839-4855-936a-25e0f46165de',
  '01095869-f243-4b8c-a8ff-9730ac3ad044',
] as const;

export async function getRevenuePeriodStats({
  start,
  end,
  gymId,
}: {
  start?: CalendarDate;
  end?: CalendarDate;
  gymId?: string;
}) {
  await connectPowerSyncIfAuthenticated();
  const clauses = ["r.entry_kind = 'charge'", 'COALESCE(r.is_deleted, 0) = 0'];
  const params: SqlValue[] = [];
  if (gymId) {
    clauses.push('r.gym_id = ?');
    params.push(gymId);
  }
  if (start) {
    clauses.push(`${sqliteLocalCalendarDate('r.paid_at')} >= date(?)`);
    params.push(start);
  }
  if (end) {
    clauses.push(`${sqliteLocalCalendarDate('r.paid_at')} <= date(?)`);
    params.push(end);
  }
  const where = `WHERE ${clauses.join(' AND ')}`;
  const [statsRaw, byPlanRaw] = await Promise.all([
    powerSync.get(
      `SELECT
        COALESCE(SUM(r.amount_cents), 0) AS total_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'cash' THEN r.amount_cents ELSE 0 END), 0) AS cash_revenue,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(r.payment_method, '')) = 'card' THEN r.amount_cents ELSE 0 END), 0) AS card_revenue,
        COUNT(*) AS transaction_count,
        COALESCE(AVG(r.amount_cents), 0) AS avg_transaction,
        COUNT(DISTINCT m.user_id) AS unique_members,
        COUNT(CASE WHEN r.source = 'day_pass' THEN 1 END) AS day_pass_count,
        COUNT(CASE WHEN r.source IN ('membership', 'membership_sale')
          AND (r.plan_id IS NULL OR r.plan_id NOT IN (?, ?)) THEN 1 END) AS new_memberships_count,
        COUNT(CASE WHEN r.source = 'membership_extension' THEN 1 END) AS extensions_count,
        COUNT(CASE WHEN r.source = 'membership_upgrade' THEN 1 END) AS upgrades_count
       FROM revenue_ledger r
       LEFT JOIN memberships m ON m.id = r.membership_id
       ${where}`,
      [...dayPassPlanIds, ...params],
    ),
    powerSync.getAll(
      `SELECT mp.name AS plan_name, COALESCE(SUM(r.amount_cents), 0) AS revenue,
              COUNT(*) AS count
       FROM revenue_ledger r
       JOIN membership_plans mp ON mp.id = r.plan_id
       ${where} AND r.source <> 'product'
       GROUP BY mp.id, mp.name ORDER BY revenue DESC`,
      params,
    ),
  ]);
  const row = asRecord(statsRaw);
  return {
    totalRevenueCents: asInteger(row.total_revenue),
    cashRevenueCents: asInteger(row.cash_revenue),
    cardRevenueCents: asInteger(row.card_revenue),
    transactionCount: asInteger(row.transaction_count),
    averageTransactionCents: asNumber(row.avg_transaction),
    uniqueMembers: asInteger(row.unique_members),
    dayPassCount: asInteger(row.day_pass_count),
    newMembershipsCount: asInteger(row.new_memberships_count),
    extensionsCount: asInteger(row.extensions_count),
    upgradesCount: asInteger(row.upgrades_count),
    revenueByPlan: asRecords(byPlanRaw),
  };
}

export async function softDeleteRevenueEntry(id: string) {
  const supabase = getSupabase();
  const { data, error: userError } = await supabase.auth.getUser();
  if (userError) throw userError;
  const { error } = await supabase
    .from('revenue_ledger')
    .update({
      is_deleted: true,
      deleted_at: new Date().toISOString(),
      deleted_by: data.user?.id ?? null,
    })
    .eq('id', id);
  if (error) throw error;
}

export async function restoreRevenueEntry(id: string) {
  const { error } = await getSupabase()
    .from('revenue_ledger')
    .update({ is_deleted: false, deleted_at: null, deleted_by: null })
    .eq('id', id);
  if (error) throw error;
}

export interface RevenueEntryUpdate {
  paid_at?: string;
  amount_cents?: number;
  payment_method?: string;
  gym_id?: string | null;
  plan_id?: string | null;
  notes?: string | null;
}

export async function updateRevenueEntry(id: string, update: RevenueEntryUpdate) {
  const { error } = await getSupabase().from('revenue_ledger').update(update).eq('id', id);
  if (error) throw error;
}
