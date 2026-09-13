import { useReportSnapshot } from '@/hooks/use-report-snapshot';
import { LinearGradient } from 'expo-linear-gradient';
import { Stack } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import React from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/app-text';
import { DateRangeDialog } from '@/components/calendar-dialog';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { MaterialIcon } from '@/components/material-icon';
import type { MaterialIconName } from '@/constants/material-icons.generated';
import { getGymTierCheckInStats, type GymTierCheckInStats } from '@/repositories/check-ins-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';
import { calendarDateRangeLabel, todayCalendarDate } from '@/utils/calendar-date';

export default function GoldCheckInsScreen() {
  const { colors } = useAppTheme();
  const [start, setStart] = React.useState(() => `${todayCalendarDate().slice(0, 7)}-01`);
  const [end, setEnd] = React.useState(todayCalendarDate);
  const [dateVisible, setDateVisible] = React.useState(false);
  const statsQuery = useQuery({ queryKey: ['gold-check-ins', start, end], queryFn: () => getGymTierCheckInStats(start, end) });
  const reportSnapshot = useReportSnapshot(statsQuery.data);
  const result = reportSnapshot ?? { gyms: [], kratosOneAndTwoUniqueGoldMembers: 0 };
  const stats = result.gyms;
  const kratos1 = stats.find((item) => item.gymName === 'Kratos 1');
  const kratos2 = stats.find((item) => item.gymName === 'Kratos 2');
  const totals = stats.reduce((current, item) => ({ goldMembers: current.goldMembers + item.uniqueGoldMembers, goldCheckIns: current.goldCheckIns + item.totalGoldCheckIns, silverMembers: current.silverMembers + item.uniqueSilverMembers, silverCheckIns: current.silverCheckIns + item.totalSilverCheckIns }), { goldMembers: 0, goldCheckIns: 0, silverMembers: 0, silverCheckIns: 0 });

  return (
    <View style={[styles.screen, { backgroundColor: colors.surfaceContainerLowest }]}>
      <Stack.Screen options={{ title: 'Gold la Kratos 1 & 2', headerRight: () => <Pressable accessibilityRole="button" accessibilityLabel="Schimbă perioada" hitSlop={10} onPress={() => setDateVisible(true)} style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, padding: 6 })}><MaterialIcon name="date_range" size={24} color={colors.onSurfaceVariant} /></Pressable> }} />
      {statsQuery.isLoading ? <View style={styles.center}><ActivityIndicator size="large" color={colors.primary} /></View> : (
        <ScrollView contentContainerStyle={styles.content} contentInsetAdjustmentBehavior="automatic" refreshControl={<ManualRefreshControl tintColor={colors.primary} colors={[colors.primary]} onRefresh={() => statsQuery.refetch()} />}>
          {statsQuery.error ? <View style={[styles.error, { backgroundColor: colorWithAlpha(colors.error, 0.1) }]}><AppText selectable color={colors.error}>Eroare: {statsQuery.error instanceof Error ? statsQuery.error.message : String(statsQuery.error)}</AppText></View> : null}
          <View style={[styles.dateCard, { backgroundColor: colors.primaryContainer }]}><MaterialIcon name="calendar_today" size={18} color={colors.onPrimaryContainer} /><AppText variant="titleSmall" color={colors.onPrimaryContainer} style={styles.dateText}>{calendarDateRangeLabel({ start, end })}</AppText><Pressable onPress={() => setDateVisible(true)} hitSlop={8}><AppText color={colors.primary} style={styles.bold}>Schimbă</AppText></Pressable></View>
          <AppText variant="titleLarge" style={styles.sectionTitle}>🥇 Membri Gold la Kratos 1 & 2</AppText>
          <AppText color={colors.onSurfaceVariant} style={styles.sectionSubtitle}>Membrii Gold care au folosit accesul la Kratos 1 sau Kratos 2</AppText>
          <View style={styles.row}><GoldGymCard name="Kratos 1" members={kratos1?.uniqueGoldMembers ?? 0} checkIns={kratos1?.totalGoldCheckIns ?? 0} color="#FFB300" /><View style={styles.rowGap} /><GoldGymCard name="Kratos 2" members={kratos2?.uniqueGoldMembers ?? 0} checkIns={kratos2?.totalGoldCheckIns ?? 0} color="#FFA000" /></View>
          <CombinedGoldCard members={result.kratosOneAndTwoUniqueGoldMembers} checkIns={(kratos1?.totalGoldCheckIns ?? 0) + (kratos2?.totalGoldCheckIns ?? 0)} />
          <AppText variant="titleLarge" style={styles.comparisonTitle}>📊 Comparație pe toate sălile</AppText>
          <View style={styles.row}><SummaryCard title="Total Gold" value={totals.goldMembers} subtitle={`${totals.goldCheckIns} check-ins`} color="#FFB300" icon="workspace_premium" /><View style={styles.rowGap} /><SummaryCard title="Total Silver" value={totals.silverMembers} subtitle={`${totals.silverCheckIns} check-ins`} color="#9E9E9E" icon="verified" /></View>
          <View style={styles.gymList}>{stats.map((item) => <GymDetailCard key={item.gymId} stat={item} />)}</View>
        </ScrollView>
      )}
      <DateRangeDialog visible={dateVisible} value={{ start, end }} minimumDate="2024-01-01" maximumDate={todayCalendarDate()} title="Interval Gold Check-ins" onCancel={() => setDateVisible(false)} onApply={(range) => { setStart(range.start); setEnd(range.end); setDateVisible(false); }} />
    </View>
  );
}

