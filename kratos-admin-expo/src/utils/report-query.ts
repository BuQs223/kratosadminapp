import type { InfiniteData, QueryClient, QueryKey } from '@tanstack/react-query';

/** A Flutter list refresh replaces the list with page one, not every loaded page. */
export async function refreshReportFirstPage(client: QueryClient, queryKey: QueryKey, refetch: () => Promise<unknown>) {
  await client.cancelQueries({ queryKey, exact: true });
  client.setQueryData<InfiniteData<unknown, number>>(queryKey, (data) => data ? {
    pages: data.pages.slice(0, 1), pageParams: data.pageParams.slice(0, 1),
  } : data);
  return refetch();
}
