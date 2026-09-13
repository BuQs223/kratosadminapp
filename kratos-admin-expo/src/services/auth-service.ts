import { AppState } from 'react-native';

import { connectPowerSyncIfAuthenticated, disconnectPowerSync } from '@/lib/powersync/system';
import { getSupabase } from '@/lib/supabase/client';

export const authService = {
  get currentUser() {
    return getSupabase().auth.getUser();
  },

  async signIn(email: string, password: string) {
    const result = await getSupabase().auth.signInWithPassword({ email, password });
    if (result.error) throw result.error;
    await connectPowerSyncIfAuthenticated();
    return result.data;
  },

  async signOut() {
    await disconnectPowerSync();
    const { error } = await getSupabase().auth.signOut();
    if (error) throw error;
  },
};

let autoRefreshSubscription: ReturnType<typeof AppState.addEventListener> | null = null;

export function startSupabaseAutoRefresh() {
  if (process.env.EXPO_OS === 'web' || autoRefreshSubscription) return () => undefined;
  const supabase = getSupabase();

  if (AppState.currentState === 'active') supabase.auth.startAutoRefresh();
  autoRefreshSubscription = AppState.addEventListener('change', (state) => {
    if (state === 'active') supabase.auth.startAutoRefresh();
    else supabase.auth.stopAutoRefresh();
  });

  return () => {
    autoRefreshSubscription?.remove();
    autoRefreshSubscription = null;
    supabase.auth.stopAutoRefresh();
  };
}
