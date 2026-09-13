import type { NetInfoState } from '@react-native-community/netinfo';
import type { SyncStatus } from '@powersync/react-native';
import React from 'react';
import { retryPowerSyncConnection, powerSync } from '@/lib/powersync/system';
import { readLastSuccessfulSync, writeLastSuccessfulSync } from '@/lib/powersync/sync-status-storage';
import { useAuth } from '@/providers/auth-provider';

export type SyncDisplayState =
  | { kind: 'hidden' }
  | { kind: 'connecting' }
  | { kind: 'downloading'; fraction?: number; downloaded?: number; total?: number }
  | { kind: 'complete'; completedAt: Date }
  | { kind: 'offline'; lastSuccessfulAt?: Date }
  | { kind: 'error'; message: string; lastSuccessfulAt?: Date };

interface SyncStatusContextValue {
  state: SyncDisplayState;
  retry: () => Promise<void>;
  isRetrying: boolean;
  isInitialSyncSettled: boolean;
  continueWithCachedData: () => void;
}

const SyncStatusContext = React.createContext<SyncStatusContextValue | null>(null);

type NetInfoSubscription = (listener: (state: NetInfoState) => void) => () => void;

/**
 * A development build created before NetInfo was installed does not contain
 * RNCNetInfo. Keep local data and navigation usable in that stale binary; a
 * freshly built client automatically enables the offline/server distinction.
 */
function loadNetInfoSubscription(): NetInfoSubscription | undefined {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports -- the native module may be absent from an old development binary.
    const loaded = require('@react-native-community/netinfo') as {
      default?: { addEventListener?: NetInfoSubscription };
      addEventListener?: NetInfoSubscription;
    };
    return loaded.default?.addEventListener ?? loaded.addEventListener;
  } catch {
    return undefined;
  }
}

const subscribeToNetInfo = loadNetInfoSubscription();

function sanitizeSyncError(error: Error | undefined): string {
  if (!error) return 'Sincronizarea nu este disponibilă momentan.';
  const withoutUrls = error.message.replace(/https?:\/\/\S+/gi, '[adresă ascunsă]');
  const withoutTokens = withoutUrls.replace(/(token|authorization|apikey|key)=?\s*[^\s,;]+/gi, '$1=[ascuns]');
  return withoutTokens.slice(0, 180) || 'Sincronizarea nu este disponibilă momentan.';
}

export function getSyncDisplayState(
  status: Pick<SyncStatus, 'connecting' | 'connected' | 'downloading' | 'downloadProgress' | 'downloadError' | 'hasSynced'>,
  online: boolean | null,
  lastSuccessfulAt?: Date,
): SyncDisplayState {
  if (status.downloadError) {
    return online === false
      ? { kind: 'offline', lastSuccessfulAt }
      : { kind: 'error', message: sanitizeSyncError(status.downloadError), lastSuccessfulAt };
  }
  if (status.downloading) {
    const progress = status.downloadProgress;
    return {
      kind: 'downloading',
      fraction: progress?.downloadedFraction,
      downloaded: progress?.downloadedOperations,
      total: progress?.totalOperations,
    };
  }
  if (status.connecting) return { kind: 'connecting' };
  if (!status.connected && online === false) return { kind: 'offline', lastSuccessfulAt };
  // Opening the transport is not the same as having a complete local dataset.
  // In particular, a freshly installed app may be connected before its first
  // full sync starts, so keep the launch screen up until PowerSync confirms it.
  if (status.connected && status.hasSynced !== true) return { kind: 'connecting' };
  return { kind: 'hidden' };
}

