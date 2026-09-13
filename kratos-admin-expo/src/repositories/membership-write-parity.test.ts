import { test, expect, jest, beforeEach, afterEach } from '@jest/globals';
import { deleteMembership, saveMembership, type SaveMembershipInput } from './members-repository';
import { saveMembershipPlan } from './membership-plans-repository';
import { flutterDateTimeIso, parseFlutterDate } from '@/utils/flutter-date';

type Call = { table: string; operation?: string; payload?: unknown; filters: unknown[][]; select?: string; cardinality?: string };
const mockCalls: Call[] = [];
const mockResponses: { data?: unknown; error?: unknown }[] = [];
const mockGetSession = jest.fn(async () => ({ data: { session: { user: { id: 'admin' } } } }));
jest.mock('@/lib/powersync/system', () => ({ powerSync: {}, connectPowerSyncIfAuthenticated: jest.fn() }));
jest.mock('@/lib/supabase/client', () => ({
  getSupabase: () => ({
    auth: { getSession: mockGetSession },
    from: (table: string) => {
      const call: Call = { table, filters: [] };
      mockCalls.push(call);
      const query = {
        insert(payload: unknown) { call.operation = 'insert'; call.payload = payload; return query; },
        update(payload: unknown) { call.operation = 'update'; call.payload = payload; return query; },
        delete() { call.operation = 'delete'; return query; },
        select(columns?: string) { call.select = columns; call.operation ??= 'select'; return query; },
        eq(column: string, value: unknown) { call.filters.push([column, value]); return query; },
        single() { call.cardinality = 'single'; return query; },
        maybeSingle() { call.cardinality = 'maybeSingle'; return query; },
        then(resolve: (result: unknown) => unknown, reject: (error: unknown) => unknown) {
          const response = mockResponses.shift();
          if (!response) throw new Error('Unexpected request');
          return Promise.resolve(response).then(resolve, reject);
        },
      };
      return query;
    },
  }),
}));

const input = (): SaveMembershipInput => ({
  memberId: 'member', planId: 'new-plan', gymId: 'new-gym',
  startDate: new Date(2026, 8, 13, 15, 30), endDate: new Date(2026, 9, 13, 15, 30),
  isActive: true, membershipType: 'monthly', pricePaidCents: 1999, paymentMethod: 'card',
});
beforeEach(() => { mockCalls.length = 0; mockResponses.length = 0; mockGetSession.mockClear(); });
afterEach(() => expect(mockResponses).toHaveLength(0));

test('new membership writes Flutter fields, then a charge with server defaults and current recorder', async () => {
  mockResponses.push({ data: { id: 'server-id' } }, {});
  expect(await saveMembership(input())).toBe('server-id');
  expect(mockCalls).toEqual([
    { table: 'memberships', operation: 'insert', filters: [], select: 'id', cardinality: 'single', payload: { user_id: 'member', plan_id: 'new-plan', sold_at_gym_id: 'new-gym', start_date: '2026-09-13T15:30:00.000', end_date: '2026-10-13T15:30:00.000', is_active: true, membership_type: 'monthly', price_paid_cents: 1999, payment_method: 'card' } },
    { table: 'revenue_ledger', operation: 'insert', filters: [], payload: { membership_id: 'server-id', plan_id: 'new-plan', gym_id: 'new-gym', amount_cents: 1999, currency: 'RON', source: 'membership', entry_kind: 'charge', payment_method: 'card', recorded_by: 'admin' } },
  ]);
});

test('same-price edits never read or change the ledger even when plan/gym/payment change', async () => {
  mockResponses.push({});
  await saveMembership({ ...input(), membershipId: 'existing', originalPricePaidCents: 1999 });
  expect(mockCalls).toHaveLength(1);
  expect(mockCalls[0]).toMatchObject({ table: 'memberships', operation: 'update', filters: [['id', 'existing']] });
  expect(mockGetSession).not.toHaveBeenCalled();
});

