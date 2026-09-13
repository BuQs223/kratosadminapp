import { useReportSnapshot } from '@/hooks/use-report-snapshot';
import { checkInPresetRange, checkInCustomRange, parseFlutterDate } from '@/utils/flutter-date';
import { useQuery } from '@tanstack/react-query';
import React from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/app-text';
import { DateRangeDialog } from '@/components/calendar-dialog';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { MaterialIcon } from '@/components/material-icon';
import type { MaterialIconName } from '@/constants/material-icons.generated';
import { getCheckInStats } from '@/repositories/check-ins-repository';
import { lookupsRepository } from '@/repositories/lookups-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';
import { calendarDateFromLocalDate, calendarDateRangeLabel, todayCalendarDate } from '@/utils/calendar-date';

type TimePreset = 'today' | 'last7Days' | 'last30Days' | 'thisMonth' | 'custom';
const presetLabels: Record<TimePreset, string> = { today: 'Azi', last7Days: 'Ultimele 7 zile', last30Days: 'Ultimele 30 zile', thisMonth: 'Luna asta', custom: 'Custom' };

const presetRange = checkInPresetRange;

export default function CheckInStatsScreen() {
  const { colors } = useAppTheme();
  const initial = React.useMemo(() => presetRange('thisMonth'), []);
  const [preset, setPreset] = React.useState<TimePreset>('thisMonth');
  const [start, setStart] = React.useState(initial.start);
  const [end, setEnd] = React.useState(initial.end);
  const [gymId, setGymId] = React.useState<string>();
  const [openSelect, setOpenSelect] = React.useState<'preset' | 'gym' | null>(null);
  const [dateDialogOpen, setDateDialogOpen] = React.useState(false);
  const gymsQuery = useQuery({ queryKey: ['gym-lookups', 'app-check-in-stats'], queryFn: lookupsRepository.getGyms });
  const statsQuery = useQuery({ queryKey: ['check-in-stats', start, end, gymId], queryFn: () => getCheckInStats({ start, end, gymId }) });

  const reportSnapshot = useReportSnapshot(statsQuery.data);
  const applyPreset = (next: TimePreset) => {
    setOpenSelect(null);
    if (next !== 'custom') { setPreset(next); const range = presetRange(next); setStart(range.start); setEnd(range.end); }
    else setDateDialogOpen(true);
  };

  if (statsQuery.isLoading && !reportSnapshot) return <View style={[styles.center, { backgroundColor: colors.surfaceContainerLowest }]}><ActivityIndicator size="large" color={colors.primary} /></View>;
  const calendarRange = { start: start.slice(0, 10), end: calendarDateFromLocalDate(new Date(parseFlutterDate(end).getTime() - 1)) };
  const stats = reportSnapshot ?? { totalCheckIns: 0, busiestHours: [], topGyms: [] };
  return (
    <>
    <ScrollView style={{ backgroundColor: colors.surfaceContainerLowest }} contentContainerStyle={styles.content} contentInsetAdjustmentBehavior="automatic" refreshControl={<ManualRefreshControl tintColor={colors.primary} colors={[colors.primary]} onRefresh={() => statsQuery.refetch()} />}>
      {statsQuery.error ? <View style={[styles.error, { backgroundColor: colorWithAlpha(colors.error, 0.1) }]}><AppText selectable color={colors.error}>Eroare la încărcarea statisticilor: {statsQuery.error instanceof Error ? statsQuery.error.message : String(statsQuery.error)}</AppText></View> : null}
      <Panel>
        <SectionHeader icon="tune" title="Filtre" />
        <SelectField label="Perioadă" icon="date_range" value={presetLabels[preset]} open={openSelect === 'preset'} onPress={() => setOpenSelect((current) => current === 'preset' ? null : 'preset')}>
          {(Object.keys(presetLabels) as TimePreset[]).map((item) => <Option key={item} label={presetLabels[item]} selected={preset === item} onPress={() => applyPreset(item)} />)}
        </SelectField>
        <Pressable accessibilityRole="button" onPress={() => setDateDialogOpen(true)} style={({ pressed }) => [styles.range, { backgroundColor: colors.surfaceContainerHighest, opacity: pressed ? 0.72 : 1 }]}>
          <MaterialIcon name="calendar_month" size={18} color={colors.onSurfaceVariant} /><AppText style={styles.rangeText}>{calendarDateRangeLabel(calendarRange)}</AppText><AppText color={colors.primary} style={styles.bold}>Schimbă</AppText>
        </Pressable>
        <SelectField label="Sală" icon="fitness_center" value={gymsQuery.data?.find((gym) => gym.id === gymId)?.name ?? 'Toate sălile'} open={openSelect === 'gym'} onPress={() => setOpenSelect((current) => current === 'gym' ? null : 'gym')}>
          <Option label="Toate sălile" selected={!gymId} onPress={() => { setGymId(undefined); setOpenSelect(null); }} />
          {gymsQuery.data?.map((gym) => <Option key={gym.id} label={gym.name} selected={gymId === gym.id} onPress={() => { setGymId(gym.id); setOpenSelect(null); }} />)}
        </SelectField>
      </Panel>

      <Panel><View style={styles.totalRow}><View style={[styles.totalIcon, { backgroundColor: colorWithAlpha(colors.primary, 0.12) }]}><MaterialIcon name="check_circle_outline" size={24} color={colors.primary} /></View><View style={styles.totalCopy}><AppText variant="titleMedium" style={styles.totalLabel}>Total Check-ins</AppText><AppText style={styles.totalValue}>{stats.totalCheckIns.toLocaleString()}</AppText></View></View></Panel>
      <SectionCard icon="schedule" title="Busiest Hours">{stats.busiestHours.length ? stats.busiestHours.map((item, index) => <RankedRow key={item.hour} rank={index + 1} label={`${String(item.hour).padStart(2, '0')}:00 - ${String((item.hour + 1) % 24).padStart(2, '0')}:00`} value={item.checkIns} />) : <EmptyText text="Nu există check-ins în intervalul selectat" />}</SectionCard>
      {!gymId ? <SectionCard icon="fitness_center" title="Top Săli după Check-ins">{stats.topGyms.length ? stats.topGyms.map((item, index) => <RankedRow key={`${item.gymName}-${index}`} rank={index + 1} label={item.gymName} value={item.checkIns} />) : <EmptyText text="Nu există date pentru săli în intervalul selectat" />}</SectionCard> : null}
    </ScrollView>
    <DateRangeDialog visible={dateDialogOpen} value={{ ...calendarRange, end: calendarRange.end > todayCalendarDate() ? todayCalendarDate() : calendarRange.end }} minimumDate="2024-01-01" maximumDate={todayCalendarDate()} title="Interval check-ins" onCancel={() => setDateDialogOpen(false)} onApply={(range) => { const timestamps = checkInCustomRange(range.start, range.end); setStart(timestamps.start); setEnd(timestamps.end); setPreset('custom'); setDateDialogOpen(false); }} />
    </>
  );
}

