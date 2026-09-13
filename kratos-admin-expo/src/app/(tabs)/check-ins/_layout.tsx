import { useFlutterTabVisit } from '@/navigation/use-flutter-tab-visit';
import { TabStack } from '@/components/tab-stack';

export default function CheckInsStackLayout() {
  const visit = useFlutterTabVisit('check-ins');
  return (
    <TabStack key={visit}>
      <TabStack.Screen name="index" options={{ title: 'Check-ins' }} />
    </TabStack>
  );
}
