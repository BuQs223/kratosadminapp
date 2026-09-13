import { test, expect, jest } from '@jest/globals';
import { QueryClient } from '@tanstack/react-query';
import { refreshReportFirstPage } from './report-query';

test('manual refresh replaces previously loaded pages with a page-one reload', async () => {
  const client = new QueryClient();
  const key = ['revenue', { gymId: 'gym' }];
  client.setQueryData(key, { pages: [{ items: ['a'] }, { items: ['b'] }, { items: ['c'] }], pageParams: [0, 20, 40] });
  const refetch = jest.fn(async () => {
    expect(client.getQueryData(key)).toEqual({ pages: [{ items: ['a'] }], pageParams: [0] });
  });
  await refreshReportFirstPage(client, key, refetch);
  expect(refetch).toHaveBeenCalledTimes(1);
  client.clear();
});
