import { connectPowerSyncIfAuthenticated, powerSync } from '@/lib/powersync/system';
import { asRecord, asRecords, asString } from '@/utils/parsing';

export interface LookupOption {
  id: string;
  name: string;
}

function option(value: unknown): LookupOption {
  const row = asRecord(value);
  return { id: asString(row.id), name: asString(row.name) };
}

export const lookupsRepository = {
  async getGyms(): Promise<LookupOption[]> {
    await connectPowerSyncIfAuthenticated();
    return asRecords(
      await powerSync.getAll('SELECT id, name FROM gyms ORDER BY name COLLATE NOCASE'),
    ).map(option);
  },

  async getActiveMembershipPlans(): Promise<LookupOption[]> {
    await connectPowerSyncIfAuthenticated();
    return asRecords(
      await powerSync.getAll(`
        SELECT id, name
        FROM membership_plans
        WHERE COALESCE(is_active, 0) = 1
        ORDER BY name COLLATE NOCASE
      `),
    ).map(option);
  },
};
