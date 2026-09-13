import { connectPowerSyncIfAuthenticated, powerSync } from '@/lib/powersync/system';
import { asInteger, asRecord } from '@/utils/parsing';
import { elapsedDays, flutterDateTimeIso, localMidnight } from '@/utils/flutter-date';

export interface DashboardStats {
  totalMembers: number;
  activeMemberships: number;
  todayCheckIns: number;
  monthlyRevenue: number;
  wau: number;
  mau: number;
  dauYesterday: number;
}

export async function getDashboardStats(now = new Date()): Promise<DashboardStats> {
  await connectPowerSyncIfAuthenticated();
  const today = localMidnight(now);
  const monthStart = flutterDateTimeIso(new Date(now.getFullYear(), now.getMonth(), 1));

  const [members, checkIns, active, revenue, summary] = await Promise.all([
    powerSync.get('SELECT COUNT(*) AS count FROM profiles'),
    powerSync.get(
      `SELECT COUNT(*) AS count
       FROM check_ins
       WHERE datetime(created_at) >= datetime(?) AND datetime(created_at) < datetime(?)`,
      [flutterDateTimeIso(today), flutterDateTimeIso(elapsedDays(today, 1))],
    ),
    powerSync.getOptional(`
      WITH active_users AS (
        SELECT m.user_id
        FROM memberships m
        WHERE m.canceled_at IS NULL
          AND COALESCE(m.days_left, CAST(julianday(m.end_date) - julianday('now', 'localtime') AS INTEGER)) >= 0
          AND COALESCE(m.is_frozen, 0) = 0
        UNION
        SELECT fm.user_id
        FROM family_memberships fm
        JOIN memberships m ON m.id = fm.membership_id
        WHERE m.canceled_at IS NULL
          AND COALESCE(m.days_left, CAST(julianday(m.end_date) - julianday('now', 'localtime') AS INTEGER)) >= 0
          AND COALESCE(m.is_frozen, 0) = 0
      )
      SELECT COUNT(DISTINCT user_id) AS count
      FROM active_users
    `),
    powerSync.get(
      `SELECT COALESCE(SUM(amount_cents), 0) AS amount_cents
       FROM revenue_ledger
       WHERE entry_kind = 'charge'
         AND datetime(paid_at) >= datetime(?)`,
      [monthStart],
    ),
    powerSync.getOptional(`
      SELECT
        COALESCE(wau, 0) AS wau,
        COALESCE(mau, 0) AS mau,
        COALESCE(yesterday_dau, 0) AS yesterday_dau
      FROM admin_analytics_summary
      WHERE id = 'current'
      LIMIT 1
    `),
  ]);

  const summaryRow = asRecord(summary);
  return {
    totalMembers: asInteger(asRecord(members).count),
    activeMemberships: asInteger(asRecord(active).count),
    todayCheckIns: asInteger(asRecord(checkIns).count),
    monthlyRevenue: asInteger(asRecord(revenue).amount_cents) / 100,
    wau: asInteger(summaryRow.wau),
    mau: asInteger(summaryRow.mau),
    dauYesterday: asInteger(summaryRow.yesterday_dau),
  };
}
