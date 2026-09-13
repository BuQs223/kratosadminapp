import { refreshReportFirstPage } from '@/utils/report-query';
import { useReportSnapshot } from '@/hooks/use-report-snapshot';
import { rememberMemberProfile } from '@/navigation/member-profile-snapshot';
import { LinearGradient } from 'expo-linear-gradient';
import { router, Stack } from 'expo-router';
import { useInfiniteQuery, useQueryClient, useQuery } from '@tanstack/react-query';
import React from 'react';
import { BottomSheetScrollView } from '@gorhom/bottom-sheet';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  StyleSheet,
  View,
} from 'react-native';

import { AppText } from '@/components/app-text';
import { BottomSheetModal } from '@/components/bottom-sheet-modal';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { MaterialIcon } from '@/components/material-icon';
import type { CheckIn } from '@/models/check-in';
import { getCheckIns, type CheckInFilters } from '@/repositories/check-ins-repository';
import { lookupsRepository, type LookupOption } from '@/repositories/lookups-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

const pageSize = 20;

export default function CheckInsScreen() {
  const { colors } = useAppTheme();
  const queryClient = useQueryClient();
  const [filters, setFilters] = React.useState<CheckInFilters>({});
  const [filtersVisible, setFiltersVisible] = React.useState(false);
  const checkInsQuery = useInfiniteQuery({
    queryKey: ['check-ins', filters],
    queryFn: ({ pageParam }) => getCheckIns({ filters, limit: pageSize, offset: pageParam }),
    initialPageParam: 0,
    getNextPageParam: (lastPage, pages) => lastPage.hasMore ? pages.reduce((count, page) => count + page.items.length, 0) : undefined,
  });
  const gymsQuery = useQuery({ queryKey: ['gym-lookups', 'check-ins-index'], queryFn: lookupsRepository.getGyms });
  const reportSnapshot = useReportSnapshot(checkInsQuery.data);
  const checkIns = reportSnapshot?.pages.flatMap((page) => page.items) ?? [];
  const activeCount = Number(Boolean(filters.gymId)) + Number(Boolean(filters.status));

  return (
    <View style={[styles.screen, { backgroundColor: colors.surfaceContainerLowest }]}>
      <Stack.Screen options={{
        title: 'Check-ins',
        headerRight: () => (
          <View style={styles.headerActions}>
            <Pressable accessibilityRole="button" accessibilityLabel="Statistici Check-ins" hitSlop={10} onPress={() => router.push('/check-in-stats')} style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, padding: 6 })}>
              <MaterialIcon name="query_stats" size={24} color={colors.onSurfaceVariant} />
            </Pressable>
            <Pressable accessibilityRole="button" accessibilityLabel="Filtre" hitSlop={10} onPress={() => setFiltersVisible(true)} style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, padding: 6 })}>
              <MaterialIcon name="filter_list" size={24} color={colors.onSurfaceVariant} />
              {activeCount ? <View style={[styles.filterCount, { backgroundColor: colors.error }]}><AppText color="#FFFFFF" style={styles.filterCountText}>{activeCount}</AppText></View> : null}
            </Pressable>
          </View>
        ),
      }} />

      {checkInsQuery.isLoading ? (
        <View style={styles.center}><ActivityIndicator size="large" color={colors.primary} /></View>
      ) : (
        <FlatList
          data={checkIns}
          keyExtractor={(checkIn) => checkIn.id}
          contentContainerStyle={checkIns.length ? styles.list : styles.emptyList}
          ItemSeparatorComponent={() => <View style={styles.gap} />}
          renderItem={({ item }) => <CheckInCard checkIn={item} />}
          onEndReachedThreshold={0.2}
          onEndReached={() => { if (checkInsQuery.hasNextPage && !checkInsQuery.isFetchingNextPage) void checkInsQuery.fetchNextPage(); }}
          contentInsetAdjustmentBehavior="automatic"
          refreshControl={<ManualRefreshControl tintColor={colors.primary} colors={[colors.primary]} onRefresh={() => refreshReportFirstPage(queryClient, ['check-ins', filters], checkInsQuery.refetch)} />}
          ListFooterComponent={
            checkInsQuery.isFetchingNextPage ? <View style={styles.footer}><ActivityIndicator color={colors.primary} /></View>
            : checkIns.length && !checkInsQuery.hasNextPage ? <View style={styles.footer}><AppText variant="bodySmall" color={colors.onSurfaceVariant}>Toate check-in-urile au fost încărcate</AppText></View>
            : null
          }
          ListEmptyComponent={
            <View style={styles.center}>
              {checkInsQuery.error ? <AppText selectable color={colors.error} style={styles.errorText}>Eroare: {checkInsQuery.error instanceof Error ? checkInsQuery.error.message : String(checkInsQuery.error)}</AppText> : (
                <><MaterialIcon name="check_circle_outline" size={80} color={colorWithAlpha(colors.primary, 0.3)} /><AppText style={styles.emptyTitle}>Niciun check-in</AppText><AppText color={colors.onSurfaceVariant} style={styles.emptySubtitle}>Activitatea de check-in va apărea aici</AppText></>
              )}
            </View>
          }
        />
      )}
      {filtersVisible ? <CheckInFilterSheet visible value={filters} gyms={gymsQuery.data ?? []} onClose={() => setFiltersVisible(false)} onApply={setFilters} /> : null}
    </View>
  );
}

