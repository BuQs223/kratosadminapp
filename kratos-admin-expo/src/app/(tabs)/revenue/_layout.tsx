import { TabStack } from '@/components/tab-stack';

export default function RevenueStackLayout() {
  return (
    <TabStack>
      <TabStack.Screen name="index" options={{ title: 'Venituri' }} />
    </TabStack>
  );
}
