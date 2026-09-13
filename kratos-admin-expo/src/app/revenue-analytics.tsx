import { useReportSnapshot } from '@/hooks/use-report-snapshot';
import { elapsedDays, parseFlutterDate, revenueAnalyticsRange } from '@/utils/flutter-date';
import { BottomSheetScrollView } from '@gorhom/bottom-sheet';
import { LinearGradient } from 'expo-linear-gradient';
import { router, Stack } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import React from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, View, useWindowDimensions } from 'react-native';
import Svg, { Circle, Defs, G, Line, LinearGradient as SvgGradient, Path, Rect, Stop, Text as SvgText } from 'react-native-svg';

import { AppText } from '@/components/app-text';
import { BottomSheetModal } from '@/components/bottom-sheet-modal';
import { DateRangeDialog } from '@/components/calendar-dialog';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { MaterialIcon } from '@/components/material-icon';
import { lookupsRepository, type LookupOption } from '@/repositories/lookups-repository';
import { getRevenueAnalytics } from '@/repositories/revenue-repository';
import {
  calendarDateFromLocalDate,
  formatCalendarDate,
  type CalendarDate,
} from '@/utils/calendar-date';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

type TimeRange = '7days' | '30days' | '90days' | 'year' | 'all' | 'custom';
const rangeLabels: Record<Exclude<TimeRange, 'custom'>, string> = { '7days': '7 zile', '30days': '30 zile', '90days': '90 zile', year: 'An curent', all: 'Tot timpul' };


export default function RevenueAnalyticsScreen() {
  const { colors } = useAppTheme(); const [gymId, setGymId] = React.useState<string>(); const [range, setRange] = React.useState<TimeRange>('30days'); const [customStart, setCustomStart] = React.useState<CalendarDate>(); const [customEnd, setCustomEnd] = React.useState<CalendarDate>(); const [filterVisible, setFilterVisible] = React.useState(false);
  const analyticsQuery = useQuery({ queryKey: ['revenue-analytics', gymId, range, customStart, customEnd], queryFn: () => { const resolved = revenueAnalyticsRange(range, customStart, customEnd); return getRevenueAnalytics({ startDate: resolved.start, endDate: resolved.end, gymId, trendInterval: range === '7days' || range === 'custom' ? 'day' : 'week' }); } }); const gymsQuery = useQuery({ queryKey: ['gym-lookups', 'app-revenue-analytics'], queryFn: lookupsRepository.getGyms }); const active = Number(Boolean(gymId)) + Number(range !== '30days');
  const reportSnapshot = useReportSnapshot(analyticsQuery.data);
  if (analyticsQuery.isLoading) return <View style={[styles.center, { backgroundColor: colors.surfaceContainerLowest }]}><ActivityIndicator size="large" color={colors.primary} /></View>;
  const data = reportSnapshot ?? { byPlan: [], byGym: [], trend: [], stats: { totalCents: 0, cashCents: 0, cardCents: 0, transactionCount: 0, averageTransactionCents: 0 } };
  return <View style={[styles.screen, { backgroundColor: colors.surfaceContainerLowest }]}><Stack.Screen options={{ title: 'Analiză Venituri', headerRight: () => <Pressable onPress={() => setFilterVisible(true)} hitSlop={10} style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, padding: 6 })}><MaterialIcon name="filter_list" size={24} color={colors.onSurfaceVariant} />{active ? <View style={[styles.badge, { backgroundColor: colors.error }]}><AppText color="#FFFFFF" style={styles.badgeText}>{active}</AppText></View> : null}</Pressable> }} /><ScrollView contentContainerStyle={styles.content} contentInsetAdjustmentBehavior="automatic" refreshControl={<ManualRefreshControl tintColor={colors.primary} colors={[colors.primary]} onRefresh={() => analyticsQuery.refetch()} />}>
    {analyticsQuery.error ? <AppText selectable color={colors.error}>Eroare la încărcarea datelor: {analyticsQuery.error instanceof Error ? analyticsQuery.error.message : String(analyticsQuery.error)}</AppText> : null}
    <Pressable onPress={() => router.push('/period-comparison')} style={[styles.quick, { backgroundColor: colors.surface, borderColor: colors.outlineVariant }]}><View style={styles.quickIcon}><MaterialIcon name="compare_arrows" size={24} color="#512DA8" /></View><View style={styles.quickCopy}><AppText variant="titleSmall" color={colors.primary} style={styles.bold}>Comparație Perioade</AppText><AppText variant="bodySmall" color="#757575" style={styles.quickSubtitle}>Compară veniturile între două perioade diferite</AppText></View><MaterialIcon name="chevron_right" size={24} color="#7E57C2" /></Pressable>
    <CompactStat title="Total" value={currency(data.stats.totalCents)} emoji="💰" color="#8E24AA" /><CompactStat title="Cash" value={currency(data.stats.cashCents)} emoji="💵" color="#43A047" /><CompactStat title="Card" value={currency(data.stats.cardCents)} emoji="💳" color="#1E88E5" />
    <Section title="Tendință Venituri"><TrendChart rows={data.trend} daily={range === '7days' || range === 'custom'} /></Section>
    <Section title="Venituri pe Plan"><Bars rows={data.byPlan} /></Section>
    <Section title="Venituri pe Sală"><GymDonut rows={data.byGym} /></Section>
  </ScrollView>{filterVisible ? <AnalyticsFilter visible gyms={gymsQuery.data ?? []} gymId={gymId} range={range} start={customStart} end={customEnd} onClose={() => setFilterVisible(false)} onClear={() => { setGymId(undefined); setRange('30days'); setCustomStart(undefined); setCustomEnd(undefined); setFilterVisible(false); }} onApply={(next) => { setGymId(next.gymId); setRange(next.range); setCustomStart(next.start); setCustomEnd(next.end); setFilterVisible(false); }} /> : null}</View>;
}

