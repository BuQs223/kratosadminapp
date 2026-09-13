import { describe, expect, jest, test } from '@jest/globals';
import { getSyncDisplayState } from '@/providers/sync-status-provider';

jest.mock('@/lib/powersync/system', () => ({
  powerSync: {},
  retryPowerSyncConnection: jest.fn(),
}));

jest.mock('@/lib/powersync/sync-status-storage', () => ({
  readLastSuccessfulSync: jest.fn(),
  writeLastSuccessfulSync: jest.fn(),
}));

jest.mock('@/providers/auth-provider', () => ({
  useAuth: jest.fn(),
}));

describe('getSyncDisplayState', () => {
  test('does not treat an open transport as a completed initial sync', () => {
    const state = getSyncDisplayState({
      connected: true,
      connecting: false,
      downloading: false,
      downloadProgress: null,
      downloadError: undefined,
      hasSynced: false,
    }, true);

    expect(state).toEqual({ kind: 'connecting' });
  });

  test('allows the launch flow to finish only after PowerSync confirms a full sync', () => {
    const state = getSyncDisplayState({
      connected: true,
      connecting: false,
      downloading: false,
      downloadProgress: null,
      downloadError: undefined,
      hasSynced: true,
    }, true);

    expect(state).toEqual({ kind: 'hidden' });
  });
});