function CheckInCard({ checkIn }: { checkIn: CheckIn }) {
  const { colors } = useAppTheme();
  const visual = checkInVisual(checkIn.status, colors.onSurfaceVariant);
  const denied = checkIn.status === 'denied' || checkIn.status === 'expired' || checkIn.status === 'no_access';
  return (
    <Pressable disabled={!checkIn.profile} onPress={() => checkIn.profile && router.push({ pathname: '/member/[memberId]', params: rememberMemberProfile(checkIn.profile) })} style={({ pressed }) => [styles.card, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5), opacity: pressed ? 0.8 : 1 }]}>
      <LinearGradient colors={[colorWithAlpha(visual.color, 0.05), colorWithAlpha(visual.color, 0.02)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} />
      <View style={styles.cardContent}>
        <View style={styles.cardHeader}>
          <View style={[styles.statusCircle, { backgroundColor: colorWithAlpha(visual.color, 0.15) }]}><AppText style={styles.statusEmoji}>{visual.emoji}</AppText></View>
          <View style={styles.cardTitle}>
            <AppText numberOfLines={1} variant="titleMedium" style={styles.bold}>{checkIn.profile?.fullName ?? 'Unknown'}</AppText>
            <AppText variant="bodySmall" color={colors.onSurfaceVariant} style={styles.timestamp}>{formatDateTime(checkIn.checkedInAt)}</AppText>
          </View>
          {checkIn.status ? <View style={[styles.statusBadge, { backgroundColor: colorWithAlpha(visual.color, 0.15) }]}><AppText color={visual.color} style={styles.statusText}>{statusLabel(checkIn.status)}</AppText></View> : null}
        </View>
        <View style={styles.metaWrap}>
          <Meta icon="fitness_center" text={checkIn.gym?.name ?? 'Unknown'} bold />
          {checkIn.daysLeft !== null ? <Meta icon="event_available" text={`${checkIn.daysLeft}z rămase`} color={checkIn.daysLeft <= 7 ? '#FF9800' : colors.onSurfaceVariant} bold /> : null}
        </View>
        {checkIn.message ? <View style={[styles.message, { backgroundColor: denied ? colorWithAlpha('#F44336', 0.1) : colorWithAlpha(colors.surfaceContainerHighest, 0.5), borderColor: denied ? colorWithAlpha('#F44336', 0.3) : 'transparent' }]}><MaterialIcon name={denied ? 'error_outline' : 'info_outline'} size={16} color={denied ? '#F44336' : colors.primary} /><AppText variant="bodySmall" color={denied ? '#B71C1C' : colors.onSurfaceVariant} style={styles.messageText}>{checkIn.message}</AppText></View> : null}
      </View>
    </Pressable>
  );
}

