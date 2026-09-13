import { TabStack } from '@/components/tab-stack';

export default function MembersStackLayout() {
  return (
    <TabStack>
      <TabStack.Screen name="index" options={{ title: 'Membri' }} />
    </TabStack>
  );
}
