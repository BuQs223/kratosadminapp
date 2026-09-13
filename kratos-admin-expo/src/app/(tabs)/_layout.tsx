import { Redirect } from 'expo-router';
import { NativeTabs } from 'expo-router/unstable-native-tabs';

import { useAuth } from '@/providers/auth-provider';
import { useAppTheme } from '@/theme/theme';

export default function MainTabsLayout() {
  const { colors } = useAppTheme();
  const { isLoading, session } = useAuth();

  if (isLoading) return null;
  if (!session) return <Redirect href="/login" />;

  return (
    <NativeTabs
      backgroundColor={colors.surfaceContainer}
      indicatorColor={colors.primaryContainer}
      iconColor={{ default: colors.onSurfaceVariant, selected: colors.onPrimaryContainer }}
      labelStyle={{
        default: { color: colors.onSurfaceVariant, fontSize: 12 },
        selected: { color: colors.onSurface, fontSize: 12, fontWeight: '500' },
      }}>
      <NativeTabs.Trigger name="dashboard">
        <NativeTabs.Trigger.Label>Acasa</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon
          sf={{ default: 'square.grid.2x2', selected: 'square.grid.2x2.fill' }}
          md={{ default: 'dashboard', selected: 'dashboard' }}
        />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="members">
        <NativeTabs.Trigger.Label>Membri</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon
          sf={{ default: 'person.2', selected: 'person.2.fill' }}
          md={{ default: 'people_outline', selected: 'people' }}
        />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="check-ins">
        <NativeTabs.Trigger.Label>Check-ins</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon
          sf={{ default: 'checkmark.circle', selected: 'checkmark.circle.fill' }}
          md={{ default: 'check_circle_outline', selected: 'check_circle' }}
        />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="revenue">
        <NativeTabs.Trigger.Label>Venituri</NativeTabs.Trigger.Label>
        <NativeTabs.Trigger.Icon
          sf={{ default: 'dollarsign.circle', selected: 'dollarsign.circle.fill' }}
          md={{ default: 'attach_money', selected: 'attach_money' }}
        />
      </NativeTabs.Trigger>
    </NativeTabs>
  );
}
