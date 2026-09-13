import { beforeEach, expect, jest, test } from '@jest/globals';
import type { CommonPowerSyncDatabase, CrudEntry, UpdateType } from '@powersync/react-native';
import { KratosPowerSyncConnector } from './connector';
import { freezeUploadPayload } from './freeze-upload';

const mockCalls: { table: string; operation: string; payload: unknown; id?: string }[] = [];
const mockResponses: { error?: Error; data?: unknown }[] = [];
jest.mock('@/lib/supabase/client', () => ({ getSupabase: () => ({
  from: (table: string) => {
    const call = { table, operation: '', payload: undefined as unknown, id: undefined as string | undefined };
    mockCalls.push(call);
    const query = {
      update: (payload: unknown) => { call.operation = 'update'; call.payload = payload; return query; },
      upsert: (payload: unknown) => { call.operation = 'upsert'; call.payload = payload; return query; },
      eq: (_column: string, id: string) => { call.id = id; return query; },
      select: () => query,
      single: async () => {
        const response = mockResponses.shift();
        if (!response) throw new Error('Unexpected upload request');
        return response;
      },
    };
    return query;
  },
}) }));
const entry = (table: string, op: string, opData: Record<string, unknown>, id = 'membership') => ({ table, op: op as UpdateType, opData, id }) as CrudEntry;
beforeEach(() => { mockCalls.length = 0; mockResponses.length = 0; });

test('resume uploads a boolean and explicit nulls to clear server freeze state', () => {
  expect(freezeUploadPayload(entry('memberships', 'PATCH', { is_frozen: 0, frozen_at: null, days_left_when_frozen: null, freeze_type: null, auto_unfreeze_at: null })))
    .toEqual({ is_frozen: false, frozen_at: null, days_left_when_frozen: null, freeze_type: null, auto_unfreeze_at: null });
  expect(freezeUploadPayload(entry('memberships', 'PATCH', { is_frozen: 1 }))).toEqual({ is_frozen: true });
});

test('a failed event upload retains the batch and retries stable IDs without duplicating history', async () => {
  const complete = jest.fn(async () => {});
  const crud = [entry('memberships', 'PATCH', { is_frozen: 1 }), entry('membership_events', 'PUT', { membership_id: 'membership', event_type: 'paused', by_user: 'admin' }, 'event-id')];
  const database = { getNextCrudTransaction: async () => ({ crud, complete }) } as unknown as CommonPowerSyncDatabase;
  const connector = new KratosPowerSyncConnector();
  mockResponses.push({}, { error: new Error('network failed') });
  await expect(connector.uploadData(database)).rejects.toThrow('network failed');
  expect(complete).not.toHaveBeenCalled();
  mockResponses.push({}, {});
  await connector.uploadData(database);
  expect(complete).toHaveBeenCalledTimes(1);
  expect(mockCalls[1]).toEqual(mockCalls[3]);
  expect(mockCalls[3]).toMatchObject({ table: 'membership_events', operation: 'upsert', payload: { id: 'event-id' } });
});

test('unknown local mutations are rejected before any remote request', async () => {
  const complete = jest.fn(async () => {});
  const crud = [entry('memberships', 'PATCH', { is_frozen: 1 }), entry('revenue_ledger', 'PUT', { amount_cents: 200 })];
  const database = { getNextCrudTransaction: async () => ({ crud, complete }) } as unknown as CommonPowerSyncDatabase;
  await expect(new KratosPowerSyncConnector().uploadData(database)).rejects.toThrow('Unsupported local write');
  expect(mockCalls).toEqual([]);
  expect(complete).not.toHaveBeenCalled();
});

test('schedule creation and cancellation use the same stable schedule record', async () => {
  const complete = jest.fn(async () => {});
  const crud = [entry('membership_freeze_schedules', 'PUT', { membership_id: 'membership', duration_days: 5, status: 'pending' }, 'schedule'),
    entry('membership_freeze_schedules', 'PATCH', { status: 'canceled', canceled_by_user_id: 'admin' }, 'schedule')];
  const database = { getNextCrudTransaction: async () => ({ crud, complete }) } as unknown as CommonPowerSyncDatabase;
  mockResponses.push({}, {});
  await new KratosPowerSyncConnector().uploadData(database);
  expect(mockCalls[0]).toMatchObject({ operation: 'upsert', payload: { id: 'schedule' } });
  expect(mockCalls[1]).toMatchObject({ operation: 'update', id: 'schedule', payload: { status: 'canceled' } });
  expect(complete).toHaveBeenCalledTimes(1);
});