function Section({ title, children }: React.PropsWithChildren<{ title: string }>) { return <View style={styles.section}><AppText variant="titleLarge" style={styles.sectionTitle}>{title}</AppText>{children}</View>; }
function CompactStat({ title, value, emoji, color }: { title: string; value: string; emoji: string; color: string }) { const { colors } = useAppTheme(); return <View style={[styles.stat, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5) }]}><LinearGradient colors={[colorWithAlpha(color, 0.05), colorWithAlpha(color, 0.02)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} /><View style={[styles.statIcon, { backgroundColor: colorWithAlpha(color, 0.15) }]}><AppText style={styles.emoji}>{emoji}</AppText></View><View style={styles.statCopy}><AppText variant="titleLarge" style={styles.bold}>{value}</AppText><AppText color={color} style={styles.statTitle}>{title}</AppText></View></View>; }
function ChartCard({ children }: React.PropsWithChildren) { const { colors } = useAppTheme(); return <View style={[styles.chart, { borderColor: colors.outlineVariant }]}>{children}</View>; }
function TrendChart({ rows, daily }: { rows: Record<string, unknown>[]; daily: boolean }) {
  const { colors } = useAppTheme();
  const { width } = useWindowDimensions();
  const [selectedIndex, setSelectedIndex] = React.useState<number | null>(null);
  if (!rows.length) return <Empty />;

  const chartWidth = Math.max(280, width - 66);
  const height = 280;
  const values = rows.map((row) => Number(row.total_revenue ?? 0) / 100);
  const max = Math.max(...values) * 1.1 || 1;
  const left = 54;
  const right = 10;
  const top = 18;
  const bottom = 44;
  const plotW = chartWidth - left - right;
  const plotH = height - top - bottom;
  const points = values.map((value, index) => ({
    x: left + (values.length === 1 ? plotW / 2 : index / (values.length - 1) * plotW),
    y: top + (1 - value / max) * plotH,
  }));
  // fl_chart 0.69 uses cubic control points with curveSmoothness = 0.35.
  let tangent = { x: 0, y: 0 };
  let path = `M ${points[0].x} ${points[0].y}`;
  for (let index = 1; index < points.length; index++) {
    const previous = points[index - 1], current = points[index], next = points[index + 1] ?? current;
    const first = { x: previous.x + tangent.x, y: previous.y + tangent.y };
    tangent = { x: (next.x - previous.x) * 0.175, y: (next.y - previous.y) * 0.175 };
    path += ` C ${first.x} ${first.y} ${current.x - tangent.x} ${current.y - tangent.y} ${current.x} ${current.y}`;
  }
  const area = `${path} L ${points.at(-1)?.x} ${top + plotH} L ${points[0]?.x} ${top + plotH} Z`;
  const validSelectedIndex = selectedIndex !== null && selectedIndex < rows.length ? selectedIndex : null;
  const selectedPoint = validSelectedIndex === null ? null : points[validSelectedIndex];
  const selectedRow = validSelectedIndex === null ? null : rows[validSelectedIndex];
  const tooltipWidth = 154;
  const tooltipHeight = 48;
  const tooltipX = selectedPoint ? Math.max(2, Math.min(chartWidth - tooltipWidth - 2, selectedPoint.x - tooltipWidth / 2)) : 0;
  const tooltipY = selectedPoint ? (selectedPoint.y >= tooltipHeight + 16 ? selectedPoint.y - tooltipHeight - 10 : selectedPoint.y + 12) : 0;
  const pointSpacing = values.length > 1 ? plotW / (values.length - 1) : plotW;
  const hitRadius = Math.max(12, Math.min(22, pointSpacing / 2));

  return (
    <ChartCard>
      <View style={styles.chartInfo}>
        <MaterialIcon name="info_outline" size={16} color="#8E24AA" />
        <AppText variant="bodySmall" color="#8E24AA" style={styles.chartInfoText}>
          {daily ? 'Fiecare punct = venit pentru ziua respectivă' : 'Fiecare punct = total pe săptămână (Lun-Dum). Ultimul punct poate fi săptămână parțială.'}
        </AppText>
      </View>
      <Svg width={chartWidth} height={height}>
        {[0, .25, .5, .75, 1].map((ratio) => (
          <G key={ratio}>
            <Line x1={left} y1={top + ratio * plotH} x2={left + plotW} y2={top + ratio * plotH} stroke={colorWithAlpha(colors.outlineVariant, .3)} />
            <SvgText x={left - 6} y={top + ratio * plotH + 4} textAnchor="end" fontSize="10" fill={colors.onSurfaceVariant}>{compact(max * (1 - ratio))}</SvgText>
          </G>
        ))}
        <Defs>
          <SvgGradient id="revenue-fill" x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor="#8E24AA" stopOpacity="0.3" />
            <Stop offset="1" stopColor="#8E24AA" stopOpacity="0.05" />
          </SvgGradient>
        </Defs>
        <Path d={area} fill="url(#revenue-fill)" />
        <Path d={path} fill="none" stroke="#8E24AA" strokeWidth="4" strokeLinejoin="round" />
        {points.map((point, index) => (
          <G key={index}>
            <Circle cx={point.x} cy={point.y} r={validSelectedIndex === index ? 6 : 4} fill="#FFFFFF" stroke="#8E24AA" strokeWidth={validSelectedIndex === index ? 3 : 2} />
            {index % (rows.length > 10 ? 3 : rows.length > 7 ? 2 : 1) === 0 ? (
              <SvgText x={point.x} y={height - 14} textAnchor="middle" fontSize="9" fill={colors.onSurfaceVariant}>{shortPeriod(String(rows[index]?.period ?? ''), daily)}</SvgText>
            ) : null}
          </G>
        ))}
        {selectedPoint && selectedRow ? (
          <G pointerEvents="none">
            <Line x1={selectedPoint.x} y1={top} x2={selectedPoint.x} y2={top + plotH} stroke={colorWithAlpha('#8E24AA', .35)} strokeDasharray="4 4" />
            <Rect x={tooltipX} y={tooltipY} width={tooltipWidth} height={tooltipHeight} rx="8" fill="#2B2730" />
            <SvgText x={tooltipX + tooltipWidth / 2} y={tooltipY + 18} textAnchor="middle" fontSize="10" fontWeight="600" fill="#FFFFFF">{trendPeriodLabel(String(selectedRow.period ?? ''), daily)}</SvgText>
            <SvgText x={tooltipX + tooltipWidth / 2} y={tooltipY + 36} textAnchor="middle" fontSize="11" fontWeight="700" fill="#FFFFFF">{currency(Number(selectedRow.total_revenue ?? 0))}</SvgText>
          </G>
        ) : null}
        {points.map((point, index) => (
          <Circle
            key={`hit-${index}`}
            cx={point.x}
            cy={point.y}
            r={hitRadius}
            fill="transparent"
            accessible
            accessibilityLabel={`${trendPeriodLabel(String(rows[index]?.period ?? ''), daily)}, ${currency(Number(rows[index]?.total_revenue ?? 0))}`}
            onPress={() => setSelectedIndex(index)}
          />
        ))}
      </Svg>
    </ChartCard>
  );
}
function Bars({ rows }: { rows: Record<string, unknown>[] }) { const { colors } = useAppTheme(); if (!rows.length) return <Empty />; const max = Math.max(...rows.map((row) => Number(row.total_revenue ?? 0)), 1); return <ChartCard>{rows.map((row, index) => { const cents = Number(row.total_revenue ?? 0); return <View key={`${row.plan_name}-${index}`} style={styles.barItem}><View style={styles.barLabel}><AppText numberOfLines={1} style={styles.barName}>{String(row.plan_name ?? 'Unknown')}</AppText><AppText color="#8E24AA" style={styles.bold}>{currency(cents)}</AppText></View><View style={[styles.track, { backgroundColor: colorWithAlpha('#8E24AA', .1) }]}><View style={[styles.fill, { width: `${cents / max * 100}%` }]} /></View><AppText variant="bodySmall" color={colors.onSurfaceVariant}>{Number(row.transaction_count ?? 0)} tranzacții</AppText></View>; })}</ChartCard>; }
function GymDonut({ rows }: { rows: Record<string, unknown>[] }) {
  const { colors } = useAppTheme();
  const [selectedIndex, setSelectedIndex] = React.useState<number | null>(null);
  if (!rows.length) return <Empty />;

  const palette = ['#8E24AA', '#43A047', '#1E88E5', '#FB8C00', '#E53935'];
  const total = rows.reduce((sum, row) => sum + Number(row.total_revenue ?? 0), 0);
  const denominator = total || 1;
  const radius = 84;
  const circumference = 2 * Math.PI * radius;
  const segments = rows.map((row, index) => {
    const fraction = Number(row.total_revenue ?? 0) / denominator;
    const dash = fraction * circumference;
    const offset = rows.slice(0, index).reduce((sum, previous) => sum + Number(previous.total_revenue ?? 0) / denominator * circumference, 0);
    return { dash, offset };
  });
  const validSelectedIndex = selectedIndex !== null && selectedIndex < rows.length ? selectedIndex : null;
  const selectedRow = validSelectedIndex === null ? null : rows[validSelectedIndex];
  const centerTitle = selectedRow ? String(selectedRow.gym_name ?? 'Unknown') : 'Total';
  const centerValue = currency(selectedRow ? Number(selectedRow.total_revenue ?? 0) : total);
  const select = (index: number) => setSelectedIndex((current) => current === index ? null : index);

  return (
    <ChartCard>
      <Svg width="100%" height={250} viewBox="0 0 250 250">
        <G rotation="-90" origin="125,125">
          {segments.map((segment, index) => (
            <Circle
              key={index}
              cx="125"
              cy="125"
              r={radius}
              fill="none"
              stroke={palette[index % palette.length]}
              strokeWidth={validSelectedIndex === index ? 48 : 42}
              strokeOpacity={validSelectedIndex === null || validSelectedIndex === index ? 1 : .42}
              strokeDasharray={`${Math.max(0, segment.dash - 5)} ${circumference - Math.max(0, segment.dash - 5)}`}
              strokeDashoffset={-segment.offset}
              accessible
              accessibilityLabel={`${String(rows[index]?.gym_name ?? 'Unknown')}, ${currency(Number(rows[index]?.total_revenue ?? 0))}`}
              onPress={() => select(index)}
            />
          ))}
        </G>
        <Circle cx="125" cy="125" r="58" fill={colors.surfaceContainerLowest} />
        <SvgText x="125" y="119" textAnchor="middle" fontSize="11" fontWeight="600" fill={colors.onSurfaceVariant}>{centerTitle.slice(0, 22)}</SvgText>
        <SvgText x="125" y="139" textAnchor="middle" fontSize="12" fontWeight="700" fill={validSelectedIndex === null ? colors.onSurface : palette[validSelectedIndex % palette.length]}>{centerValue}</SvgText>
      </Svg>
      <View style={styles.legend}>
        {rows.map((row, index) => {
          const selected = validSelectedIndex === index;
          return (
            <Pressable
              key={index}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              accessibilityLabel={`${String(row.gym_name ?? 'Unknown')}, ${currency(Number(row.total_revenue ?? 0))}`}
              onPress={() => select(index)}
              style={({ pressed }) => [styles.legendItem, { backgroundColor: selected ? colorWithAlpha(palette[index % palette.length], .14) : 'transparent', opacity: pressed ? .58 : 1 }]}>
              <View style={[styles.legendDot, { backgroundColor: palette[index % palette.length] }]} />
              <AppText variant="bodySmall" style={selected ? styles.bold : undefined}>{String(row.gym_name ?? 'Unknown')} · {currency(Number(row.total_revenue ?? 0))}</AppText>
            </Pressable>
          );
        })}
      </View>
    </ChartCard>
  );
}
function Empty() { const { colors } = useAppTheme(); return <ChartCard><AppText color={colors.onSurfaceVariant} style={styles.empty}>Nicio dată disponibilă</AppText></ChartCard>; }

