import {
  asBoolean,
  asDate,
  asNullableString,
  asRecord,
  asString,
} from '@/utils/parsing';

export interface Gym {
  id: string;
  name: string;
  address: string | null;
  phoneNumber: string | null;
  emailAddress: string | null;
  cityName: string | null;
  isActive: boolean;
  createdAt: Date;
}

export function parseGym(value: unknown): Gym {
  const row = asRecord(value);
  return {
    id: asString(row.id),
    name: asString(row.name, 'Unknown Gym'),
    address: asNullableString(row.address),
    phoneNumber: asNullableString(row.phone_number ?? row.phone),
    emailAddress: asNullableString(row.email),
    cityName: asNullableString(row.city),
    isActive: asBoolean(row.is_active, true),
    createdAt: asDate(row.created_at),
  };
}

export function serializeGym(gym: Gym) {
  return {
    id: gym.id,
    name: gym.name,
    address: gym.address,
    phone_number: gym.phoneNumber,
    email: gym.emailAddress,
    city: gym.cityName,
    is_active: gym.isActive,
    created_at: gym.createdAt.toISOString(),
  };
}
