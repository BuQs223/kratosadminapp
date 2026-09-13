import { getSupabase } from '@/lib/supabase/client';
import {
  parseMembershipTrendPoint,
  type MembershipTrendPoint,
  type MembershipTrendRange,
} from '@/models/membership-trend';
import { asRecords } from '@/utils/parsing';

export async function getMembershipAccessTrend({
  range,
  gymId,
}: {
  range: MembershipTrendRange;
  gymId?: string;
}): Promise<MembershipTrendPoint[]> {
  const { data, error } = await getSupabase().rpc('get_admin_membership_access_trend', {
    p_range: range,
    p_gym_id: gymId ?? null,
  });

  if (error) {
    // React Query owns the user-facing retry state. Keep the original Supabase
    // error for it, but surface the structured response in Metro while debugging.
    if (__DEV__ && process.env.NODE_ENV !== 'test') {
      console.warn('Membership analytics RPC failed', error);
    }
    throw error;
  }
  return asRecords(data).map(parseMembershipTrendPoint);
}
