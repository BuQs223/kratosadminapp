import { useLocalSearchParams } from 'expo-router';

import { MemberDetailScreen } from '@/screens/members/member-detail-screen';

export default function MemberDetailRoute() {
  const { memberId } = useLocalSearchParams<{ memberId: string }>();
  return <MemberDetailScreen memberId={memberId} />;
}
