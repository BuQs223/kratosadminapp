import {
  asInteger,
  asNumber,
  asRecord,
  asRecords,
  asString,
  asDate,
} from '@/utils/parsing';

export interface BusinessMetrics {
  totalMembers: number;
  activeMembers: number;
  newMembersThisMonth: number;
  monthlyRevenue: number;
  checkInsToday: number;
  averageGymOccupancy: number;
  totalGyms: number;
}

export const emptyBusinessMetrics = (): BusinessMetrics => ({
  totalMembers: 0,
  activeMembers: 0,
  newMembersThisMonth: 0,
  monthlyRevenue: 0,
  checkInsToday: 0,
  averageGymOccupancy: 0,
  totalGyms: 0,
});

export function parseBusinessMetrics(value: unknown): BusinessMetrics {
  const row = asRecord(value);
  return {
    totalMembers: asInteger(row.total_members),
    activeMembers: asInteger(row.active_members),
    newMembersThisMonth: asInteger(row.new_members_this_month),
    monthlyRevenue: asNumber(row.monthly_revenue),
    checkInsToday: asInteger(row.check_ins_today),
    averageGymOccupancy: asNumber(row.average_gym_occupancy),
    totalGyms: asInteger(row.total_gyms),
  };
}

export interface RevenueData {
  date: Date;
  amount: number;
  source: string;
}

export function parseRevenueData(value: unknown): RevenueData {
  const row = asRecord(value);
  return { date: asDate(row.date), amount: asNumber(row.amount), source: asString(row.source) };
}

export interface MembershipTrend {
  date: Date;
  newMemberships: number;
  canceledMemberships: number;
  netChange: number;
}

export function parseMembershipTrend(value: unknown): MembershipTrend {
  const row = asRecord(value);
  return {
    date: asDate(row.date),
    newMemberships: asInteger(row.new_memberships),
    canceledMemberships: asInteger(row.canceled_memberships),
    netChange: asInteger(row.net_change),
  };
}

export interface GymOccupancy {
  gymName: string;
  currentOccupancy: number;
  maxCapacity: number;
  occupancyPercentage: number;
  hourlyData: Record<string, unknown>[];
}

export function parseGymOccupancy(value: unknown): GymOccupancy {
  const row = asRecord(value);
  return {
    gymName: asString(row.gym_name),
    currentOccupancy: asInteger(row.current_occupancy),
    maxCapacity: asInteger(row.max_capacity),
    occupancyPercentage: asNumber(row.occupancy_percentage),
    hourlyData: asRecords(row.hourly_data),
  };
}
