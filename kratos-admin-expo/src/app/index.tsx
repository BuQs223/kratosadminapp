import { router } from 'expo-router';
import React from 'react';
import { ActivityIndicator, View } from 'react-native';

import { AppText } from '@/components/app-text';
import { MaterialIcon } from '@/components/material-icon';
import { useAuth } from '@/providers/auth-provider';
import { useAppTheme } from '@/theme/theme';

const splashStartedAt = Date.now();

export default function SplashRoute() {
  const { colors } = useAppTheme();
  const { isLoading, session } = useAuth();
  React.useEffect(() => {
    if (isLoading) return;
    const remaining = Math.max(0, 2000 - (Date.now() - splashStartedAt));
    const timer = setTimeout(() => {
      router.replace(session ? '/(tabs)/dashboard' : '/login');
    }, remaining);
    return () => clearTimeout(timer);
  }, [isLoading, session]);

  return (
    <View
      style={{
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        gap: 24,
        backgroundColor: colors.surface,
      }}>
      <MaterialIcon name="fitness_center" size={100} color={colors.primary} />
      <AppText
        variant="headlineLarge"
        style={{ fontWeight: '700', color: colors.primary }}>
        Kratos Gym
      </AppText>
      <ActivityIndicator size="large" color={colors.primary} style={{ marginTop: 24 }} />
    </View>
  );
}
