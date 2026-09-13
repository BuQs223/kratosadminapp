import { test, expect } from '@jest/globals';
import { renderHook } from '@testing-library/react-native';
import { useReportSnapshot } from './use-report-snapshot';

test('a failed filter request preserves the previous successful values until replacement arrives', async () => {
  const initial = { total: 2500 };
  const { result, rerender } = await renderHook(({ data }: { data: typeof initial | undefined }) => useReportSnapshot(data), { initialProps: { data: initial as typeof initial | undefined } });
  await rerender({ data: undefined });
  expect(result.current).toEqual(initial);
  await rerender({ data: { total: 0 } });
  expect(result.current).toEqual({ total: 0 });
  await rerender({ data: undefined });
  expect(result.current).toEqual({ total: 0 });
});
