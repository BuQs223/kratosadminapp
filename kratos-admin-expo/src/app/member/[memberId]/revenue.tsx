import { useLocalSearchParams } from 'expo-router';

import { MemberRevenueHistoryScreen } from '@/screens/members/member-revenue-history-screen';

export default function MemberRevenueHistoryRoute() {
  const { memberId } = useLocalSearchParams<{ memberId: string }>();
  return <MemberRevenueHistoryScreen memberId={memberId} />;
}
