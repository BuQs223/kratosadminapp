import { parseGym, type Gym } from '@/models/gym';
import { parseMembershipPlan, type MembershipPlan } from '@/models/membership-plan';
import { parseProfile, type Profile } from '@/models/profile';
import {
  asBoolean,
  requiredDate,
  requiredString,
  requiredInteger,
  asNullableDate,
  asNullableString,
  asRecord,
} from '@/utils/parsing';

export interface RevenueLedger {
  id: string;
  paidAt: Date;
  planId: string | null;
  membershipId: string | null;
  gymId: string | null;
  amountCents: number;
  currency: string;
  source: string;
  entryKind: string;
  paymentMethod: string;
  notes: string | null;
  recordedBy: string | null;
  isDeleted: boolean;
  deletedAt: Date | null;
  deletedBy: string | null;
  createdAt: Date;
  recordedByProfile: Profile | null;
  clientProfile: Profile | null;
  plan: MembershipPlan | null;
  gym: Gym | null;
  deletedByProfile: Profile | null;
}

export function parseRevenueLedger(value: unknown): RevenueLedger {
  const row = asRecord(value);
  return {
    id: requiredString(row.id),
    paidAt: requiredDate(row.paid_at),
    planId: asNullableString(row.plan_id),
    membershipId: asNullableString(row.membership_id),
    gymId: asNullableString(row.gym_id),
    amountCents: requiredInteger(row.amount_cents),
    currency: requiredString(row.currency),
    source: requiredString(row.source),
    entryKind: requiredString(row.entry_kind),
    paymentMethod: requiredString(row.payment_method),
    notes: asNullableString(row.notes),
    recordedBy: asNullableString(row.recorded_by),
    isDeleted: asBoolean(row.is_deleted),
    deletedAt: asNullableDate(row.deleted_at),
    deletedBy: asNullableString(row.deleted_by),
    createdAt: requiredDate(row.created_at),
    recordedByProfile: row.recorded_by_profile ? parseProfile(row.recorded_by_profile) : null,
    clientProfile: row.profile ? parseProfile(row.profile) : null,
    plan: row.membership_plan ? parseMembershipPlan(row.membership_plan) : null,
    gym: row.gym ? parseGym(row.gym) : null,
    deletedByProfile: row.deleted_by_profile ? parseProfile(row.deleted_by_profile) : null,
  };
}

export const revenueAmount = (entry: RevenueLedger) => entry.amountCents / 100;
export const revenueAmountLabel = (entry: RevenueLedger) =>
  `${revenueAmount(entry).toFixed(2)} ${entry.currency}`;
