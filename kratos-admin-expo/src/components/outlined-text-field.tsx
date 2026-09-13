import React from 'react';
import {
  Pressable,
  TextInput,
  View,
  type TextInputProps,
} from 'react-native';

import { AppText } from '@/components/app-text';
import { MaterialIcon } from '@/components/material-icon';
import type { MaterialIconName } from '@/constants/material-icons.generated';
import { useAppTheme } from '@/theme/theme';

export function OutlinedTextField({
  label,
  icon,
  error,
  suffixIcon,
  onSuffixPress,
  style,
  ...props
}: TextInputProps & {
  label: string;
  icon: MaterialIconName;
  error?: string;
  suffixIcon?: MaterialIconName;
  onSuffixPress?: () => void;
}) {
  const { colors } = useAppTheme();
  const [focused, setFocused] = React.useState(false);

  return (
    <View style={{ gap: 4 }}>
      <View
        style={{
          height: 56,
          borderWidth: focused ? 2 : 1,
          borderColor: error ? colors.error : focused ? colors.primary : colors.outline,
          borderRadius: 4,
          borderCurve: 'continuous',
          flexDirection: 'row',
          alignItems: 'center',
          paddingHorizontal: focused ? 11 : 12,
        }}>
        <View
          pointerEvents="none"
          style={{
            position: 'absolute',
            top: -9,
            left: 11,
            paddingHorizontal: 4,
            backgroundColor: colors.surface,
            zIndex: 1,
          }}>
          <AppText
            variant="bodySmall"
            color={error ? colors.error : focused ? colors.primary : colors.onSurfaceVariant}>
            {label}
          </AppText>
        </View>
        <MaterialIcon name={icon} size={24} color={colors.onSurfaceVariant} />
        <TextInput
          accessibilityLabel={label}
          placeholderTextColor={colors.onSurfaceVariant}
          selectionColor={colors.primary}
          style={[
            {
              flex: 1,
              height: 54,
              paddingHorizontal: 12,
              paddingVertical: 0,
              color: colors.onSurface,
              fontSize: 16,
            },
            style,
          ]}
          onFocus={(event) => {
            setFocused(true);
            props.onFocus?.(event);
          }}
          onBlur={(event) => {
            setFocused(false);
            props.onBlur?.(event);
          }}
          {...props}
        />
        {suffixIcon ? (
          <Pressable
            accessibilityRole="button"
            hitSlop={10}
            onPress={onSuffixPress}
            style={({ pressed }) => ({ opacity: pressed ? 0.6 : 1 })}>
            <MaterialIcon name={suffixIcon} size={24} color={colors.onSurfaceVariant} />
          </Pressable>
        ) : null}
      </View>
      {error ? (
        <AppText variant="bodySmall" color={colors.error} style={{ paddingHorizontal: 12 }}>
          {error}
        </AppText>
      ) : null}
    </View>
  );
}
