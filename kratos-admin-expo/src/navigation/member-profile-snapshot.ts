import type { Profile } from '@/models/profile';

// Flutter passes the selected Profile object into the detail route. Keep that
// snapshot (including partial revenue profiles) instead of silently reloading it.
const snapshots = new Map<string, Profile>();
export function rememberMemberProfile(profile: Profile): { memberId: string } {
  snapshots.set(profile.id, profile);
  return { memberId: profile.id };
}
export function memberProfileSnapshot(memberId: string): Profile | undefined { return snapshots.get(memberId); }

export function clearMemberProfileSnapshots(): void { snapshots.clear(); }