function GoldGymCard({ name, members, checkIns, color }: { name: string; members: number; checkIns: number; color: string }) {
  const { colors } = useAppTheme();
  return <View style={[styles.goldCard, { borderColor: colorWithAlpha(color, 0.3) }]}><LinearGradient colors={[colorWithAlpha(color, 0.15), colorWithAlpha(color, 0.05)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} /><View style={styles.cardNameRow}><MaterialIcon name="fitness_center" size={20} color={color} /><AppText variant="titleMedium" style={styles.cardName}>{name}</AppText></View><AppText variant="headlineLarge" color={color} style={styles.bigValue}>{members}</AppText><AppText variant="bodySmall" color={colors.onSurfaceVariant}>membri unici</AppText><View style={[styles.checkInsBadge, { backgroundColor: colorWithAlpha(color, 0.2) }]}><AppText color={color} style={styles.checkInsText}>{checkIns} check-ins</AppText></View></View>;
}
function CombinedGoldCard({ members, checkIns }: { members: number; checkIns: number }) { const color = '#FFA000'; return <View style={[styles.combined, { borderColor: colorWithAlpha(color, 0.3) }]}><LinearGradient colors={[colorWithAlpha(color, 0.15), colorWithAlpha(color, 0.05)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} /><View style={styles.medal}><AppText style={styles.medalEmoji}>🥇</AppText></View><View style={styles.combinedCopy}><AppText variant="titleMedium" style={styles.bold}>Total Gold la K1 + K2</AppText><AppText color="#FF8F00" style={styles.combinedValue}>{members} membri unici • {checkIns} check-ins</AppText></View></View>; }
function SummaryCard({ title, value, subtitle, color, icon }: { title: string; value: number; subtitle: string; color: string; icon: MaterialIconName }) { const { colors } = useAppTheme(); return <View style={[styles.summaryCard, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5) }]}><View style={styles.summaryHeader}><View style={styles.summaryIcon}><MaterialIcon name={icon} size={20} color={color} /></View><AppText variant="titleSmall" style={styles.summaryTitle}>{title}</AppText></View><AppText variant="headlineMedium" color={color} style={styles.bigValue}>{value}</AppText><AppText variant="bodySmall" color={colors.onSurfaceVariant}>{subtitle}</AppText></View>; }
function GymDetailCard({ stat }: { stat: GymTierCheckInStats }) { const { colors } = useAppTheme(); return <View style={[styles.detailCard, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5) }]}><View style={styles.detailHeader}><View style={[styles.detailIcon, { backgroundColor: colors.primaryContainer }]}><MaterialIcon name="fitness_center" size={20} color={colors.primary} /></View><AppText variant="titleMedium" style={styles.detailName}>{stat.gymName}</AppText>{stat.gymName === 'Kratos 3' ? <View style={[styles.goldOnly, { backgroundColor: colors.tertiaryContainer }]}><AppText color={colors.onTertiaryContainer} style={styles.goldOnlyText}>Gold Only</AppText></View> : null}</View><View style={styles.statRow}><StatColumn label="🥇 Gold" value={stat.uniqueGoldMembers} subtitle={`${stat.totalGoldCheckIns} check-ins`} color="#FFB300" /><View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} /><StatColumn label="🥈 Silver" value={stat.uniqueSilverMembers} subtitle={`${stat.totalSilverCheckIns} check-ins`} color="#9E9E9E" /></View></View>; }
function StatColumn({ label, value, subtitle, color }: { label: string; value: number; subtitle: string; color: string }) { const { colors } = useAppTheme(); return <View style={styles.statColumn}><AppText color={colors.onSurfaceVariant} style={styles.statLabel}>{label}</AppText><AppText color={color} style={styles.statValue}>{value}</AppText><AppText variant="bodySmall" color={colors.onSurfaceVariant}>{subtitle}</AppText></View>; }


