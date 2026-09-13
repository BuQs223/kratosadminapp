import { DarkTheme, DefaultTheme, ThemeProvider } from 'expo-router';
import { useFonts } from 'expo-font';
import { Stack } from 'expo-router/stack';
import * as SplashScreen from 'expo-splash-screen';
import React from 'react';
import { StatusBar } from 'expo-status-bar';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

import { AppProviders } from '@/providers/app-providers';
import { useAppTheme } from '@/theme/theme';

void SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [fontsLoaded, fontError] = useFonts({
    MaterialIcons: require('@/assets/fonts/MaterialIcons-Regular.otf'),
  });

  React.useEffect(() => {
    if (fontsLoaded || fontError) void SplashScreen.hideAsync();
  }, [fontError, fontsLoaded]);

  if (!fontsLoaded && !fontError) return null;
  return <RootNavigator />;
}

function RootNavigator() {
  const { colors, isDark } = useAppTheme();
  const baseTheme = isDark ? DarkTheme : DefaultTheme;
  const navigationTheme = {
    ...baseTheme,
    colors: {
      ...baseTheme.colors,
      primary: colors.primary,
      background: colors.surfaceContainerLowest,
      card: colors.surface,
      text: colors.onSurface,
      border: colors.outlineVariant,
      notification: colors.error,
    },
  };
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <ThemeProvider value={navigationTheme}>
        <AppProviders>
          <StatusBar style={isDark ? 'light' : 'dark'} />
          <Stack
            screenOptions={{
              headerTitleAlign: 'center',
              headerBackButtonDisplayMode: 'minimal',
              headerShadowVisible: false,
              headerStyle: { backgroundColor: colors.surface },
              headerTintColor: colors.onSurface,
              contentStyle: { backgroundColor: colors.surfaceContainerLowest },
            }}>
            <Stack.Screen name="index" options={{ headerShown: false }} />
            <Stack.Screen name="login" options={{ headerShown: false }} />
            <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
            <Stack.Screen name="gold-checkins" options={{ title: 'Gold Check-ins' }} />
            <Stack.Screen name="check-in-stats" options={{ title: 'Statistici Check-ins' }} />
            <Stack.Screen name="revenue-analytics" options={{ title: 'Analiză Venituri' }} />
            <Stack.Screen name="membership-analytics" options={{ title: 'Acces membri' }} />
            <Stack.Screen name="period-comparison" options={{ title: 'Comparație Perioade' }} />
            <Stack.Screen name="gyms" options={{ title: 'Săli' }} />
            <Stack.Screen name="membership-plans" options={{ title: 'Planuri Abonamente' }} />
            <Stack.Screen name="admin-tools" options={{ title: 'Administrare' }} />
            <Stack.Screen name="member/[memberId]" options={{ headerShown: false }} />
            <Stack.Screen name="member/[memberId]/history" options={{ title: 'Istoric Membru' }} />
            <Stack.Screen name="member/[memberId]/revenue" options={{ title: 'Istoric încasări' }} />
          </Stack>
        </AppProviders>
      </ThemeProvider>
    </GestureHandlerRootView>
  );
}
