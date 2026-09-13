import React from 'react';
import { RefreshControl, type RefreshControlProps } from 'react-native';

interface ManualRefreshControlProps
  extends Omit<RefreshControlProps, 'refreshing' | 'onRefresh'> {
  onRefresh: () => Promise<unknown> | void;
}

/** Only displays the native spinner for a refresh explicitly started by the user. */
export function ManualRefreshControl({ onRefresh, ...props }: ManualRefreshControlProps) {
  const [refreshing, setRefreshing] = React.useState(false);
  const active = React.useRef(false);
  const mounted = React.useRef(true);

  React.useEffect(() => () => {
    mounted.current = false;
  }, []);

  const handleRefresh = React.useCallback(() => {
    if (active.current) return;
    active.current = true;
    setRefreshing(true);

    void Promise.resolve()
      .then(onRefresh)
      .catch(() => undefined)
      .finally(() => {
        active.current = false;
        if (mounted.current) setRefreshing(false);
      });
  }, [onRefresh]);

  return <RefreshControl {...props} refreshing={refreshing} onRefresh={handleRefresh} />;
}
