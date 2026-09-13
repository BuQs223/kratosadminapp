import { useFlutterTabVisit } from '@/navigation/use-flutter-tab-visit';
import { TabStack } from '@/components/tab-stack';

export default function RevenueStackLayout() {
  const visit = useFlutterTabVisit('revenue');
  return (
    <TabStack key={visit}>
      <TabStack.Screen name="index" options={{ title: 'Venituri' }} />
    </TabStack>
  );
}