test('price changes select any membership ledger row and only update amount, payment and gym', async () => {
  mockResponses.push({}, { data: { id: 'old-deleted-or-refund-row' } }, {});
  await saveMembership({ ...input(), membershipId: 'existing', originalPricePaidCents: 1000 });
  expect(mockCalls[1]).toEqual({ table: 'revenue_ledger', operation: 'select', select: 'id', cardinality: 'maybeSingle', filters: [['membership_id', 'existing']] });
  expect(mockCalls[2]).toEqual({ table: 'revenue_ledger', operation: 'update', filters: [['id', 'old-deleted-or-refund-row']], payload: { amount_cents: 1999, payment_method: 'card', gym_id: 'new-gym' } });
});

test('a missing ledger row is inserted on a price change', async () => {
  mockResponses.push({}, { data: null }, {});
  await saveMembership({ ...input(), membershipId: 'existing', originalPricePaidCents: 1000 });
  expect(mockCalls[2]).toMatchObject({ table: 'revenue_ledger', operation: 'insert', payload: { membership_id: 'existing', plan_id: 'new-plan', amount_cents: 1999 } });
});

test('an ambiguous ledger fails after the membership update, without rollback or reconciliation RPC', async () => {
  const error = new Error('Multiple rows');
  mockResponses.push({}, { error });
  await expect(saveMembership({ ...input(), membershipId: 'existing', originalPricePaidCents: 1000 })).rejects.toBe(error);
  expect(mockCalls.map(call => call.operation)).toEqual(['update', 'select']);
});

test('retrying a failed new charge creates another membership, just like the Flutter form', async () => {
  const error = new Error('Ledger rejected');
  mockResponses.push({ data: { id: 'first' } }, { error }, { data: { id: 'second' } }, {});
  await expect(saveMembership(input())).rejects.toBe(error);
  expect(await saveMembership(input())).toBe('second');
  expect(mockCalls.filter(call => call.table === 'memberships').map(call => call.operation)).toEqual(['insert', 'insert']);
  expect(mockCalls[3]).toMatchObject({ payload: { membership_id: 'second' } });
});

test('parsed UTC dates and microseconds survive an untouched membership edit', async () => {
  mockResponses.push({});
  await saveMembership({ ...input(), membershipId: 'existing', originalPricePaidCents: 1999, startDate: parseFlutterDate('2026-09-13T00:30:00.123456+03:00') });
  expect(mockCalls[0]).toMatchObject({ payload: { start_date: '2026-09-12T21:30:00.123456Z' } });
});

test('delete uses the Flutter order and no extra dependent tables', async () => {
  mockResponses.push({}, {}, {});
  await deleteMembership('membership');
  expect(mockCalls).toEqual([
    { table: 'revenue_ledger', operation: 'delete', filters: [['membership_id', 'membership']] },
    { table: 'check_ins', operation: 'delete', filters: [['membership_id', 'membership']] },
    { table: 'memberships', operation: 'delete', filters: [['id', 'membership']] },
  ]);
});

test('delete stops at the first failed stage', async () => {
  const error = new Error('Check-in delete failed');
  mockResponses.push({}, { error });
  await expect(deleteMembership('membership')).rejects.toBe(error);
  expect(mockCalls.map(call => call.table)).toEqual(['revenue_ledger', 'check_ins']);
});

test('plan save preserves name/tier/durations and uses a local offset-free updated_at', async () => {
  jest.useFakeTimers().setSystemTime(new Date(2026, 8, 13, 15, 30));
  mockResponses.push({});
  await saveMembershipPlan({ name: '  Original name  ', tier: 'Platinum', gymId: null, monthlyPriceCents: 1998, isActive: true, isFamilyPlan: false, isGoodMorning: false, durationMonths: -1, durationDays: 0 }, 'plan');
  expect(mockCalls[0]).toMatchObject({ table: 'membership_plans', operation: 'update', filters: [['id', 'plan']], payload: { name: '  Original name  ', tier: 'Platinum', duration_months: -1, monthly_price_cents: 1998, updated_at: flutterDateTimeIso(new Date()) } });
  expect(mockCalls[0].select).toBeUndefined();
  jest.useRealTimers();
});
