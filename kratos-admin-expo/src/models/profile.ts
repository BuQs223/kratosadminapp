import {
  asBoolean,
  asDate,
  asNullableDate,
  asNullableString,
  asRecord,
  asString,
} from '@/utils/parsing';

export interface Profile {
  id: string;
  email: string;
  fullName: string;
  phoneNumber: string | null;
  avatarUrl: string | null;
  role: string;
  isAdmin: boolean;
  isEmployee: boolean;
  createdAt: Date;
  updatedAt: Date | null;
}

export function parseProfile(value: unknown): Profile {
  const row = asRecord(value);
  return {
    id: asString(row.id),
    email: asString(row.email),
    fullName: asString(row.full_name),
    phoneNumber: asNullableString(row.phone ?? row.phone_number),
    avatarUrl: asNullableString(row.avatar_url),
    role: asString(row.role, 'client'),
    isAdmin: asBoolean(row.is_admin),
    isEmployee: asBoolean(row.is_employee),
    createdAt: asDate(row.created_at),
    updatedAt: asNullableDate(row.updated_at),
  };
}

export function serializeProfile(profile: Profile) {
  return {
    id: profile.id,
    email: profile.email,
    full_name: profile.fullName,
    phone: profile.phoneNumber,
    phone_number: profile.phoneNumber,
    avatar_url: profile.avatarUrl,
    role: profile.role,
    is_admin: profile.isAdmin,
    is_employee: profile.isEmployee,
    created_at: profile.createdAt.toISOString(),
    updated_at: profile.updatedAt?.toISOString() ?? null,
  };
}