const styles = StyleSheet.create({
  screen: { flex: 1 }, center: { flex: 1, alignItems: 'center', justifyContent: 'center' }, content: { padding: 16, paddingBottom: 24 }, error: { borderRadius: 12, padding: 12, marginBottom: 12 }, dateCard: { minHeight: 52, borderRadius: 12, flexDirection: 'row', alignItems: 'center', padding: 12 }, dateText: { flex: 1, fontWeight: '600', marginLeft: 8 }, bold: { fontWeight: '700' }, sectionTitle: { fontWeight: '700', marginTop: 24 }, sectionSubtitle: { marginTop: 8, marginBottom: 16 }, row: { flexDirection: 'row' }, rowGap: { width: 12 }, goldCard: { flex: 1, minHeight: 190, borderWidth: 1, borderRadius: 16, overflow: 'hidden', padding: 16 }, cardNameRow: { flexDirection: 'row', alignItems: 'center' }, cardName: { flex: 1, fontWeight: '700', marginLeft: 8 }, bigValue: { fontWeight: '700', marginTop: 16 }, checkInsBadge: { alignSelf: 'flex-start', borderRadius: 8, paddingHorizontal: 8, paddingVertical: 4, marginTop: 8 }, checkInsText: { fontSize: 11, lineHeight: 16, fontWeight: '600' }, combined: { minHeight: 88, borderWidth: 1, borderRadius: 16, overflow: 'hidden', padding: 16, flexDirection: 'row', alignItems: 'center', marginTop: 12 }, medal: { width: 56, height: 56, borderRadius: 28, backgroundColor: '#241C07CC', alignItems: 'center', justifyContent: 'center' }, medalEmoji: { fontSize: 28, lineHeight: 36 }, combinedCopy: { flex: 1, marginLeft: 16 }, combinedValue: { fontWeight: '600', marginTop: 4 }, comparisonTitle: { fontWeight: '700', marginTop: 32, marginBottom: 16 }, summaryCard: { flex: 1, minHeight: 150, borderWidth: StyleSheet.hairlineWidth, borderRadius: 16, padding: 16 }, summaryHeader: { flexDirection: 'row', alignItems: 'center' }, summaryIcon: { width: 36, height: 36, borderRadius: 8, backgroundColor: '#424242', alignItems: 'center', justifyContent: 'center' }, summaryTitle: { flex: 1, fontWeight: '600', marginLeft: 8 }, gymList: { gap: 12, marginTop: 16 }, detailCard: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 16, padding: 16 }, detailHeader: { flexDirection: 'row', alignItems: 'center' }, detailIcon: { width: 40, height: 40, borderRadius: 10, alignItems: 'center', justifyContent: 'center' }, detailName: { flex: 1, fontWeight: '700', marginLeft: 12 }, goldOnly: { borderRadius: 8, paddingHorizontal: 8, paddingVertical: 4 }, goldOnlyText: { fontSize: 11, lineHeight: 16, fontWeight: '600' }, statRow: { flexDirection: 'row', alignItems: 'center', marginTop: 16 }, statColumn: { flex: 1, alignItems: 'center' }, statLabel: { fontSize: 12, lineHeight: 16 }, statValue: { fontSize: 24, lineHeight: 32, fontWeight: '700', marginTop: 4 }, divider: { width: 1, height: 50 }, modalBackdrop: { flex: 1, backgroundColor: '#00000066', alignItems: 'center', justifyContent: 'center', padding: 24 }, dateDialog: { width: '100%', maxWidth: 420, borderRadius: 28, padding: 24 }, dateChoiceRow: { flexDirection: 'row', gap: 8, marginTop: 16 }, dateChoice: { flex: 1, borderWidth: 1, borderRadius: 8, padding: 10 }, dialogActions: { flexDirection: 'row', justifyContent: 'flex-end' }, dialogButton: { padding: 12, marginLeft: 8 },
});