function Meta({ icon, text, color, bold }: { icon: 'fitness_center' | 'event_available'; text: string; color?: string; bold?: boolean }) {
  const { colors } = useAppTheme();
  return <View style={styles.meta}><MaterialIcon name={icon} size={16} color={color ?? colors.onSurfaceVariant} /><AppText color={color} style={[styles.metaText, bold ? styles.medium : null]}>{text}</AppText></View>;
}

function CheckInFilterSheet({ visible, value, gyms, onClose, onApply }: { visible: boolean; value: CheckInFilters; gyms: LookupOption[]; onClose: () => void; onApply: (value: CheckInFilters) => void }) {
  const { colors } = useAppTheme();
  const [draft, setDraft] = React.useState(value);
  return (
    <BottomSheetModal visible={visible} onClose={onClose} snapPoints={['60%']} initialIndex={0} scrollable sheetStyle={[styles.filterSheet, { backgroundColor: colors.surface }]}>
      <View style={styles.filterHeader}><AppText variant="titleLarge" style={styles.bold}>Filtre</AppText><Pressable onPress={() => { onApply({}); onClose(); }} hitSlop={8}><AppText color={colors.primary}>Resetează</AppText></Pressable></View>
      <View style={[styles.rule, { backgroundColor: colors.outlineVariant }]} />
      <BottomSheetScrollView contentInsetAdjustmentBehavior="automatic" style={styles.filterScroll} contentContainerStyle={styles.filterContent} showsVerticalScrollIndicator={false}>
        <FilterGroup title="Sală">
          <Chip label="Toate" selected={!draft.gymId} onPress={() => setDraft((current) => ({ ...current, gymId: undefined }))} />
          {gyms.map((gym) => <Chip key={gym.id} label={gym.name} selected={draft.gymId === gym.id} onPress={() => setDraft((current) => ({ ...current, gymId: current.gymId === gym.id ? undefined : gym.id }))} />)}
        </FilterGroup>
        <FilterGroup title="Status">
          <Chip label="Toate" selected={!draft.status} onPress={() => setDraft((current) => ({ ...current, status: undefined }))} />
          {[['success', '✅ Activ'], ['expiring', '⚠️ Expiră'], ['denied', '❌ Refuzat'], ['time_restricted', '⏰ Restricție'], ['expired', '🚫 Expirat']].map(([status, label]) => <Chip key={status} label={label} selected={draft.status === status} onPress={() => setDraft((current) => ({ ...current, status: current.status === status ? undefined : status }))} />)}
        </FilterGroup>
      </BottomSheetScrollView>
      <View style={[styles.applyArea, { borderTopColor: colors.outlineVariant }]}><Pressable onPress={() => { onApply(draft); onClose(); }} style={({ pressed }) => [styles.applyButton, { backgroundColor: colors.primary, opacity: pressed ? 0.72 : 1 }]}><AppText color={colors.onPrimary} style={styles.medium}>Aplică Filtre</AppText></Pressable></View>
    </BottomSheetModal>
  );
}

