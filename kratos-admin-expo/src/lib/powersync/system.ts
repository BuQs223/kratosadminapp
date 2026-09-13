import { PowerSyncDatabase } from '@powersync/react-native';

import { KratosPowerSyncConnector } from '@/lib/powersync/connector';
import { appSchema } from '@/lib/powersync/schema';
import { getSupabase } from '@/lib/supabase/client';

export const powerSync = new PowerSyncDatabase({
  schema: appSchema,
  database: { dbFilename: 'kratos-powersync.db' },
});

const connector = new KratosPowerSyncConnector();
let initialization: Promise<void> | null = null;
let connection: Promise<void> | null = null;
let reconnect: Promise<void> | null = null;

export function initializePowerSync(): Promise<void> {
  initialization ??= powerSync.init();
  return initialization;
}

export async function connectPowerSyncIfAuthenticated(): Promise<void> {
  if (connection) return connection;

  connection = (async () => {
    await initializePowerSync();
    const { data, error } = await getSupabase().auth.getSession();
    if (error) throw error;
    if (!data.session) {
      connection = null;
      return;
    }
    await powerSync.connect(connector);
  })().catch((error: unknown) => {
    connection = null;
    throw error;
  });

  await connection;
}

export async function disconnectPowerSync(): Promise<void> {
  if (!initialization) return;
  connection = null;
  await powerSync.disconnect();
}

/** Forces a reconnect without touching the local SQLite database or its cache. */
export async function retryPowerSyncConnection(): Promise<void> {
  if (reconnect) return reconnect;
  reconnect = (async () => {
    await disconnectPowerSync();
    connection = null;
    await connectPowerSyncIfAuthenticated();
  })().finally(() => {
    reconnect = null;
  });
  return reconnect;
}
