import { useFlutterTabVisit } from '@/navigation/use-flutter-tab-visit';
import { router } from 'expo-router';
import { Pressable } from 'react-native';

import { AppText } from '@/components/app-text';
import { MaterialIcon } from '@/components/material-icon';
import { TabStack } from '@/components/tab-stack';
import { authService } from '@/services/auth-service';
import { useAppTheme } from '@/theme/theme';

export default function DashboardStackLayout() {
  const visit = useFlutterTabVisit('dashboard');
  const { colors } = useAppTheme();

  const signOut = async () => {
    await authService.signOut();
    router.replace('/login');
  };

  return (
    <TabStack key={visit}>
      <TabStack.Screen
        name="index"
        options={{
          headerTitle: () => <AppText variant="titleLarge">Dashboard</AppText>,
          headerRight: () => (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Deconectare"
              hitSlop={12}
              onPress={() => void signOut()}
              style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, padding: 6 })}>
              <MaterialIcon name="logout_rounded" size={24} color={colors.onSurfaceVariant} />
            </Pressable>
          ),
          headerLeft: () => (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Instrumente administrare"
              hitSlop={12}
              onPress={() => router.push('/admin-tools')}
              style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, padding: 6 })}>
              <MaterialIcon name="admin_panel_settings_outlined" size={24} color={colors.onSurfaceVariant} />
            </Pressable>
          ),
        }}
      />
    </TabStack>
  );
}
