export interface ClientConfig {
  supabaseUrl: string;
  supabaseAnonKey: string;
  powerSyncUrl: string;
}

export class AppConfigurationError extends Error {
  constructor(readonly missingKeys: string[]) {
    super(`Missing app configuration: ${missingKeys.join(', ')}`);
    this.name = 'AppConfigurationError';
  }
}

export function getClientConfig(): ClientConfig {
  const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;
  const powerSyncUrl =
    process.env.EXPO_PUBLIC_POWERSYNC_URL || 'https://sync.kratosgym.ro';

  const missingKeys = [
    !supabaseUrl && 'EXPO_PUBLIC_SUPABASE_URL',
    !supabaseAnonKey && 'EXPO_PUBLIC_SUPABASE_ANON_KEY',
  ].filter((key): key is string => Boolean(key));

  if (missingKeys.length) throw new AppConfigurationError(missingKeys);
  return { supabaseUrl: supabaseUrl!, supabaseAnonKey: supabaseAnonKey!, powerSyncUrl };
}
