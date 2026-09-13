import { connectPowerSyncIfAuthenticated, powerSync } from '@/lib/powersync/system';
import { parseCheckIn, type CheckIn } from '@/models/check-in';
import {
  asBoolean,
  asInteger,
  asRecord,
  flutterNullableTruncatedNumber,
  asRecords,
  asString,
} from '@/utils/parsing';
import {
  type CalendarDate,
} from '@/utils/calendar-date';

type SqlValue = string | number | null;

export interface CheckInFilters {
  gymId?: string;
  status?: string;
}

export interface CheckInPage {
  items: CheckIn[];
  hasMore: boolean;
}

export async function getCheckIns({
  filters = {},
  limit = 20,
  offset = 0,
}: {
  filters?: CheckInFilters;
  limit?: number;
  offset?: number;
}): Promise<CheckInPage> {
  await connectPowerSyncIfAuthenticated();
  const clauses: string[] = [];
  const params: SqlValue[] = [];
  if (filters.gymId) {
    clauses.push('c.gym_id = ?');
    params.push(filters.gymId);
  }
  if (filters.status) {
    clauses.push('c.status = ?');
    params.push(filters.status);
  }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  const rows = asRecords(
    await powerSync.getAll(
      `SELECT
        c.id, c.user_id, c.gym_id, c.membership_id, c.status, c.message,
        c.days_left, c.shown_to_user, c.method, c.created_at,
        p.full_name AS user_full_name, p.email AS user_email,
        p.phone AS user_phone, p.created_at AS user_created_at,
        p.is_admin AS user_is_admin, p.is_employee AS user_is_employee,
        g.name AS gym_name, g.created_at AS gym_created_at
       FROM check_ins c
       LEFT JOIN profiles p ON p.id = c.user_id
       LEFT JOIN gyms g ON g.id = c.gym_id
       ${where}
       ORDER BY c.created_at DESC
       LIMIT ? OFFSET ?`,
      [...params, limit, offset],
    ),
  );

  const items = rows.flatMap((row) => {
    try {
      return [
        parseCheckIn({
          ...row,
          days_left: flutterNullableTruncatedNumber(row.days_left),
          profiles: row.user_full_name != null
            ? {
                id: row.user_id,
                full_name: row.user_full_name,
                email: row.user_email,
                phone: row.user_phone,
                created_at: row.user_created_at,
                is_admin: asBoolean(row.user_is_admin),
                is_employee: asBoolean(row.user_is_employee),
                role: 'client',
              }
            : null,
          gyms: row.gym_name != null
            ? { id: row.gym_id, name: row.gym_name, created_at: row.gym_created_at }
            : null,
        }),
      ];
    } catch (error) {
      console.warn('Skipping malformed check-in row', {
        entity: 'check_in',
        id: typeof row.id === 'string' ? row.id : 'unknown',
        reason: error instanceof Error ? error.name : 'parse_failure',
      });
      return [];
    }
  });
  return { items, hasMore: items.length === limit };
}

export interface CheckInHourStat {
  hour: number;
  checkIns: number;
}

export interface CheckInGymStat {
  gymName: string;
  checkIns: number;
}