export function SyncStatusProvider({ children }: React.PropsWithChildren) {
  const { session } = useAuth();
  const sessionUserId = session?.user.id ?? null;
  const [lastSuccessfulAt, setLastSuccessfulAt] = React.useState<Date | undefined>();
  const [online, setOnline] = React.useState<boolean | null>(null);
  const [state, setState] = React.useState<SyncDisplayState>({ kind: 'hidden' });
  const [isRetrying, setIsRetrying] = React.useState(false);
  const [settledSessionId, setSettledSessionId] = React.useState<string | null>(null);
  const previousDownloading = React.useRef(false);
  const completionTimer = React.useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const lastSuccessfulAtRef = React.useRef<Date | undefined>(undefined);
  const sessionUserIdRef = React.useRef<string | null>(null);

  React.useEffect(() => {
    lastSuccessfulAtRef.current = lastSuccessfulAt;
  }, [lastSuccessfulAt]);

  React.useEffect(() => {
    sessionUserIdRef.current = sessionUserId;
    if (!sessionUserId) previousDownloading.current = false;
  }, [sessionUserId]);

  React.useEffect(() => {
    void readLastSuccessfulSync().then(setLastSuccessfulAt);
    if (!subscribeToNetInfo) return;
    const unsubscribe = subscribeToNetInfo((next) => {
      setOnline(next.isInternetReachable ?? next.isConnected ?? null);
    });
    return unsubscribe;
  }, []);

  React.useEffect(() => {
    const markInitialSyncSettled = () => {
      const activeSessionId = sessionUserIdRef.current;
      if (activeSessionId) setSettledSessionId(activeSessionId);
    };

    const update = (status: SyncStatus) => {
      if (!sessionUserId) return;

      const completedAt = status.lastSyncedAt;
      if (completedAt && completedAt.getTime() !== lastSuccessfulAtRef.current?.getTime()) {
        setLastSuccessfulAt(completedAt);
        void writeLastSuccessfulSync(completedAt);
      }

      const isDownloading = status.downloading || status.connecting;
      if (previousDownloading.current && !isDownloading && completedAt) {
        if (completionTimer.current) clearTimeout(completionTimer.current);
        setState({ kind: 'complete', completedAt });
        completionTimer.current = setTimeout(() => {
          completionTimer.current = undefined;
          setState({ kind: 'hidden' });
          markInitialSyncSettled();
        }, 550);
      } else if (completionTimer.current && !isDownloading) {
        // Keep the brief success state visible until the launch screen closes.
      } else {
        if (completionTimer.current) {
          clearTimeout(completionTimer.current);
          completionTimer.current = undefined;
        }
        const next = getSyncDisplayState(status, online, completedAt ?? lastSuccessfulAtRef.current);
        if (next.kind === 'hidden' && status.hasSynced === true) {
          setState(next);
          markInitialSyncSettled();
        } else {
          setState(next);
        }
      }
      previousDownloading.current = isDownloading;
    };
    const dispose = powerSync.registerListener({ statusChanged: update });
    update(powerSync.currentStatus);
    return dispose;
  }, [online, sessionUserId]);

  React.useEffect(() => () => {
    if (completionTimer.current) clearTimeout(completionTimer.current);
  }, []);

  const retry = React.useCallback(async () => {
    setIsRetrying(true);
    try {
      await retryPowerSyncConnection();
    } finally {
      setIsRetrying(false);
    }
  }, []);

  const continueWithCachedData = React.useCallback(() => {
    const activeSessionId = sessionUserIdRef.current;
    if (activeSessionId) setSettledSessionId(activeSessionId);
  }, []);

  const isInitialSyncSettled = !sessionUserId || settledSessionId === sessionUserId;
  const value = React.useMemo(
    () => ({ state, retry, isRetrying, isInitialSyncSettled, continueWithCachedData }),
    [continueWithCachedData, isInitialSyncSettled, isRetrying, retry, state],
  );
  return <SyncStatusContext value={value}>{children}</SyncStatusContext>;
}

export function useSyncStatus(): SyncStatusContextValue {
  const value = React.use(SyncStatusContext);
  if (!value) throw new Error('useSyncStatus must be used inside SyncStatusProvider.');
  return value;
}
