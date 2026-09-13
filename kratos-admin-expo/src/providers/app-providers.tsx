import { PowerSyncContext } from '@powersync/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import React from 'react';

import { powerSync } from '@/lib/powersync/system';
import { AuthProvider } from '@/providers/auth-provider';
import { SyncStatusProvider } from '@/providers/sync-status-provider';

const queryClient = new QueryClient({
  defaultOptions: {
    // Shared Flutter reports load on entry, filter changes and explicit refresh.
    // Replication itself does not reload their displayed snapshot.
    queries: { staleTime: 0, gcTime: 0, retry: false, refetchOnMount: 'always', refetchOnWindowFocus: false, refetchOnReconnect: false },
    mutations: { retry: 0 },
  },
});

export function AppProviders({ children }: React.PropsWithChildren) {
  return (
    <PowerSyncContext.Provider value={powerSync}>
      <QueryClientProvider client={queryClient}>
        <AuthProvider>
          <SyncStatusProvider>{children}</SyncStatusProvider>
        </AuthProvider>
      </QueryClientProvider>
    </PowerSyncContext.Provider>
  );
}
