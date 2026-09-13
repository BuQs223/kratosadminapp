import { useFlutterTabVisit } from '@/navigation/use-flutter-tab-visit';
import { TabStack } from '@/components/tab-stack';

export default function MembersStackLayout() {
  const visit = useFlutterTabVisit('members');
  return (
    <TabStack key={visit}>
      <TabStack.Screen name="index" options={{ title: 'Membri' }} />
    </TabStack>
  );
}
