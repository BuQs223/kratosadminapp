import { Text, type TextStyle, type StyleProp } from 'react-native';

import {
  materialIconCodepoints,
  type MaterialIconName,
} from '@/constants/material-icons.generated';

export function MaterialIcon({
  name,
  size = 24,
  color,
  style,
}: {
  name: MaterialIconName;
  size?: number;
  color?: string;
  style?: StyleProp<TextStyle>;
}) {
  return (
    <Text
      accessibilityElementsHidden
      importantForAccessibility="no"
      style={[{ fontFamily: 'MaterialIcons', fontSize: size, lineHeight: size, color }, style]}>
      {String.fromCodePoint(materialIconCodepoints[name])}
    </Text>
  );
}
