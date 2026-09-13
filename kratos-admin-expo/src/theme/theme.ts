import { useColorScheme } from 'react-native';

export const lightColors = {
  primary: '#68548E',
  onPrimary: '#FFFFFF',
  primaryContainer: '#EBDDFF',
  onPrimaryContainer: '#230F46',
  secondary: '#635B70',
  onSecondary: '#FFFFFF',
  secondaryContainer: '#E9DEF8',
  onSecondaryContainer: '#1F182A',
  tertiary: '#7E525D',
  onTertiary: '#FFFFFF',
  tertiaryContainer: '#FFD9E1',
  onTertiaryContainer: '#31101B',
  surface: '#FEF7FF',
  onSurface: '#1D1B20',
  surfaceContainerLowest: '#FFFFFF',
  surfaceContainerLow: '#F8F1FA',
  surfaceContainer: '#F2ECF4',
  surfaceContainerHigh: '#EDE6EE',
  surfaceContainerHighest: '#E7E0E8',
  onSurfaceVariant: '#49454E',
  outline: '#7A757F',
  outlineVariant: '#CBC4CF',
  error: '#BA1A1A',
  errorContainer: '#FFDAD6',
  onErrorContainer: '#410002',
} as const;

export const darkColors = {
  primary: '#D3BCFD',
  onPrimary: '#38265C',
  primaryContainer: '#4F3D74',
  onPrimaryContainer: '#EBDDFF',
  secondary: '#CDC2DB',
  onSecondary: '#342D40',
  secondaryContainer: '#4B4357',
  onSecondaryContainer: '#E9DEF8',
  tertiary: '#EFB8C8',
  onTertiary: '#4A2532',
  tertiaryContainer: '#633B48',
  onTertiaryContainer: '#FFD9E1',
  surface: '#151218',
  onSurface: '#E7E0E8',
  surfaceContainerLowest: '#0F0D13',
  surfaceContainerLow: '#1D1B20',
  surfaceContainer: '#211F24',
  surfaceContainerHigh: '#2C292F',
  surfaceContainerHighest: '#36343A',
  onSurfaceVariant: '#CBC4CF',
  outline: '#948F99',
  outlineVariant: '#49454E',
  error: '#FFB4AB',
  errorContainer: '#93000A',
  onErrorContainer: '#FFDAD6',
} as const;

export type AppColors = { [Key in keyof typeof lightColors]: string };

export function useAppTheme() {
  const colorScheme = useColorScheme();
  const isDark = colorScheme === 'dark';
  return { colors: (isDark ? darkColors : lightColors) as AppColors, isDark };
}

export function colorWithAlpha(hex: string, alpha: number): string {
  const normalized = hex.replace('#', '');
  const red = Number.parseInt(normalized.slice(0, 2), 16);
  const green = Number.parseInt(normalized.slice(2, 4), 16);
  const blue = Number.parseInt(normalized.slice(4, 6), 16);
  return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
}