function Panel({ children }: React.PropsWithChildren) { const { colors } = useAppTheme(); return <View style={[styles.panel, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5), backgroundColor: colors.surface }]}>{children}</View>; }
function SectionHeader({ icon, title }: { icon: MaterialIconName; title: string }) { const { colors } = useAppTheme(); return <View style={styles.sectionHeader}><MaterialIcon name={icon} size={20} color={colors.primary} /><AppText variant="titleMedium" style={styles.sectionTitle}>{title}</AppText></View>; }
function SelectField({ label, icon, value, open, onPress, children }: React.PropsWithChildren<{ label: string; icon: MaterialIconName; value: string; open: boolean; onPress: () => void }>) { const { colors } = useAppTheme(); return <View style={styles.selectWrap}><Pressable onPress={onPress} style={({ pressed }) => [styles.select, { borderColor: colors.outline, opacity: pressed ? 0.72 : 1 }]}><MaterialIcon name={icon} size={24} color={colors.onSurfaceVariant} /><View style={styles.selectCopy}><AppText variant="bodySmall" color={colors.onSurfaceVariant}>{label}</AppText><AppText variant="bodyLarge">{value}</AppText></View><MaterialIcon name="arrow_drop_down" size={24} color={colors.onSurfaceVariant} style={open ? styles.rotate : undefined} /></Pressable>{open ? <View style={[styles.menu, { backgroundColor: colors.surfaceContainerHigh, borderColor: colors.outlineVariant }]}>{children}</View> : null}</View>; }
function Option({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) { const { colors } = useAppTheme(); return <Pressable onPress={onPress} style={({ pressed }) => [styles.option, { opacity: pressed ? 0.6 : 1 }]}><AppText color={selected ? colors.primary : undefined} style={selected ? styles.bold : undefined}>{label}</AppText></Pressable>; }
function SectionCard({ icon, title, children }: React.PropsWithChildren<{ icon: MaterialIconName; title: string }>) { return <Panel><SectionHeader icon={icon} title={title} /><View style={styles.sectionBody}>{children}</View></Panel>; }
function RankedRow({ rank, label, value }: { rank: number; label: string; value: number }) { const { colors } = useAppTheme(); return <View style={[styles.ranked, { backgroundColor: colors.surfaceContainerHigh }]}><AppText variant="titleMedium" style={styles.rankedLabel}>{rank}. {label}</AppText><AppText variant="bodyLarge" color={colors.primary} style={styles.rankedValue}>{value.toLocaleString()}</AppText></View>; }
function EmptyText({ text }: { text: string }) { const { colors } = useAppTheme(); return <AppText color={colors.onSurfaceVariant}>{text}</AppText>; }

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' }, content: { padding: 16, gap: 16, paddingBottom: 24 }, error: { borderRadius: 12, padding: 12 }, panel: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 12, padding: 16 }, sectionHeader: { flexDirection: 'row', alignItems: 'center' }, sectionTitle: { fontWeight: '700', marginLeft: 8 }, selectWrap: { marginTop: 16, zIndex: 2 }, select: { minHeight: 56, borderWidth: 1, borderRadius: 4, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12 }, selectCopy: { flex: 1, marginLeft: 12 }, rotate: { transform: [{ rotate: '180deg' }] }, menu: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 8, marginTop: 4, overflow: 'hidden' }, option: { paddingHorizontal: 16, paddingVertical: 12 }, range: { minHeight: 48, borderRadius: 12, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, marginTop: 12 }, rangeText: { flex: 1, fontWeight: '600', marginLeft: 8 }, bold: { fontWeight: '700' }, picker: { borderRadius: 12, marginTop: 12, padding: 8 }, pickerTitle: { textAlign: 'center' }, pickerActions: { flexDirection: 'row', justifyContent: 'flex-end' }, pickerButton: { padding: 10, marginLeft: 8 }, totalRow: { flexDirection: 'row', alignItems: 'center' }, totalIcon: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' }, totalCopy: { flex: 1, marginLeft: 12 }, totalLabel: { fontWeight: '700' }, totalValue: { fontSize: 24, lineHeight: 32, fontWeight: '700', marginTop: 4 }, sectionBody: { marginTop: 16 }, ranked: { minHeight: 56, borderRadius: 14, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 14, paddingVertical: 16, marginBottom: 12 }, rankedLabel: { flex: 1, fontWeight: '500' }, rankedValue: { fontWeight: '700', letterSpacing: 0.3 },
});
