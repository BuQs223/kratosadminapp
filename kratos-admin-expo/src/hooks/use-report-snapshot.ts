import { useState } from 'react';

/** Flutter retains the last successful report when a new filter/load fails. */
export function useReportSnapshot<T>(data: T | undefined): T | undefined {
  const [previous, setPrevious] = useState(data);
  if (data !== undefined && data !== previous) setPrevious(data);
  return data ?? previous;
}
