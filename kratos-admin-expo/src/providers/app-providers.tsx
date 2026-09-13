import { PowerSyncContext } from '@powersync/react';
import { QueryClient, QueryClientProvider, useQueryClient } from '@tanstack/react-query';
import React from 'react';

import { initializePowerSync, powerSync } from '@/lib/powersync/system';
import { AuthProvider } from '@/providers/auth-provider';
import { SyncStatusProvider, useSyncStatus } from '@/providers/sync-status-provider';
import { SyncLaunchScreen } from '@/components/sync-launch-screen';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 30_000, retry: 2 },
    mutations: { retry: 0 },
  },
});

const queryGroups: { tables: string[]; queryKeys: readonly (readonly unknown[])[] }[] = [
  {
    tables: ['profiles', 'memberships', 'family_memberships', 'membership_plans'],
    queryKeys: [['members'], ['member-detail'], ['dashboard-stats'], ['membership-form-options'], ['member-filter-lookups'], ['membership-plan-lookups'], ['membership-plans-admin']],
  },
  { tables: ['membership_events'], queryKeys: [['member-history'], ['member-detail']] },
  { tables: ['check_ins'], queryKeys: [['check-ins'], ['check-in-stats'], ['gold-check-ins'], ['member-detail'], ['dashboard-stats']] },
  { tables: ['revenue_ledger'], queryKeys: [['revenue'], ['revenue-today-comparison'], ['revenue-analytics'], ['revenue-period-comparison'], ['member-revenue-history'], ['member-detail'], ['dashboard-stats']] },
  { tables: ['gyms'], queryKeys: [['gym-lookups'], ['member-filter-lookups'], ['membership-form-options'], ['membership-plan-lookups'], ['membership-plans-admin']] },
  { tables: ['admin_analytics_summary'], queryKeys: [['dashboard-stats']] },
];

function PowerSyncQueryBridge() {
  const activeQueryClient = useQueryClient();

  React.useEffect(() => {
    let active = true;
    const timers = new Map<number, ReturnType<typeof setTimeout>>();
    const disposers: (() => void)[] = [];

    void initializePowerSync().then(() => {
      if (!active) return;
      queryGroups.forEach((group, groupIndex) => {
        const schedule = () => {
          const existing = timers.get(groupIndex);
          if (existing) clearTimeout(existing);
          timers.set(groupIndex, setTimeout(() => {
            group.queryKeys.forEach((queryKey) => {
              void activeQueryClient.invalidateQueries({ queryKey: [...queryKey] });
            });
          }, 150));
        };
        disposers.push(powerSync.onChange({ onChange: schedule }, { tables: group.tables }));
      });
    });

    return () => {
      active = false;
      disposers.forEach((dispose) => dispose());
      timers.forEach((timer) => clearTimeout(timer));
    };
  }, [activeQueryClient]);

  return null;
}

export function AppProviders({ children }: React.PropsWithChildren) {
  return (
    <PowerSyncContext.Provider value={powerSync}>
      <QueryClientProvider client={queryClient}>
        <PowerSyncQueryBridge />
        <AuthProvider>
          <SyncStatusProvider>
            <SyncLaunchGate>{children}</SyncLaunchGate>
          </SyncStatusProvider>
        </AuthProvider>
      </QueryClientProvider>
    </PowerSyncContext.Provider>
  );
}

function SyncLaunchGate({ children }: React.PropsWithChildren) {
  const { state, retry, isRetrying, isInitialSyncSettled, continueWithCachedData } = useSyncStatus();

  if (isInitialSyncSettled) return children;
  return (
    <SyncLaunchScreen
      state={state}
      isRetrying={isRetrying}
      onRetry={() => void retry()}
      onContinueWithCachedData={continueWithCachedData}
    />
  );
}
