import { TabStack } from '@/components/tab-stack';

export default function CheckInsStackLayout() {
  return (
    <TabStack>
      <TabStack.Screen name="index" options={{ title: 'Check-ins' }} />
    </TabStack>
  );
}