function FilterGroup({ title, children }: React.PropsWithChildren<{ title: string }>) { return <View style={styles.filterGroup}><AppText variant="titleMedium" style={styles.medium}>{title}</AppText><View style={styles.chips}>{children}</View></View>; }
function Chip({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  const { colors } = useAppTheme();
  return <Pressable accessibilityState={{ selected }} onPress={onPress} style={({ pressed }) => [styles.chip, { backgroundColor: selected ? colors.secondaryContainer : colors.surfaceContainerLow, borderColor: selected ? colors.onSurfaceVariant : colors.outlineVariant, opacity: pressed ? 0.7 : 1 }]}><AppText>{label}</AppText></Pressable>;
}

function checkInVisual(status: string | null, fallback: string) {
  if (status === 'success') return { color: '#43A047', emoji: '✅' };
  if (status === 'expiring') return { color: '#FB8C00', emoji: '⚠️' };
  if (status === 'time_restricted') return { color: '#1E88E5', emoji: '⏰' };
  if (status === 'denied' || status === 'expired' || status === 'no_access') return { color: '#E53935', emoji: '❌' };
  return { color: fallback, emoji: '❓' };
}
function statusLabel(status: string) { return ({ success: 'ACTIV', expiring: 'EXPIRĂ', expired: 'EXPIRAT', denied: 'REFUZAT', no_access: 'FĂRĂ ACCES', time_restricted: 'RESTRICȚIE' } as Record<string, string>)[status.toLowerCase()] ?? status.toUpperCase(); }
function formatDateTime(date: Date) { return `${String(date.getDate()).padStart(2, '0')} ${date.toLocaleDateString('en-GB', { month: 'short' })} ${date.getFullYear()}, ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`; }

const styles = StyleSheet.create({
  screen: { flex: 1 }, center: { flex: 1, alignItems: 'center', justifyContent: 'center' }, headerActions: { flexDirection: 'row', alignItems: 'center' },
  filterCount: { position: 'absolute', right: -2, top: -2, minWidth: 16, minHeight: 16, borderRadius: 8, paddingHorizontal: 4, alignItems: 'center', justifyContent: 'center' }, filterCountText: { fontSize: 10, lineHeight: 14, fontWeight: '700' },
  list: { padding: 16 }, emptyList: { flexGrow: 1, padding: 24 }, gap: { height: 12 }, footer: { padding: 16, alignItems: 'center' }, errorText: { textAlign: 'center' }, emptyTitle: { fontSize: 24, lineHeight: 32, fontWeight: '600', marginTop: 24 }, emptySubtitle: { marginTop: 8, textAlign: 'center' },
  card: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 16, overflow: 'hidden' }, cardContent: { padding: 16 }, cardHeader: { flexDirection: 'row', alignItems: 'center' }, statusCircle: { width: 48, height: 48, borderRadius: 24, alignItems: 'center', justifyContent: 'center' }, statusEmoji: { fontSize: 24, lineHeight: 32 }, cardTitle: { flex: 1, marginLeft: 12 }, bold: { fontWeight: '700' }, medium: { fontWeight: '500' }, timestamp: { marginTop: 2 }, statusBadge: { borderRadius: 8, paddingHorizontal: 10, paddingVertical: 6 }, statusText: { fontSize: 11, lineHeight: 16, fontWeight: '700', letterSpacing: 0.5 },
  metaWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 16, rowGap: 12, marginTop: 16 }, meta: { flexDirection: 'row', alignItems: 'center' }, metaText: { marginLeft: 6 }, message: { borderWidth: 1, borderRadius: 8, flexDirection: 'row', alignItems: 'flex-start', padding: 12, marginTop: 12 }, messageText: { flex: 1, fontWeight: '500', marginLeft: 8 },
  filterSheet: { borderTopLeftRadius: 28, borderTopRightRadius: 28, overflow: 'hidden' }, filterHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 24, paddingBottom: 16 }, rule: { height: StyleSheet.hairlineWidth }, filterScroll: { flex: 1 }, filterContent: { padding: 24, paddingBottom: 12 }, filterGroup: { marginBottom: 24, gap: 8 }, chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 }, chip: { minHeight: 32, borderWidth: StyleSheet.hairlineWidth, borderRadius: 8, paddingHorizontal: 12, alignItems: 'center', justifyContent: 'center' }, applyArea: { borderTopWidth: StyleSheet.hairlineWidth, paddingHorizontal: 24, paddingTop: 16, paddingBottom: 24 }, applyButton: { minHeight: 52, borderRadius: 26, alignItems: 'center', justifyContent: 'center' },
});
