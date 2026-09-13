import { parseGym, type Gym } from '@/models/gym';
import { parseMembership, type Membership } from '@/models/membership';
import { parseProfile, type Profile } from '@/models/profile';
import {
  asBoolean,
  asDate,
  asNullableDate,
  asNullableInteger,
  asNullableString,
  asRecord,
  asString,
} from '@/utils/parsing';

export interface CheckIn {
  id: string;
  userId: string;
  gymId: string;
  membershipId: string | null;
  checkedInAt: Date;
  checkedOutAt: Date | null;
  notes: string | null;
  status: string | null;
  message: string | null;
  daysLeft: number | null;
  shownToUser: boolean | null;
  profile: Profile | null;
  gym: Gym | null;
  membership: Membership | null;
}

export function parseCheckIn(value: unknown): CheckIn {
  const row = asRecord(value);
  const checkedInAt = row.checked_in_at ?? row.created_at;
  if (!checkedInAt) throw new Error('No valid timestamp found for check-in');

  return {
    id: asString(row.id),
    userId: asString(row.user_id),
    gymId: asString(row.gym_id),
    membershipId: asNullableString(row.membership_id),
    checkedInAt: asDate(checkedInAt),
    checkedOutAt: asNullableDate(row.checked_out_at),
    notes: asNullableString(row.notes),
    status: asNullableString(row.status),
    message: asNullableString(row.message),
    daysLeft: asNullableInteger(row.days_left),
    shownToUser:
      row.shown_to_user === null || row.shown_to_user === undefined
        ? null
        : asBoolean(row.shown_to_user),
    profile: row.profiles || row.profile ? parseProfile(row.profiles ?? row.profile) : null,
    gym: row.gyms || row.gym ? parseGym(row.gyms ?? row.gym) : null,
    membership:
      row.memberships || row.membership
        ? parseMembership(row.memberships ?? row.membership)
        : null,
  };
}

export function checkInDuration(checkIn: CheckIn): string | null {
  if (!checkIn.checkedOutAt) return null;
  const minutes = Math.floor(
    (checkIn.checkedOutAt.getTime() - checkIn.checkedInAt.getTime()) / 60_000,
  );
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return hours > 0 ? `${hours}h ${remainingMinutes}m` : `${remainingMinutes}m`;
}
