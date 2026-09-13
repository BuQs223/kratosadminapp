import { useLocalSearchParams } from 'expo-router';

import { MemberHistoryScreen } from '@/screens/members/member-history-screen';

export default function MemberHistoryRoute() {
  const { memberId } = useLocalSearchParams<{ memberId: string }>();
  return <MemberHistoryScreen memberId={memberId} />;
}
