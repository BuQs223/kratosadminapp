import { test, expect, jest } from '@jest/globals';
import { act, renderHook } from '@testing-library/react-native';
import { useFlutterTabVisit } from './use-flutter-tab-visit';

const mockFocusHandlers = new Set<() => void>();
jest.mock('expo-router', () => ({ useFocusEffect: (callback: () => void) => { mockFocusHandlers.add(callback); } }));

test('pushed routes preserve a tab, but switching tabs resets it on return', async () => {
  mockFocusHandlers.clear();
  const members = await renderHook(() => useFlutterTabVisit('members'));
  const focusMembers = [...mockFocusHandlers][0];
  await act(() => focusMembers());
  expect(members.result.current).toBe(0);
  await act(() => focusMembers()); // Detail route popped; same tab.
  expect(members.result.current).toBe(0);
  const revenue = await renderHook(() => useFlutterTabVisit('revenue'));
  const focusRevenue = [...mockFocusHandlers][1];
  await act(() => focusRevenue());
  expect(revenue.result.current).toBe(0);
  await act(() => focusMembers());
  expect(members.result.current).toBe(1);
});
