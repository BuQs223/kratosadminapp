import { Text, type TextProps } from 'react-native';

import { useAppTheme } from '@/theme/theme';

export type AppTextVariant =
  | 'body'
  | 'bodyLarge'
  | 'bodySmall'
  | 'titleSmall'
  | 'titleMedium'
  | 'titleLarge'
  | 'headlineMedium'
  | 'headlineLarge';

const variants = {
  body: { fontSize: 14, lineHeight: 20 },
  bodyLarge: { fontSize: 16, lineHeight: 24 },
  bodySmall: { fontSize: 12, lineHeight: 16 },
  titleSmall: { fontSize: 14, lineHeight: 20, fontWeight: '500' as const },
  titleMedium: { fontSize: 16, lineHeight: 24, fontWeight: '500' as const },
  titleLarge: { fontSize: 22, lineHeight: 28, fontWeight: '500' as const },
  headlineMedium: { fontSize: 28, lineHeight: 36 },
  headlineLarge: { fontSize: 32, lineHeight: 40 },
};

export function AppText({
  variant = 'body',
  color,
  selectable,
  style,
  ...props
}: TextProps & { variant?: AppTextVariant; color?: string }) {
  const { colors } = useAppTheme();
  return (
    <Text
      selectable={selectable}
      style={[{ color: color ?? colors.onSurface }, variants[variant], style]}
      {...props}
    />
  );
}