function AnalyticsFilter({ visible, gyms, gymId, range, start, end, onClose, onClear, onApply }: { visible: boolean; gyms: LookupOption[]; gymId?: string; range: TimeRange; start?: CalendarDate; end?: CalendarDate; onClose: () => void; onClear: () => void; onApply: (value: { gymId?: string; range: TimeRange; start?: CalendarDate; end?: CalendarDate }) => void }) {
  const { colors } = useAppTheme();
  const { height } = useWindowDimensions();
  const [draftGym, setDraftGym] = React.useState(gymId);
  const [draftRange, setDraftRange] = React.useState(range);
  const [draftStart, setDraftStart] = React.useState(start);
  const [draftEnd, setDraftEnd] = React.useState(end);
  const [calendarOpen, setCalendarOpen] = React.useState(false);
  const selectedRange = draftStart && draftEnd ? { start: draftStart, end: draftEnd } : undefined;
  return <BottomSheetModal visible={visible} onClose={onClose} dynamic scrollable maxDynamicContentSize={height * 0.82} sheetStyle={[styles.sheet, { backgroundColor: colors.surface }]}>
      <BottomSheetScrollView contentContainerStyle={[styles.filterContent, { paddingBottom: 16 }]}>
        <View style={styles.filterHeader}><AppText variant="titleLarge" style={styles.bold}>Filtre Analiză</AppText><Pressable onPress={onClear}><AppText color={colors.primary}>Resetează</AppText></Pressable></View>
        <FilterGroup title="Perioadă">{Object.entries(rangeLabels).map(([key, label]) => <Chip key={key} label={label} selected={draftRange === key} onPress={() => setDraftRange(key as TimeRange)} />)}</FilterGroup>
        <Pressable accessibilityRole="button" accessibilityLabel="Selectează perioada personalizată" onPress={() => setCalendarOpen(true)} style={[styles.dateSelect, { borderColor: colors.outline }]}>
          <MaterialIcon name="date_range" size={20} color={colors.primary} />
          <AppText style={styles.dateSelectText}>{draftRange === 'custom' && draftStart && draftEnd ? `${shortDate(draftStart)} - ${shortDate(draftEnd)}` : 'Perioadă personalizată'}</AppText>
        </Pressable>
        <DateRangeDialog visible={calendarOpen} title="Selectează perioada" minimumDate="2020-01-01" maximumDate={calendarDateFromLocalDate(new Date())} value={selectedRange} onCancel={() => setCalendarOpen(false)} onApply={(selected) => { setDraftRange('custom'); setDraftStart(selected.start); setDraftEnd(selected.end); setCalendarOpen(false); }} />
        <FilterGroup title="Sală"><Chip label="Toate" selected={!draftGym} onPress={() => setDraftGym(undefined)} />{gyms.map((gym) => <Chip key={gym.id} label={gym.name} selected={draftGym === gym.id} onPress={() => setDraftGym(gym.id)} />)}</FilterGroup>
        <Pressable onPress={() => onApply({ gymId: draftGym, range: draftRange, start: draftStart, end: draftEnd })} style={[styles.apply, { backgroundColor: colors.primary }]}><AppText color={colors.onPrimary} style={styles.bold}>Aplică Filtre</AppText></Pressable>
      </BottomSheetScrollView>
    </BottomSheetModal>;
}
function FilterGroup({ title, children }: React.PropsWithChildren<{ title: string }>) { return <View style={styles.filterGroup}><AppText variant="titleMedium" style={styles.bold}>{title}</AppText><View style={styles.chips}>{children}</View></View>; } function Chip({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) { const { colors } = useAppTheme(); return <Pressable onPress={onPress} style={[styles.chip, { backgroundColor: selected ? colors.secondaryContainer : colors.surfaceContainerLow, borderColor: selected ? colors.onSurfaceVariant : colors.outlineVariant }]}><AppText>{label}</AppText></Pressable>; }
function currency(cents: number) { return `RON ${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`; } function compact(value: number) { return Intl.NumberFormat('ro', { notation: 'compact', maximumFractionDigits: 1 }).format(value); } function shortDate(date: CalendarDate) { return formatCalendarDate(date, { day: '2-digit', month: 'short', year: 'numeric' }); } function shortPeriod(value: string, daily: boolean) { const date = parseFlutterDate(value); return daily ? `${String(date.getDate()).padStart(2,'0')} ${date.toLocaleDateString('en-GB',{month:'short'})}` : `${String(date.getDate()).padStart(2,'0')}/${String(date.getMonth()+1).padStart(2,'0')}-${String(elapsedDays(date, 6).getDate()).padStart(2,'0')}/${String(elapsedDays(date, 6).getMonth()+1).padStart(2,'0')}`; }
function trendPeriodLabel(value: string, daily: boolean) { const start = parseFlutterDate(value); if (Number.isNaN(start.getTime())) return 'Perioadă necunoscută'; const format = (date: Date, year = false) => date.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', ...(year ? { year: 'numeric' as const } : {}) }); if (daily) return format(start, true); const end = elapsedDays(start, 6); return `${format(start)} - ${format(end, true)}`; }
const styles = StyleSheet.create({ screen:{flex:1},center:{flex:1,alignItems:'center',justifyContent:'center'},content:{padding:16,paddingBottom:24},badge:{position:'absolute',right:-2,top:-2,minWidth:16,minHeight:16,borderRadius:8,alignItems:'center',justifyContent:'center'},badgeText:{fontSize:10,lineHeight:14,fontWeight:'700'},quick:{minHeight:82,borderWidth:StyleSheet.hairlineWidth,borderRadius:12,flexDirection:'row',alignItems:'center',paddingHorizontal:16,paddingVertical:14},quickIcon:{padding:10,borderRadius:10,backgroundColor:'#D1C4E9'},quickCopy:{flex:1,marginLeft:16},quickSubtitle:{marginTop:4},bold:{fontWeight:'700'},stat:{height:80,borderWidth:StyleSheet.hairlineWidth,borderRadius:16,overflow:'hidden',flexDirection:'row',alignItems:'center',padding:16,marginTop:6},statIcon:{width:48,height:48,borderRadius:12,alignItems:'center',justifyContent:'center'},emoji:{fontSize:24,lineHeight:32},statCopy:{flex:1,marginLeft:12},statTitle:{fontSize:12,lineHeight:16,fontWeight:'600',marginTop:4},section:{marginTop:24},sectionTitle:{fontWeight:'700',marginBottom:12},chart:{borderWidth:StyleSheet.hairlineWidth,borderRadius:16,padding:16,overflow:'hidden'},chartInfo:{borderRadius:8,backgroundColor:'#8E24AA1A',paddingHorizontal:12,paddingVertical:8,flexDirection:'row',alignItems:'center'},chartInfoText:{flex:1,fontWeight:'500',marginLeft:8},barItem:{marginBottom:16},barLabel:{flexDirection:'row',alignItems:'center'},barName:{flex:1,fontWeight:'600',marginRight:8},track:{height:8,borderRadius:4,overflow:'hidden',marginTop:8,marginBottom:4},fill:{height:8,backgroundColor:'#8E24AA'},legend:{flexDirection:'row',flexWrap:'wrap',gap:8,rowGap:8,justifyContent:'center'},legendItem:{minHeight:32,flexDirection:'row',alignItems:'center',paddingHorizontal:8,borderRadius:16},legendDot:{width:12,height:12,borderRadius:6,marginRight:4},empty:{padding:32,textAlign:'center'},sheet:{borderTopLeftRadius:20,borderTopRightRadius:20,overflow:'hidden'},handle:{width:40,height:4,borderRadius:2,alignSelf:'center',marginTop:12,marginBottom:8},filterHeader:{flexDirection:'row',justifyContent:'space-between',paddingVertical:8},filterContent:{padding:16},filterGroup:{marginBottom:24,gap:8},chips:{flexDirection:'row',flexWrap:'wrap',gap:8},chip:{minHeight:32,borderWidth:StyleSheet.hairlineWidth,borderRadius:8,paddingHorizontal:12,alignItems:'center',justifyContent:'center'},dateSelect:{minHeight:44,borderWidth:1,borderRadius:8,flexDirection:'row',alignItems:'center',paddingHorizontal:12,marginBottom:16},dateSelectText:{marginLeft:8},picker:{borderRadius:12,padding:8,marginBottom:16},pickerActions:{flexDirection:'row',justifyContent:'flex-end'},pickerButton:{padding:10,marginLeft:8},apply:{minHeight:48,borderRadius:24,alignItems:'center',justifyContent:'center',marginTop:8} });
