import { render } from '@testing-library/react-native';
import { describe, expect, jest, test } from '@jest/globals';
import React from 'react';

import DashboardScreen from '@/app/(tabs)/dashboard/index';

const mockUseQuery = jest.fn();
const mockLinkPress = jest.fn();

jest.mock('@tanstack/react-query', () => ({
  useQuery: (options: unknown) => mockUseQuery(options),
}));

jest.mock('@/repositories/dashboard-repository', () => ({
  getDashboardStats: jest.fn(),
}));

jest.mock('expo-router', () => {
  const ReactActual = jest.requireActual<typeof import('react')>('react');
  return {
    Link: ({ children, href }: { children: React.ReactElement<{ onPress?: () => void }>; href: string }) =>
      ReactActual.cloneElement(children, { onPress: () => mockLinkPress(href) }),
  };
});

describe('dashboard membership metrics', () => {
  test('keeps the active-membership card informational and out of membership-access navigation', async () => {
    mockUseQuery.mockReturnValue({
      isLoading: false,
      data: {
        totalMembers: 950,
        activeMemberships: 876,
        todayCheckIns: 30,
        monthlyRevenue: 1000,
        wau: 500,
        mau: 800,
        dauYesterday: 70,
      },
      error: null,
      refetch: jest.fn(),
    });

    const screen = await render(<DashboardScreen />);
    expect(screen.getByText('Abonamente Active')).toBeTruthy();
    expect(screen.queryByText('Persoane cu acces')).toBeNull();
    expect(mockLinkPress).not.toHaveBeenCalled();
  });
});
