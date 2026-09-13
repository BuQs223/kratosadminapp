import { parseGym, type Gym } from '@/models/gym';
import { parseMembershipPlan, type MembershipPlan } from '@/models/membership-plan';
import {
  asBoolean,
  asDate,
  flutterInteger as asInteger,
  asNullableDate,
  flutterNullableInteger as asNullableInteger,
  asNullableString,
  asRecord,
  flutterNullableTruncatedNumber,
  asString,
} from '@/utils/parsing';
import { elapsedDays, dayMilliseconds } from '@/utils/flutter-date';

export interface Membership {
  id: string;
  userId: string;
  planId: string;
  soldAtGymId: string;
  startDate: Date;
  effectiveStartDate: Date | null;
  endDate: Date;
  durationMonths: number;
  pricePaidCents: number;
  currency: string;
  paymentMethod: string;
  membershipType: string;
  isActive: boolean;
  isStudent: boolean;
  cancelReason: string | null;
  canceledAt: Date | null;
  createdAt: Date;
  isFrozen: boolean;
  frozenAt: Date | null;
  frozenByUserId: string | null;
  daysLeftWhenFrozen: number | null;
  daysLeft: number | null;
  freezeType: string | null;
  autoUnfreezeAt: Date | null;
  plan: MembershipPlan | null;
  gym: Gym | null;
}

export function parseMembership(value: unknown): Membership {
  const row = asRecord(value);
  const planValue = row.membership_plans ?? row.membership_plan;
  const gymValue = row.gyms ?? row.gym;
  return {
    id: asString(row.id ?? row.membership_id),
    userId: asString(row.user_id),
    planId: asString(row.plan_id ?? row.membership_plan_id),
    soldAtGymId: asString(row.sold_at_gym_id),
    startDate: asDate(row.start_date),
    effectiveStartDate: asNullableDate(row.effective_start_date),
    endDate: asDate(row.end_date, elapsedDays(new Date(), 30)),
    durationMonths: asInteger(row.duration_months, 1),
    pricePaidCents: asInteger(row.price_paid_cents),
    currency: asString(row.currency, 'RON'),
    paymentMethod: asString(row.payment_method, 'cash'),
    membershipType: asString(row.membership_type, 'monthly'),
    isActive: asBoolean(row.is_active),
    isStudent: asBoolean(row.is_student),
    cancelReason: asNullableString(row.cancel_reason),
    canceledAt: asNullableDate(row.canceled_at),
    createdAt: asDate(row.created_at),
    isFrozen: asBoolean(row.is_frozen),
    frozenAt: asNullableDate(row.frozen_at),
    frozenByUserId: asNullableString(row.frozen_by_user_id),
    daysLeftWhenFrozen: asNullableInteger(row.days_left_when_frozen),
    daysLeft: asNullableInteger(row.days_left),
    freezeType: asNullableString(row.freeze_type),
    autoUnfreezeAt: asNullableDate(row.auto_unfreeze_at),
    plan: planValue ? parseMembershipPlan(planValue) : null,
    gym: gymValue ? parseGym(gymValue) : null,
  };
}

export function parseOptimizedMembership(value: unknown): Membership {
  const row = asRecord(value);
  const base = parseMembership({ ...row, days_left: flutterNullableTruncatedNumber(row.days_left), days_left_when_frozen: flutterNullableTruncatedNumber(row.days_left_when_frozen) });
  return {
    ...base,
    plan: parseMembershipPlan({
      membership_plan_id: row.membership_plan_id,
      plan_name: row.plan_name,
      tier: row.tier,
      is_family_plan: row.is_family_plan,
      currency: 'RON',
      is_active: true,
    }),
    gym: row.sold_at_gym_name
      ? parseGym({ id: row.sold_at_gym_id, name: row.sold_at_gym_name })
      : null,
  };
}

export const membershipPrice = (membership: Membership) => membership.pricePaidCents / 100;

export function membershipIsExpired(membership: Membership, now = new Date()): boolean {
  return membership.daysLeft !== null
    ? membership.daysLeft < 0
    : now.getTime() > membership.endDate.getTime();
}

export function membershipDaysUntilExpiry(membership: Membership, now = new Date()): number {
  if (membership.daysLeft !== null) return Math.max(membership.daysLeft, 0);
  if (membershipIsExpired(membership, now)) return 0;
  return Math.max(Math.trunc((membership.endDate.getTime() - now.getTime()) / dayMilliseconds), 0);
}

export function membershipStatusText(membership: Membership): string {
  if (membership.canceledAt) return 'Anulat';
  if (membershipIsExpired(membership)) return 'Expirat';
  if (membership.isFrozen) return 'Înghețat';
  const days = membership.daysLeft ?? membershipDaysUntilExpiry(membership);
  if (days >= 0 && days <= 7) return `Expiră în ${days} zile`;
  return 'Activ';
}