export async function getCheckInStats({
  start,
  end,
  gymId,
}: {
  start: string;
  /** Exclusive timestamp, captured when the Flutter preset/custom range is applied. */
  end: string;
  gymId?: string;
}) {
  await connectPowerSyncIfAuthenticated();
  const params: SqlValue[] = [start, end];
  const gymFilter = gymId ? 'AND c.gym_id = ?' : '';
  if (gymId) params.push(gymId);

  const [total, hourRows, gymRows] = await Promise.all([
    powerSync.get(
      `SELECT COUNT(*) AS total_checkins
       FROM check_ins c
       WHERE datetime(c.created_at) >= datetime(?) AND datetime(c.created_at) < datetime(?) ${gymFilter}`,
      params,
    ),
    powerSync.getAll(
      `SELECT CAST(strftime('%H', datetime(c.created_at), 'localtime') AS INTEGER) AS hour,
              COUNT(*) AS checkins
       FROM check_ins c
       WHERE datetime(c.created_at) >= datetime(?) AND datetime(c.created_at) < datetime(?) ${gymFilter}
       GROUP BY hour ORDER BY checkins DESC, hour ASC LIMIT 5`,
      params,
    ),
    powerSync.getAll(
      `SELECT COALESCE(g.name, 'Unknown') AS gym_name, COUNT(*) AS checkins
       FROM check_ins c
       LEFT JOIN gyms g ON g.id = c.gym_id
       WHERE datetime(c.created_at) >= datetime(?) AND datetime(c.created_at) < datetime(?) ${gymFilter}
       GROUP BY c.gym_id, g.name
       ORDER BY checkins DESC, gym_name COLLATE NOCASE LIMIT 5`,
      params,
    ),
  ]);

  return {
    totalCheckIns: asInteger(asRecord(total).total_checkins),
    busiestHours: asRecords(hourRows).map(
      (row): CheckInHourStat => ({ hour: asInteger(row.hour), checkIns: asInteger(row.checkins) }),
    ),
    topGyms: asRecords(gymRows).map(
      (row): CheckInGymStat => ({
        gymName: asString(row.gym_name, 'Unknown'),
        checkIns: asInteger(row.checkins),
      }),
    ),
  };
}

export interface GymTierCheckInStats {
  gymId: string;
  gymName: string;
  uniqueGoldMembers: number;
  totalGoldCheckIns: number;
  uniqueSilverMembers: number;
  totalSilverCheckIns: number;
}

export interface GymTierCheckInResult {
  gyms: GymTierCheckInStats[];
  kratosOneAndTwoUniqueGoldMembers: number;
}

export async function getGymTierCheckInStats(start: CalendarDate, end: CalendarDate): Promise<GymTierCheckInResult> {
  await connectPowerSyncIfAuthenticated();
  const rows = await powerSync.getAll(
    `SELECT
      g.id AS gym_id, g.name AS gym_name,
      COUNT(DISTINCT CASE WHEN mp.tier = 'gold' THEN ci.user_id END) AS unique_gold_members,
      COUNT(CASE WHEN mp.tier = 'gold' THEN ci.id END) AS total_checkins,
      COUNT(DISTINCT CASE WHEN mp.tier = 'silver' THEN ci.user_id END) AS unique_silver_members,
      COUNT(CASE WHEN mp.tier = 'silver' THEN ci.id END) AS silver_total_checkins
     FROM gyms g
     LEFT JOIN check_ins ci ON ci.gym_id = g.id
       AND date(ci.created_at) >= ? AND date(ci.created_at) <= ?
       AND ci.status = 'success'
     LEFT JOIN memberships m ON m.id = ci.membership_id
     LEFT JOIN membership_plans mp ON mp.id = m.plan_id
     GROUP BY g.id, g.name
     ORDER BY g.name COLLATE NOCASE`,
      [start, end],
    );
  const gyms = asRecords(rows).map(
    (row): GymTierCheckInStats => ({
      gymId: asString(row.gym_id),
      gymName: asString(row.gym_name),
      uniqueGoldMembers: asInteger(row.unique_gold_members),
      totalGoldCheckIns: asInteger(row.total_checkins),
      uniqueSilverMembers: asInteger(row.unique_silver_members),
      totalSilverCheckIns: asInteger(row.silver_total_checkins),
    }),
    );
  return {
    gyms,
    kratosOneAndTwoUniqueGoldMembers: (gyms.find((gym) => gym.gymName === 'Kratos 1')?.uniqueGoldMembers ?? 0)
      + (gyms.find((gym) => gym.gymName === 'Kratos 2')?.uniqueGoldMembers ?? 0),
  };
}
