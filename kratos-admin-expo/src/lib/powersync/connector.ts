import type {
  CommonPowerSyncDatabase,
  PowerSyncBackendConnector,
  PowerSyncCredentials,
} from '@powersync/react-native';

import { getClientConfig } from '@/lib/config';
import { getSupabase } from '@/lib/supabase/client';
import { freezeUploadPayload } from '@/lib/powersync/freeze-upload';

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

    // Validate the entire batch before sending anything. Stable row IDs make a
    // retry after an interrupted upload safe for events and schedules as well.
    const operations = transaction.crud.map((op) => ({ op, payload: freezeUploadPayload(op) }));
    for (const { op, payload } of operations) {
      const table = getSupabase().from(op.table);
      const { error } = op.op === 'PUT'
        ? await table.upsert({ ...payload, id: op.id }).select('id').single()
        : await table.update(payload).eq('id', op.id).select('id').single();
      if (error) throw error;
    }
    await transaction.complete();
  }
}
