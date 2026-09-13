import { useFocusEffect } from 'expo-router';
import { useCallback, useRef, useState } from 'react';

let lastTab: string | undefined;
/** Flutter replaces its tab widget on a tab switch, but preserves it under pushed routes. */
export function useFlutterTabVisit(tab: string): number {
  const visited = useRef(false);
  const [visit, setVisit] = useState(0);
  useFocusEffect(useCallback(() => {
    if (visited.current && lastTab !== tab) setVisit((value) => value + 1);
    visited.current = true;
    lastTab = tab;
  }, [tab]));
  return visit;
}
