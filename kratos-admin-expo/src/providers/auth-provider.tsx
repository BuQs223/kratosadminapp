import type { Session, User } from '@supabase/supabase-js';
import React from 'react';

import { connectPowerSyncIfAuthenticated, disconnectPowerSync } from '@/lib/powersync/system';
import { getSupabase } from '@/lib/supabase/client';
import { startSupabaseAutoRefresh } from '@/services/auth-service';

interface AuthState {
  isLoading: boolean;
  session: Session | null;
  user: User | null;
  error: Error | null;
}

const AuthContext = React.createContext<AuthState | null>(null);

export function AuthProvider({ children }: React.PropsWithChildren) {
  const [state, setState] = React.useState<AuthState>({
    isLoading: true,
    session: null,
    user: null,
    error: null,
  });

  React.useEffect(() => {
    const supabase = getSupabase();
    const stopAutoRefresh = startSupabaseAutoRefresh();
    let active = true;

    supabase.auth.getSession().then(({ data, error }) => {
      if (!active) return;
      if (error) {
        setState({ isLoading: false, session: null, user: null, error });
        return;
      }
      setState({
        isLoading: false,
        session: data.session,
        user: data.session?.user ?? null,
        error: null,
      });
      if (data.session) void connectPowerSyncIfAuthenticated();
    });

    const { data: subscription } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!active) return;
      setState({ isLoading: false, session, user: session?.user ?? null, error: null });
      queueMicrotask(() => {
        if (session) void connectPowerSyncIfAuthenticated();
        else void disconnectPowerSync();
      });
    });

    return () => {
      active = false;
      stopAutoRefresh();
      subscription.subscription.unsubscribe();
    };
  }, []);

  return <AuthContext value={state}>{children}</AuthContext>;
}

export function useAuth(): AuthState {
  const state = React.use(AuthContext);
  if (!state) throw new Error('useAuth must be used inside AuthProvider.');
  return state;
}
