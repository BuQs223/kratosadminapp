import type {
  CommonPowerSyncDatabase,
  PowerSyncBackendConnector,
  PowerSyncCredentials,
} from '@powersync/react-native';

import { getClientConfig } from '@/lib/config';
import { getSupabase } from '@/lib/supabase/client';

export class KratosPowerSyncConnector implements PowerSyncBackendConnector {
  async fetchCredentials(): Promise<PowerSyncCredentials | null> {
    const { data, error } = await getSupabase().auth.getSession();
    if (error) throw error;
    if (!data.session) return null;

    return {
      endpoint: getClientConfig().powerSyncUrl,
      token: data.session.access_token,
      expiresAt: data.session.expires_at
        ? new Date(data.session.expires_at * 1000)
        : undefined,
    };
  }

  async uploadData(database: CommonPowerSyncDatabase): Promise<void> {
    const transaction = await database.getNextCrudTransaction();
    if (!transaction) return;

    // This mirrors the Flutter app: reads are local-first, while every write path
    // remains an explicit Supabase mutation until CRUD upload mappings are defined.
    throw new Error(
      'A local PowerSync write was queued without an upload mapping. Use a Supabase repository mutation.',
    );
  }
}
