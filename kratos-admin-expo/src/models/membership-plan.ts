import {
  asBoolean,
  asDate,
  flutterInteger as asInteger,
  flutterNullableInteger as asNullableInteger,
  asRecord,
  asString,
} from '@/utils/parsing';

export interface MembershipPlan {
  id: string;
  name: string;
  tier: string;
  monthlyPriceCents: number;
  yearlyPriceCents: number;
  currency: string;
  isFamilyPlan: boolean;
  maxFamilyMembers: number | null;
  isActive: boolean;
  createdAt: Date;
}

export function parseMembershipPlan(value: unknown): MembershipPlan {
  const row = asRecord(value);
  return {
    id: asString(row.id ?? row.membership_plan_id),
    name: asString(row.name ?? row.plan_name, 'Plan Necunoscut'),
    tier: asString(row.tier, 'basic'),
    monthlyPriceCents: asInteger(row.monthly_price_cents),
    yearlyPriceCents: asInteger(row.yearly_price_cents),
    currency: asString(row.currency, 'RON'),
    isFamilyPlan: asBoolean(row.is_family_plan),
    maxFamilyMembers: asNullableInteger(row.max_family_members),
    isActive: asBoolean(row.is_active, true),
    createdAt: asDate(row.created_at),
  };
}

export const monthlyPlanPrice = (plan: MembershipPlan) => plan.monthlyPriceCents / 100;
export const yearlyPlanPrice = (plan: MembershipPlan) => plan.yearlyPriceCents / 100;
