import { fireEvent, render } from '@testing-library/react-native';
import { describe, expect, jest, test } from '@jest/globals';
import React from 'react';

import MembershipAnalyticsScreen from '@/app/membership-analytics';
import type { MembershipTrendPoint } from '@/models/membership-trend';

const mockUseQuery = jest.fn();
const mockRefetch = jest.fn<() => Promise<unknown>>().mockResolvedValue(undefined);
let mockTrendState: Record<string, unknown>;

jest.mock('@tanstack/react-query', () => ({
  useQuery: (options: unknown) => mockUseQuery(options),
}));

jest.mock('expo-router', () => ({
  Stack: { Screen: () => null },
}));

jest.mock('react-native-safe-area-context', () => ({
  useSafeAreaInsets: () => ({ bottom: 0 }),
}));

jest.mock('@gorhom/bottom-sheet', () => {
  const ReactActual = jest.requireActual<typeof import('react')>('react');
  const { ScrollView } = jest.requireActual<typeof import('react-native')>('react-native');
  return { BottomSheetScrollView: ({ children }: React.PropsWithChildren) => ReactActual.createElement(ScrollView, null, children) };
});

jest.mock('@/components/bottom-sheet-modal', () => {
  const ReactActual = jest.requireActual<typeof import('react')>('react');
  const { View } = jest.requireActual<typeof import('react-native')>('react-native');
  return { BottomSheetModal: ({ children }: React.PropsWithChildren) => ReactActual.createElement(View, null, children) };
});

jest.mock('react-native-reanimated', () => {
  const { View } = jest.requireActual<typeof import('react-native')>('react-native');
  return {
    __esModule: true,
    default: { View },
    SlideInDown: { duration: () => ({}) },
    SlideOutDown: { duration: () => ({}) },
  };
});

jest.mock('@/repositories/lookups-repository', () => ({
  lookupsRepository: { getGyms: jest.fn() },
}));

const points: MembershipTrendPoint[] = [
  {
    periodStart: new Date('2026-08-01T00:00:00.000Z'),
    periodEnd: new Date('2026-08-01T00:00:00.000Z'),
    activePeople: 876,
    newActivations: 11,
    isEstimated: true,
    computedAt: new Date('2026-08-02T00:15:00.000Z'),
  },
  {
    periodStart: new Date('2026-08-02T00:00:00.000Z'),
    periodEnd: new Date('2026-08-02T00:00:00.000Z'),
    activePeople: 882,
    newActivations: 6,
    isEstimated: false,
    computedAt: new Date('2026-08-03T00:15:00.000Z'),
  },
];

function queryKey(options: unknown): unknown[] {
  return (options as { queryKey: unknown[] }).queryKey;
}

function setOnlineData() {
  mockUseQuery.mockClear();
  mockRefetch.mockClear();
  mockTrendState = { data: points, isLoading: false, isError: false, error: null, refetch: mockRefetch };
  mockUseQuery.mockImplementation((options: unknown) => {
    if (queryKey(options)[0] === 'membership-access-trend') return mockTrendState;
    return {
      data: [{ id: 'gym-1', name: 'Kratos 1' }],
      isLoading: false,
      isError: false,
      error: null,
      refetch: mockRefetch,
    };
  });
}

function thirtyDailyPoints(): MembershipTrendPoint[] {
  return Array.from({ length: 30 }, (_, index) => ({
    periodStart: new Date(Date.UTC(2026, 7, index + 1)),
    periodEnd: new Date(Date.UTC(2026, 7, index + 1)),
    activePeople: 850 + index,
    newActivations: index % 6,
    isEstimated: index < 29,
    computedAt: new Date('2026-09-01T00:15:00.000Z'),
  }));
}

describe('membership analytics screen', () => {
  test('updates metric, range, and selling-gym query parameters from the controls', async () => {
    setOnlineData();
    const screen = await render(<MembershipAnalyticsScreen />);

    await fireEvent.press(screen.getByText('Activări noi'));
    await fireEvent.press(screen.getByText('12L'));
    await fireEvent.press(screen.getByText('Schimbă'));
    await fireEvent.press(await screen.findByText('Kratos 1'));

    const trendKeys = mockUseQuery.mock.calls
      .map(([options]) => queryKey(options))
      .filter((key) => key[0] === 'membership-access-trend');
    expect(trendKeys).toContainEqual(['membership-access-trend', '12m', 'gym-1']);
  });

  test('renders the estimated explanation and selects the nearest point from anywhere on the chart', async () => {
    setOnlineData();
    const screen = await render(<MembershipAnalyticsScreen />);

    expect(screen.getByText(/Perioadele punctate sunt reconstruite/)).toBeTruthy();
    const chart = screen.getByTestId('membership-trend-chart');
    await fireEvent.press(chart, { nativeEvent: { locationX: 42 } });
    expect(screen.getByLabelText(/Detalii punct: .*876, estimat/)).toBeTruthy();
  });

  test('shows weekly visual markers and snaps 30-day selection to those markers', async () => {
    setOnlineData();
    mockTrendState = { data: thirtyDailyPoints(), isLoading: false, isError: false, error: null, refetch: mockRefetch };
    const screen = await render(<MembershipAnalyticsScreen />);

    expect(screen.getByTestId('membership-trend-marker-0')).toBeTruthy();
    expect(screen.getByTestId('membership-trend-marker-7')).toBeTruthy();
    expect(screen.getByTestId('membership-trend-marker-29')).toBeTruthy();
    expect(screen.queryByTestId('membership-trend-marker-1')).toBeNull();

    await fireEvent.press(screen.getByTestId('membership-trend-chart'), { nativeEvent: { locationX: 60 } });
    expect(screen.getByLabelText(/Detalii punct: .*850/)).toBeTruthy();
    expect(screen.queryByLabelText(/Detalii punct: .*851/)).toBeNull();
  });

  test('shows an online error with a working retry action', async () => {
    mockTrendState = {
      data: undefined,
      isLoading: false,
      isError: true,
      error: new Error('Fără conexiune'),
      refetch: mockRefetch,
    };
    mockUseQuery.mockImplementation((options: unknown) => {
      if (queryKey(options)[0] === 'membership-access-trend') return mockTrendState;
      return { data: [], isLoading: false, isError: false, error: null, refetch: mockRefetch };
    });

    const screen = await render(<MembershipAnalyticsScreen />);
    expect(screen.getByText('Analiza nu poate fi încărcată')).toBeTruthy();
    await fireEvent.press(screen.getByText('Reîncearcă'));
    expect(mockRefetch).toHaveBeenCalled();
  });
});
