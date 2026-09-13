import { afterEach, beforeEach, expect, jest, test } from '@jest/globals';
import { fireEvent, render, waitFor } from '@testing-library/react-native';
import { notifyManager, onlineManager, QueryClient, QueryClientProvider } from '@tanstack/react-query';
import React from 'react';
import { MembershipFreezeSheet } from './membership-freeze-sheet';
import type { FreezeAction, FreezeData } from '@/repositories/membership-freeze-repository';

const mockGetData = jest.fn<() => Promise<FreezeData>>();
const mockApply = jest.fn<(memberId: string, action: FreezeAction) => Promise<void>>();
jest.mock('@/lib/powersync/system', () => ({ powerSync: {}, connectPowerSyncIfAuthenticated: async () => {} }));
jest.mock('@/lib/supabase/client', () => ({ getSupabase: jest.fn() }));
jest.mock('@/repositories/membership-freeze-repository', () => ({
  ...jest.requireActual<typeof import('@/repositories/membership-freeze-repository')>('@/repositories/membership-freeze-repository'),
  getFreezeData: () => mockGetData(),
  applyFreezeAction: (memberId: string, action: FreezeAction) => mockApply(memberId, action),
}));
jest.mock('@/components/bottom-sheet-modal', () => ({ BottomSheetModal: ({ children }: React.PropsWithChildren) => children }));
jest.mock('@gorhom/bottom-sheet', () => ({ BottomSheetScrollView: ({ children }: React.PropsWithChildren) => children }));
jest.mock('@/components/calendar-dialog', () => ({ SingleDateDialog: () => null }));

const fixture = (duration = 1): FreezeData => ({ memberships: [{
  id: 'membership', user_id: 'client', plan_id: 'plan', plan_name: 'Gold', duration_months: duration,
  plan_duration_months: 3, is_active: 1, is_frozen: 0, canceled_at: null,
  start_date: '2026-01-01', end_date: '2090-12-31', days_left: 17, days_left_when_frozen: null,
  freeze_type: null, auto_unfreeze_at: null,
}], schedules: [] });

const clients: QueryClient[] = [];
beforeEach(() => {
  mockGetData.mockReset(); mockApply.mockReset();
  notifyManager.setScheduler((callback) => callback());
});
afterEach(() => {
  for (const client of clients.splice(0)) client.clear();
  onlineManager.setOnline(true);
  notifyManager.setScheduler((callback) => { setTimeout(callback, 0); });
});
async function setup() {
  const onClose = jest.fn();
  const onSaved = jest.fn();
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 }, mutations: { retry: false, gcTime: 0 } } });
  clients.push(client);
  const screen = await render(<QueryClientProvider client={client}><MembershipFreezeSheet memberId="client" onClose={onClose} onSaved={onSaved} /></QueryClientProvider>);
  return { screen, onClose, onSaved };
}

test('one-month membership hides 14 days; a failed save keeps the choice and retry saves once', async () => {
  mockGetData.mockResolvedValue(fixture());
  mockApply.mockRejectedValueOnce(new Error('Salvarea a eșuat')).mockResolvedValueOnce(undefined);
  const { screen, onClose, onSaved } = await setup();
  await screen.findByText('Gold');
  expect(screen.queryByText('14 zile')).toBeNull();
  await fireEvent.press(screen.getByText('5 zile'));
  await fireEvent.press(screen.getByText('Îngheață abonamentul'));
  await screen.findByText('Salvarea a eșuat');
  expect(onClose).not.toHaveBeenCalled();
  expect(onSaved).not.toHaveBeenCalled();
  expect(screen.getByRole('button', { name: /5 zile/, selected: true })).toBeTruthy();
  await fireEvent.press(screen.getByText('Îngheață abonamentul'));
  await waitFor(() => expect(onSaved).toHaveBeenCalledTimes(1));
  expect(onClose).toHaveBeenCalledTimes(1);
  expect(mockApply.mock.calls).toEqual([
    ['client', { kind: 'freeze', membershipId: 'membership', mode: 'auto_5_days' }],
    ['client', { kind: 'freeze', membershipId: 'membership', mode: 'auto_5_days' }],
  ]);
});

test('three-month memberships offer 14 days and scheduling hides manual mode', async () => {
  mockGetData.mockResolvedValue(fixture(3));
  const { screen } = await setup();
  await screen.findByText('Gold');
  expect(screen.getByText('14 zile')).toBeTruthy();
  await fireEvent.press(screen.getByText('La o dată viitoare'));
  expect(screen.queryByText('Manuală')).toBeNull();
  expect(screen.getByText('Programează înghețarea')).toBeTruthy();
});

test('frozen memberships show the preserved balance and offer resume', async () => {
  const data = fixture();
  data.memberships[0] = { ...data.memberships[0], is_frozen: 1, days_left_when_frozen: 8 };
  mockGetData.mockResolvedValue(data);
  mockApply.mockResolvedValue(undefined);
  const { screen, onSaved } = await setup();
  await screen.findByText('8 zile păstrate');
  await fireEvent.press(screen.getByText('Dezgheață abonamentul'));
  await waitFor(() => expect(onSaved).toHaveBeenCalledTimes(1));
  expect(mockApply).toHaveBeenCalledWith('client', { kind: 'resume', membershipId: 'membership' });
});

test('clients without owned memberships have no mutation action', async () => {
  mockGetData.mockResolvedValue({ memberships: [], schedules: [] });
  const { screen } = await setup();
  await screen.findByText(/Acest client nu are abonamente proprii/);
  expect(screen.queryByText('Îngheață abonamentul')).toBeNull();
  expect(mockApply).not.toHaveBeenCalled();
});

test('offline mode still reads the local memberships and commits the queued freeze', async () => {
  onlineManager.setOnline(false);
  mockGetData.mockResolvedValue(fixture());
  mockApply.mockResolvedValue(undefined);
  const { screen, onSaved } = await setup();
  await screen.findByText('Gold');
  await fireEvent.press(screen.getByText('Îngheață abonamentul'));
  await waitFor(() => expect(onSaved).toHaveBeenCalledTimes(1));
  expect(mockApply).toHaveBeenCalledWith('client', { kind: 'freeze', membershipId: 'membership', mode: 'manual' });
});
