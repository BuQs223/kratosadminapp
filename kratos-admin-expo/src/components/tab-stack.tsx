import { Stack } from 'expo-router/stack';
import type React from 'react';

import { useAppTheme } from '@/theme/theme';

function TabStackRoot({ children }: { children?: React.ReactNode }) {
  const { colors } = useAppTheme();
  return (
    <Stack
      screenOptions={{
        headerTitleAlign: 'center',
        headerShadowVisible: false,
        headerStyle: { backgroundColor: colors.surface },
        headerTintColor: colors.onSurface,
        contentStyle: { backgroundColor: colors.surfaceContainerLowest },
      }}>
      {children}
    </Stack>
  );
}

export const TabStack = Object.assign(TabStackRoot, { Screen: Stack.Screen });
