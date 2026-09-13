import * as SecureStore from 'expo-secure-store';

const lastSuccessfulSyncKey = 'kratos.sync.last_successful_at';

export async function readLastSuccessfulSync(): Promise<Date | undefined> {
  if (process.env.EXPO_OS === 'web') return undefined;
  const value = await SecureStore.getItemAsync(lastSuccessfulSyncKey);
  if (!value) return undefined;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

export async function writeLastSuccessfulSync(value: Date): Promise<void> {
  if (process.env.EXPO_OS === 'web') return;
  await SecureStore.setItemAsync(lastSuccessfulSyncKey, value.toISOString());
}
