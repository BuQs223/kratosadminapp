import { getSupabase } from '@/lib/supabase/client';
import { asRecord, asRecords } from '@/utils/parsing';

export type MembershipPlanStatus = 'all' | 'active' | 'inactive';

export interface MembershipPlanInput {
  name: string;
  tier: string;
  gymId: string | null;
  monthlyPriceCents: number;
  isActive: boolean;
  isFamilyPlan: boolean;
  isGoodMorning: boolean;
  durationMonths: number;
  durationDays: number;
}

export async function getMembershipPlans(status: MembershipPlanStatus) {
  let query = getSupabase()
    .from('membership_plans')
    .select('*, gyms!membership_plans_gym_id_fkey(id, name)');

  if (status === 'active') query = query.eq('is_active', true);
  if (status === 'inactive') query = query.eq('is_active', false);
  const { data, error } = await query.order('created_at', { ascending: false });
  if (error) throw error;
  return asRecords(data);
}

export async function setMembershipPlanActive(id: string, isActive: boolean) {
  const { error } = await getSupabase()
    .from('membership_plans')
    .update({ is_active: isActive })
    .eq('id', id);
  if (error) throw error;
}

export async function saveMembershipPlan(input: MembershipPlanInput, id?: string) {
  const data = {
    name: input.name,
    tier: input.tier,
    gym_id: input.gymId,
    monthly_price_cents: input.monthlyPriceCents,
    yearly_price_cents: 0,
    student_discount_cents: 0,
    currency: 'RON',
    plan_kind: 'package',
    is_active: input.isActive,
    is_family_plan: input.isFamilyPlan,
    is_good_morning: input.isGoodMorning,
    duration_months: input.durationMonths,
    duration_days: input.durationDays,
    updated_at: new Date().toISOString(),
  };

  const result = id
    ? await getSupabase().from('membership_plans').update(data).eq('id', id).select().single()
    : await getSupabase().from('membership_plans').insert(data).select().single();
  if (result.error) throw result.error;
  return asRecord(result.data);
}
