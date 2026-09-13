import { flutterDateTimeIso } from '@/utils/flutter-date';
import {
  emptyBusinessMetrics,
  parseBusinessMetrics,
  parseGymOccupancy,
  parseMembershipTrend,
  parseRevenueData,
  type BusinessMetrics,
  type GymOccupancy,
  type MembershipTrend,
  type RevenueData,
} from '@/models/analytics';
import { getSupabase } from '@/lib/supabase/client';
import { asRecord, asRecords } from '@/utils/parsing';

async function rpc(name: string, params?: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await getSupabase().rpc(name, params);
  if (error) throw error;
  return data;
}

export const analyticsService = {
  async getBusinessMetrics(): Promise<BusinessMetrics> {
    try {
      return parseBusinessMetrics(await rpc('get_business_metrics'));
    } catch (error) {
      console.warn('Error fetching business metrics', error);
      return emptyBusinessMetrics();
    }
  },

  async getRevenueTrends({
    startDate,
    endDate,
    groupBy = 'day',
  }: {
    startDate: Date;
    endDate: Date;
    groupBy?: 'day' | 'week' | 'month';
  }): Promise<RevenueData[]> {
    try {
      const data = await rpc('get_revenue_trends', {
        start_date: flutterDateTimeIso(startDate),
        end_date: flutterDateTimeIso(endDate),
        group_by: groupBy,
      });
      return asRecords(data).map(parseRevenueData);
    } catch (error) {
      console.warn('Error fetching revenue trends', error);
      return [];
    }
  },

  async getMembershipTrends({
    startDate,
    endDate,
  }: {
    startDate: Date;
    endDate: Date;
  }): Promise<MembershipTrend[]> {
    try {
      const data = await rpc('get_membership_trends', {
        start_date: flutterDateTimeIso(startDate),
        end_date: flutterDateTimeIso(endDate),
      });
      return asRecords(data).map(parseMembershipTrend);
    } catch (error) {
      console.warn('Error fetching membership trends', error);
      return [];
    }
  },

  async getGymOccupancy(): Promise<GymOccupancy[]> {
    try {
      return asRecords(await rpc('get_gym_occupancy')).map(parseGymOccupancy);
    } catch (error) {
      console.warn('Error fetching gym occupancy', error);
      return [];
    }
  },

  async getTopPerformingGyms({
    limit = 5,
    startDate,
    endDate,
  }: {
    limit?: number;
    startDate?: Date;
    endDate?: Date;
  } = {}) {
    try {
      return asRecords(
        await rpc('get_top_performing_gyms', {
          limit_count: limit,
          ...(startDate ? { start_date: flutterDateTimeIso(startDate) } : {}),
          ...(endDate ? { end_date: flutterDateTimeIso(endDate) } : {}),
        }),
      );
    } catch (error) {
      console.warn('Error fetching top performing gyms', error);
      return [];
    }
  },

  async getMemberRetention() {
    try {
      return asRecord(await rpc('get_member_retention'));
    } catch (error) {
      console.warn('Error fetching member retention', error);
      return {};
    }
  },

  async getCheckInPatterns(date?: Date) {
    try {
      return asRecords(
        await rpc('get_checkin_patterns', date ? { target_date: flutterDateTimeIso(date) } : {}),
      );
    } catch (error) {
      console.warn('Error fetching check-in patterns', error);
      return [];
    }
  },

  async getMembershipPlanPerformance() {
    try {
      return asRecords(await rpc('get_membership_plan_performance'));
    } catch (error) {
      console.warn('Error fetching membership plan performance', error);
      return [];
    }
  },

  async getPaymentMethodAnalytics({
    startDate,
    endDate,
  }: { startDate?: Date; endDate?: Date } = {}) {
    try {
      return asRecord(
        await rpc('get_payment_method_analytics', {
          ...(startDate ? { start_date: flutterDateTimeIso(startDate) } : {}),
          ...(endDate ? { end_date: flutterDateTimeIso(endDate) } : {}),
        }),
      );
    } catch (error) {
      console.warn('Error fetching payment method analytics', error);
      return {};
    }
  },

  async trackEvent({
    eventName,
    userId,
    properties = {},
  }: {
    eventName: string;
    userId: string;
    properties?: Record<string, unknown>;
  }) {
    const { error } = await getSupabase().from('analytics_events').insert({
      event_name: eventName,
      user_id: userId,
      properties,
      created_at: flutterDateTimeIso(new Date()),
    });
    if (error) console.warn('Error tracking event', error);
  },
};
