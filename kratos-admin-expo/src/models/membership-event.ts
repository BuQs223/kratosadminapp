import {
  asDate,
  asNullableDate,
  asNullableInteger,
  asNullableString,
  asRecord,
  asString,
} from '@/utils/parsing';

export interface MembershipEvent {
  id: string;
  membershipId: string;
  eventType: string;
  at: Date;
  byUserId: string | null;
  byUserName: string | null;
  notes: string | null;
  deltaDays: number | null;
  deltaCents: number | null;
  oldStartDate: Date | null;
  oldEndDate: Date | null;
  newStartDate: Date | null;
  newEndDate: Date | null;
  planName: string | null;
}

export function parseMembershipEvent(value: unknown): MembershipEvent {
  const row = asRecord(value);
  return {
    id: asString(row.id),
    membershipId: asString(row.membership_id),
    eventType: asString(row.event_type),
    at: asDate(row.at),
    byUserId: asNullableString(row.by_user),
    byUserName: asNullableString(row.by_user_name),
    notes: asNullableString(row.notes),
    deltaDays: asNullableInteger(row.delta_days),
    deltaCents: asNullableInteger(row.delta_cents),
    oldStartDate: asNullableDate(row.old_start_date),
    oldEndDate: asNullableDate(row.old_end_date),
    newStartDate: asNullableDate(row.new_start_date),
    newEndDate: asNullableDate(row.new_end_date),
    planName: asNullableString(row.plan_name),
  };
}

export function membershipEventLabel(eventType: string): string {
  return (
    {
      created: 'Creat',
      extended: 'Prelungit',
      canceled: 'Anulat',
      paused: 'Înghețat',
      upgraded: 'Upgrade',
      edited: 'Editat',
      resumed: 'Reluat',
    }[eventType] ?? eventType
  );
}
