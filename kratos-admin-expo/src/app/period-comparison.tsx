import { LinearGradient } from 'expo-linear-gradient';
import { BottomSheetScrollView } from '@gorhom/bottom-sheet';
import { Stack } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/app-text';
import { BottomSheetModal } from '@/components/bottom-sheet-modal';
import { DateRangeDialog as CalendarDateRangeDialog } from '@/components/calendar-dialog';
import {
  calendarDateFromLocalDate,
  formatCalendarDate,
  type CalendarDate,
  type CalendarDateRange,
} from '@/utils/calendar-date';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { MaterialIcon } from '@/components/material-icon';
import { lookupsRepository, type LookupOption } from '@/repositories/lookups-repository';
import { getRevenuePeriodStats } from '@/repositories/revenue-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

type PeriodAType = 'this_month' | 'this_week' | 'this_year' | 'custom';
type PeriodBType = 'last_month' | 'last_week' | 'last_year' | 'custom';
type Side = 'A' | 'B';
type PeriodStats = Awaited<ReturnType<typeof getRevenuePeriodStats>>;
type PlanRow = Record<string, unknown>;

const purple = '#8E24AA';
const blue = '#1E88E5';
const green = '#2E7D32';
const red = '#C62828';
const amber = '#FFB300';

const optionsA: { type: PeriodAType; label: string }[] = [
  { type: 'this_month', label: 'Luna curentă' },
  { type: 'this_week', label: 'Săpt. curentă' },
  { type: 'this_year', label: 'Anul curent' },
  { type: 'custom', label: 'Personalizat' },
];
const optionsB: { type: PeriodBType; label: string }[] = [
  { type: 'last_month', label: 'Luna trecută' },
  { type: 'last_week', label: 'Săpt. trecută' },
  { type: 'last_year', label: 'Anul trecut' },
  { type: 'custom', label: 'Personalizat' },
];

function localCalendarRange(start: Date, end: Date): CalendarDateRange {
  return { start: calendarDateFromLocalDate(start), end: calendarDateFromLocalDate(end) };
}

function datesForType(type: PeriodAType | PeriodBType, current?: CalendarDateRange): CalendarDateRange {
  const now = new Date();
  if (type === 'custom' && current) return current;
  if (type === 'this_month') {
    return localCalendarRange(new Date(now.getFullYear(), now.getMonth(), 1), new Date(now.getFullYear(), now.getMonth() + 1, 0));
  }
  if (type === 'last_month') {
    return localCalendarRange(new Date(now.getFullYear(), now.getMonth() - 1, 1), new Date(now.getFullYear(), now.getMonth(), 0));
  }
  if (type === 'this_year') {
    return localCalendarRange(new Date(now.getFullYear(), 0, 1), new Date(now.getFullYear(), 11, 31));
  }
  if (type === 'last_year') {
    return localCalendarRange(new Date(now.getFullYear() - 1, 0, 1), new Date(now.getFullYear() - 1, 11, 31));
  }
  const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7));
  if (type === 'last_week') {
    const start = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() - 7);
    return localCalendarRange(start, new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6));
  }
  return localCalendarRange(monday, new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 6));
}

export default function PeriodComparisonScreen() {
  const { colors } = useAppTheme();
  const [gymId, setGymId] = React.useState<string>();
  const [gymSelectorVisible, setGymSelectorVisible] = React.useState(false);
  const [periodAType, setPeriodAType] = React.useState<PeriodAType>('this_month');
  const [periodBType, setPeriodBType] = React.useState<PeriodBType>('last_month');
  const [periodA, setPeriodA] = React.useState(() => datesForType('this_month'));
  const [periodB, setPeriodB] = React.useState(() => datesForType('last_month'));
  const [periodMenu, setPeriodMenu] = React.useState<Side>();
  const [dateDialog, setDateDialog] = React.useState<Side>();
  const [info, setInfo] = React.useState<{ title: string; description: string }>();
  const [plansVisible, setPlansVisible] = React.useState(false);

  const gymsQuery = useQuery({ queryKey: ['gym-lookups'], queryFn: lookupsRepository.getGyms, staleTime: 5 * 60_000 });
  const comparisonQuery = useQuery({
    queryKey: ['revenue-period-comparison', gymId, periodA.start, periodA.end, periodB.start, periodB.end],
    queryFn: async () => {
      const [a, b] = await Promise.all([
        getRevenuePeriodStats({ start: periodA.start, end: periodA.end, gymId }),
        getRevenuePeriodStats({ start: periodB.start, end: periodB.end, gymId }),
      ]);
      return { a, b };
    },
  });

  const selectPeriod = (side: Side, type: PeriodAType | PeriodBType) => {
    setPeriodMenu(undefined);
    if (type === 'custom') {
      setDateDialog(side);
      return;
    }
    if (side === 'A') {
      setPeriodAType(type as PeriodAType);
      setPeriodA(datesForType(type, periodA));
    } else {
      setPeriodBType(type as PeriodBType);
      setPeriodB(datesForType(type, periodB));
    }
  };

  const applyCustomDates = (side: Side, start: CalendarDate, end: CalendarDate) => {
    if (side === 'A') {
      setPeriodAType('custom');
      setPeriodA({ start, end });
    } else {
      setPeriodBType('custom');
      setPeriodB({ start, end });
    }
    setDateDialog(undefined);
  };

  const swapPeriods = () => {
    setPeriodA(periodB);
    setPeriodB(periodA);
    setPeriodAType('custom');
    setPeriodBType('custom');
  };

  if (comparisonQuery.isLoading) {
    return <View style={[styles.center, { backgroundColor: colors.surfaceContainerLowest }]}><Stack.Screen options={{ title: 'Comparație Perioade' }} /><ActivityIndicator size="large" color={colors.primary} /></View>;
  }

  const data = comparisonQuery.data ?? { a: emptyStats(), b: emptyStats() };
  const gymName = !gymId ? 'Toate Sălile' : gymsQuery.data?.find((gym) => gym.id === gymId)?.name ?? 'Necunoscut';

  return (
    <View style={[styles.screen, { backgroundColor: colors.surfaceContainerLowest }]}>
      <Stack.Screen options={{ title: 'Comparație Perioade' }} />
      <ScrollView
        contentContainerStyle={styles.content}
        contentInsetAdjustmentBehavior="automatic"
        refreshControl={<ManualRefreshControl onRefresh={() => comparisonQuery.refetch()} tintColor={colors.primary} colors={[colors.primary]} />}>
        {comparisonQuery.error ? <AppText selectable color={colors.error} style={styles.error}>Eroare: {comparisonQuery.error instanceof Error ? comparisonQuery.error.message : String(comparisonQuery.error)}</AppText> : null}
        <GymIndicator name={gymName} onPress={() => setGymSelectorVisible(true)} />
        <PeriodSelectors
          aType={periodAType}
          bType={periodBType}
          onOpen={setPeriodMenu}
          onCustom={setDateDialog}
          onSwap={swapPeriods}
        />
        <ComparisonSummary a={data.a} b={data.b} aLabel={periodName(periodAType, periodA)} bLabel={periodName(periodBType, periodB)} />
        <View style={styles.sideBySide}>
          <PeriodCard title={periodName(periodAType, periodA)} range={periodA} stats={data.a} color={purple} />
          <PeriodCard title={periodName(periodBType, periodB)} range={periodB} stats={data.b} color={blue} />
        </View>
        <DetailedComparison a={data.a} b={data.b} onInfo={(title, description) => setInfo({ title, description })} />
        <TopPlanComparison a={data.a.revenueByPlan} b={data.b.revenueByPlan} onShowAll={() => setPlansVisible(true)} />
      </ScrollView>

      <GymSelector visible={gymSelectorVisible} gyms={gymsQuery.data ?? []} selected={gymId} onClose={() => setGymSelectorVisible(false)} onSelect={(value) => { setGymId(value); setGymSelectorVisible(false); }} />
      <PeriodMenu visibleSide={periodMenu} selectedA={periodAType} selectedB={periodBType} onClose={() => setPeriodMenu(undefined)} onSelect={selectPeriod} />
      {dateDialog ? <DateRangeDialog visibleSide={dateDialog} range={dateDialog === 'B' ? periodB : periodA} onClose={() => setDateDialog(undefined)} onApply={applyCustomDates} /> : null}
      <InfoSheet info={info} onClose={() => setInfo(undefined)} />
      <AllPlansSheet visible={plansVisible} a={data.a.revenueByPlan} b={data.b.revenueByPlan} onClose={() => setPlansVisible(false)} />
    </View>
  );
}

function GymIndicator({ name, onPress }: { name: string; onPress: () => void }) {
  const { colors } = useAppTheme();
  return <View style={[styles.gymIndicator, { backgroundColor: colorWithAlpha(colors.primaryContainer, 0.45), borderColor: colorWithAlpha(colors.primary, 0.3) }]}><MaterialIcon name="fitness_center" size={20} color={colors.primary} /><View style={styles.gymCopy}><AppText variant="bodySmall" color={colors.onSurfaceVariant} style={styles.tiny}>Comparație pentru:</AppText><AppText color={colors.primary} style={styles.bold}>{name}</AppText></View><Pressable onPress={onPress} style={styles.changeGym}><MaterialIcon name="swap_horiz" size={18} color={colors.primary} /><AppText color={colors.primary} style={styles.changeGymText}>Schimbă</AppText></Pressable></View>;
}

function PeriodSelectors({ aType, bType, onOpen, onCustom, onSwap }: { aType: PeriodAType; bType: PeriodBType; onOpen: (side: Side) => void; onCustom: (side: Side) => void; onSwap: () => void }) {
  const { colors } = useAppTheme();
  return <Card style={styles.selectors}><AppText variant="titleMedium" style={styles.bold}>Selectează Perioade</AppText><View style={styles.selectorRow}><PeriodSelector side="A" type={aType} color={purple} onOpen={() => onOpen('A')} onCustom={() => onCustom('A')} /><Pressable accessibilityLabel="Inversează perioadele" onPress={onSwap} style={[styles.swap, { backgroundColor: colorWithAlpha(colors.primaryContainer, 0.55) }]}><MaterialIcon name="swap_horiz" size={24} color={colors.primary} /></Pressable><PeriodSelector side="B" type={bType} color={blue} onOpen={() => onOpen('B')} onCustom={() => onCustom('B')} /></View></Card>;
}

function PeriodSelector({ side, type, color, onOpen, onCustom }: { side: Side; type: PeriodAType | PeriodBType; color: string; onOpen: () => void; onCustom: () => void }) {
  const options = side === 'A' ? optionsA : optionsB;
  const label = options.find((option) => option.type === type)?.label ?? 'Personalizat';
  return <View style={styles.selector}><AppText variant="bodySmall" color={color} style={styles.selectorLabel}>Perioada {side}</AppText><Pressable onPress={onOpen} style={[styles.selectorButton, { borderColor: colorWithAlpha(color, 0.35) }]}><AppText numberOfLines={1} style={styles.selectorValue}>{label}</AppText><MaterialIcon name="arrow_drop_down" size={22} color={color} /></Pressable>{type === 'custom' ? <Pressable onPress={onCustom}><AppText variant="bodySmall" color={color} style={styles.customLink}>Apasă pentru a schimba datele</AppText></Pressable> : null}</View>;
}

function ComparisonSummary({ a, b, aLabel, bLabel }: { a: PeriodStats; b: PeriodStats; aLabel: string; bLabel: string }) {
  const { colors } = useAppTheme();
  const difference = a.totalRevenueCents - b.totalRevenueCents;
  const change = percentChange(a.totalRevenueCents, b.totalRevenueCents);
  const positive = difference >= 0;
  const tint = positive ? green : red;
  return <View style={[styles.summary, { borderColor: colorWithAlpha(tint, 0.35) }]}><LinearGradient colors={[colorWithAlpha(tint, 0.1), colorWithAlpha(tint, 0.02)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} /><View style={styles.summaryChange}><MaterialIcon name={positive ? 'trending_up' : 'trending_down'} size={32} color={tint} /><AppText color={tint} style={styles.summaryPercent}>{signed(change)}%</AppText></View><AppText color={tint} style={styles.summaryDifference}>{difference >= 0 ? '+' : ''}{currency(difference)}</AppText><AppText variant="bodySmall" color={colors.onSurfaceVariant} style={styles.centerText}>{aLabel} vs {bLabel}</AppText></View>;
}

function PeriodCard({ title, range, stats, color }: { title: string; range: CalendarDateRange; stats: PeriodStats; color: string }) {
  return <View style={[styles.periodCard, { borderColor: colorWithAlpha(color, 0.35) }]}><LinearGradient colors={[colorWithAlpha(color, 0.08), colorWithAlpha(color, 0.02)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} /><View style={styles.periodTitleRow}><View style={[styles.periodStripe, { backgroundColor: color }]} /><AppText numberOfLines={2} color={color} style={styles.periodTitle}>{title}</AppText></View><AppText variant="bodySmall" color="#757575" style={styles.periodDate}>{dayMonth(range.start)} - {dayMonth(range.end)}</AppText><AppText variant="titleLarge" style={styles.periodRevenue}>{currency(stats.totalRevenueCents)}</AppText><StatRow label="Tranzacții" value={String(stats.transactionCount)} /><StatRow label="Media" value={currency(stats.averageTransactionCents)} /><StatRow label="Membri" value={String(stats.uniqueMembers)} /></View>;
}

function StatRow({ label, value }: { label: string; value: string }) {
  const { colors } = useAppTheme();
  return <View style={styles.statRow}><AppText variant="bodySmall" color={colors.onSurfaceVariant}>{label}</AppText><AppText style={styles.statValue}>{value}</AppText></View>;
}

const metricInfo = {
  uniqueMembers: 'Numărul de persoane unice care au efectuat plăți în această perioadă.\n\nDacă un client a plătit de 3 ori, el este numărat o singură dată.\n\nAcest indicator arată câți clienți diferiți au fost activi (au plătit) în perioada selectată.',
  newMemberships: 'Numărul de abonamente noi vândute în această perioadă.\n\nInclude doar vânzările de abonamente noi, nu și extensiile sau upgrade-urile.',
  extensions: 'Numărul de abonamente extinse în această perioadă.\n\nInclude doar prelungirile de abonamente existente.',
  upgrades: 'Numărul de upgrade-uri de abonamente în această perioadă.\n\nInclude doar schimbările de la un plan la altul mai scump.',
  dayPasses: 'Numărul de tichete de intrare zilnică (day pass) vândute în această perioadă.',
} as const;

function DetailedComparison({ a, b, onInfo }: { a: PeriodStats; b: PeriodStats; onInfo: (title: string, description: string) => void }) {
  const metrics = [
    { label: 'Venit Total', a: a.totalRevenueCents, b: b.totalRevenueCents, currency: true },
    { label: 'Cash', a: a.cashRevenueCents, b: b.cashRevenueCents, currency: true },
    { label: 'Card', a: a.cardRevenueCents, b: b.cardRevenueCents, currency: true },
    { label: 'Nr. Tranzacții', a: a.transactionCount, b: b.transactionCount },
    { label: 'Media/Tranzacție', a: a.averageTransactionCents, b: b.averageTransactionCents, currency: true },
    { label: 'Membri Unici', a: a.uniqueMembers, b: b.uniqueMembers, info: metricInfo.uniqueMembers },
    { label: 'Abonamente Noi', a: a.newMembershipsCount, b: b.newMembershipsCount, info: metricInfo.newMemberships },
    { label: 'Extensii Abonamente', a: a.extensionsCount, b: b.extensionsCount, info: metricInfo.extensions },
    { label: 'Upgrade-uri', a: a.upgradesCount, b: b.upgradesCount, info: metricInfo.upgrades },
    { label: 'Intrări Zilnice', a: a.dayPassCount, b: b.dayPassCount, info: metricInfo.dayPasses },
  ];
  return <Card><View style={styles.detailedHeader}><AppText variant="titleMedium" style={styles.bold}>Comparație Detaliată</AppText><View style={styles.legend}><LegendDot color={purple} label="A" /><LegendDot color={blue} label="B" /></View></View>{metrics.map((metric) => <Metric key={metric.label} {...metric} onInfo={onInfo} />)}</Card>;
}

function Metric({ label, a, b, currency: isCurrency, info, onInfo }: { label: string; a: number; b: number; currency?: boolean; info?: string; onInfo: (title: string, description: string) => void }) {
  const change = percentChange(a, b);
  const positive = change >= 0;
  const tint = positive ? green : red;
  const total = a + b;
  const percentA = total > 0 ? a / total : 0.5;
  const percentB = total > 0 ? b / total : 0.5;
  return <View style={styles.metric}><View style={styles.metricHeader}><View style={styles.metricLabelRow}><AppText style={styles.metricLabel}>{label}</AppText>{info ? <Pressable hitSlop={8} onPress={() => onInfo(label, info)}><MaterialIcon name="info_outline" size={16} color="#9E9E9E" /></Pressable> : null}</View><View style={[styles.changePill, { backgroundColor: colorWithAlpha(tint, 0.1) }]}><MaterialIcon name={positive ? 'arrow_upward' : 'arrow_downward'} size={14} color={tint} /><AppText color={tint} style={styles.changeText}>{signed(change)}%</AppText></View></View><View style={styles.dualBar}><View style={[styles.barA, { flex: Math.max(percentA, 0.001) }]} /><View style={[styles.barB, { flex: Math.max(percentB, 0.001) }]} /></View><View style={styles.barLabels}><LegendValue color={purple} value={isCurrency ? currency(a) : String(Math.trunc(a))} percent={percentA} /><LegendValue reverse color={blue} value={isCurrency ? currency(b) : String(Math.trunc(b))} percent={percentB} /></View></View>;
}

function LegendDot({ color, label }: { color: string; label: string }) { return <View style={styles.legendItem}><View style={[styles.legendSquare, { backgroundColor: color }]} /><AppText variant="bodySmall" style={styles.legendLabel}>{label}</AppText></View>; }
function LegendValue({ color, value, percent, reverse }: { color: string; value: string; percent: number; reverse?: boolean }) { const dot = <View style={[styles.valueDot, { backgroundColor: color }]} />; return <View style={styles.legendValue}>{reverse ? null : dot}<AppText numberOfLines={1} color={color} style={styles.legendValueText}>{value} ({Math.round(percent * 100)}%)</AppText>{reverse ? dot : null}</View>; }

function TopPlanComparison({ a, b, onShowAll }: { a: PlanRow[]; b: PlanRow[]; onShowAll: () => void }) {
  return <Card><View style={styles.topPlanHeader}><MaterialIcon name="emoji_events" size={22} color={amber} /><AppText variant="titleMedium" style={styles.topPlanTitle}>Cel Mai Vândut Plan</AppText></View><View style={styles.sideBySide}><TopPlanCard label="Perioada A" plan={a[0]} color={purple} /><TopPlanCard label="Perioada B" plan={b[0]} color={blue} /></View>{a.length > 1 || b.length > 1 ? <Pressable onPress={onShowAll} style={styles.showPlans}><MaterialIcon name="list" size={18} color="#68548E" /><AppText color="#68548E" style={styles.showPlansText}>Vezi toate planurile</AppText></Pressable> : null}</Card>;
}

function TopPlanCard({ label, plan, color }: { label: string; plan?: PlanRow; color: string }) {
  return <View style={[styles.topPlanCard, { backgroundColor: colorWithAlpha(color, 0.1), borderColor: colorWithAlpha(color, 0.3) }]}><AppText variant="bodySmall" color={color} style={styles.selectorLabel}>{label}</AppText><AppText numberOfLines={2} style={styles.topPlanName}>{String(plan?.plan_name ?? 'N/A')}</AppText><AppText color={color} style={styles.topPlanRevenue}>{currency(Number(plan?.revenue ?? 0))}</AppText><AppText variant="bodySmall" color="#757575">{Number(plan?.count ?? 0)} vânzări</AppText></View>;
}

function Card({ children, style }: React.PropsWithChildren<{ style?: object }>) {
  const { colors } = useAppTheme();
  return <View style={[styles.card, { borderColor: colors.outlineVariant }, style]}>{children}</View>;
}

function GymSelector({ visible, gyms, selected, onClose, onSelect }: { visible: boolean; gyms: LookupOption[]; selected?: string; onClose: () => void; onSelect: (id?: string) => void }) {
  return <BottomSheet visible={visible} onClose={onClose}><AppText variant="titleLarge" style={styles.sheetTitle}>Selectează Sala</AppText><SheetOption icon="all_inclusive" label="Toate Sălile" selected={!selected} onPress={() => onSelect(undefined)} />{gyms.map((gym) => <SheetOption key={gym.id} icon="fitness_center" label={gym.name} selected={selected === gym.id} onPress={() => onSelect(gym.id)} />)}</BottomSheet>;
}

function PeriodMenu({ visibleSide, selectedA, selectedB, onClose, onSelect }: { visibleSide?: Side; selectedA: PeriodAType; selectedB: PeriodBType; onClose: () => void; onSelect: (side: Side, type: PeriodAType | PeriodBType) => void }) {
  const options = visibleSide === 'B' ? optionsB : optionsA;
  const selected = visibleSide === 'B' ? selectedB : selectedA;
  return <BottomSheet visible={Boolean(visibleSide)} onClose={onClose}><AppText variant="titleLarge" style={styles.sheetTitle}>Perioada {visibleSide}</AppText>{options.map((option) => <SheetOption key={option.type} icon={option.type === 'custom' ? 'date_range' : 'calendar_today'} label={option.label} selected={selected === option.type} onPress={() => visibleSide && onSelect(visibleSide, option.type)} />)}</BottomSheet>;
}

function SheetOption({ icon, label, selected, onPress }: { icon: 'all_inclusive' | 'fitness_center' | 'date_range' | 'calendar_today'; label: string; selected: boolean; onPress: () => void }) {
  const { colors } = useAppTheme();
  return <Pressable onPress={onPress} style={[styles.sheetOption, selected && { backgroundColor: colors.secondaryContainer }]}><MaterialIcon name={icon} size={22} color={selected ? colors.primary : colors.onSurfaceVariant} /><AppText style={[styles.sheetOptionLabel, selected && styles.bold]}>{label}</AppText>{selected ? <MaterialIcon name="check" size={20} color={colors.primary} /> : null}</Pressable>;
}

function BottomSheet({ visible, onClose, children }: React.PropsWithChildren<{ visible: boolean; onClose: () => void }>) {
  const { colors } = useAppTheme();
  return <BottomSheetModal visible={visible} onClose={onClose} dynamic scrollable maxDynamicContentSize={600} sheetStyle={[styles.sheet, { backgroundColor: colors.surface }]}><View style={[styles.handle, { backgroundColor: colorWithAlpha(colors.onSurfaceVariant, 0.4) }]} /><BottomSheetScrollView contentContainerStyle={styles.sheetContent}>{children}</BottomSheetScrollView></BottomSheetModal>;
}

function DateRangeDialog({ visibleSide, range, onClose, onApply }: { visibleSide?: Side; range: CalendarDateRange; onClose: () => void; onApply: (side: Side, start: CalendarDate, end: CalendarDate) => void }) {
  const maximum = calendarDateFromLocalDate(new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0));
  return <CalendarDateRangeDialog
    visible={Boolean(visibleSide)}
    title="Selectează interval"
    minimumDate="2020-01-01"
    maximumDate={maximum}
    value={range}
    onCancel={onClose}
    onApply={(selected) => { if (visibleSide) onApply(visibleSide, selected.start, selected.end); }}
  />;
}

function InfoSheet({ info, onClose }: { info?: { title: string; description: string }; onClose: () => void }) {
  const { colors } = useAppTheme();
  return <BottomSheetModal visible={Boolean(info)} onClose={onClose} dynamic maxDynamicContentSize={600} sheetStyle={[styles.infoSheet, { backgroundColor: colors.surface }]}><View style={styles.infoHeader}><View style={[styles.infoIcon, { backgroundColor: colors.primaryContainer }]}><MaterialIcon name="info_outline" size={24} color={colors.primary} /></View><AppText variant="titleLarge" style={styles.infoTitle}>{info?.title}</AppText></View><AppText color={colors.onSurfaceVariant} style={styles.infoDescription}>{info?.description}</AppText><Pressable onPress={onClose} style={[styles.infoDone, { backgroundColor: colors.primary }]}><AppText color={colors.onPrimary} style={styles.bold}>Am înțeles</AppText></Pressable></BottomSheetModal>;
}

function AllPlansSheet({ visible, a, b, onClose }: { visible: boolean; a: PlanRow[]; b: PlanRow[]; onClose: () => void }) {
  const { colors } = useAppTheme();
  const insets = useSafeAreaInsets();
  return <BottomSheetModal visible={visible} onClose={onClose} snapPoints={['50%', '70%', '95%']} initialIndex={1} scrollable sheetStyle={[styles.plansSheet, { backgroundColor: colors.surface }]}><View style={styles.plansHeader}><AppText variant="titleLarge" style={styles.bold}>Vânzări pe Plan</AppText><Pressable hitSlop={10} onPress={onClose}><MaterialIcon name="close" size={24} color={colors.onSurfaceVariant} /></Pressable></View><View style={styles.plansLegend}><LegendDot color={purple} label="Perioada A" /><LegendDot color={blue} label="Perioada B" /></View><View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} /><BottomSheetScrollView style={styles.plansScroll} contentContainerStyle={[styles.plansList, { paddingBottom: 20 + insets.bottom }]}><PlanSection label="Perioada A" plans={a} color={purple} /><PlanSection label="Perioada B" plans={b} color={blue} /></BottomSheetScrollView></BottomSheetModal>;
}

function PlanSection({ label, plans, color }: { label: string; plans: PlanRow[]; color: string }) {
  if (!plans.length) return null;
  return <View style={styles.planSection}><AppText color={color} style={styles.planSectionTitle}>{label}</AppText>{plans.map((plan, index) => <PlanListItem key={`${String(plan.plan_name)}-${index}`} rank={index + 1} plan={plan} color={color} />)}</View>;
}

function PlanListItem({ rank, plan, color }: { rank: number; plan: PlanRow; color: string }) {
  const top = rank === 1;
  return <View style={[styles.planItem, { backgroundColor: top ? colorWithAlpha(color, 0.1) : '#9E9E9E0D', borderColor: top ? colorWithAlpha(color, 0.3) : 'transparent' }]}><View style={[styles.rank, { backgroundColor: top ? amber : '#E0E0E0' }]}><AppText color={top ? '#FFFFFF' : '#616161'} style={styles.rankText}>{rank}</AppText></View><View style={styles.planCopy}><AppText numberOfLines={1} style={top ? styles.bold : undefined}>{String(plan.plan_name ?? 'N/A')}</AppText><AppText variant="bodySmall" color="#757575">{Number(plan.count ?? 0)} vânzări</AppText></View><AppText color={color} style={styles.planAmount}>{currency(Number(plan.revenue ?? 0))}</AppText></View>;
}

function emptyStats(): PeriodStats { return { totalRevenueCents: 0, cashRevenueCents: 0, cardRevenueCents: 0, transactionCount: 0, averageTransactionCents: 0, uniqueMembers: 0, dayPassCount: 0, newMembershipsCount: 0, extensionsCount: 0, upgradesCount: 0, revenueByPlan: [] }; }
function percentChange(current: number, previous: number) { return previous === 0 ? (current > 0 ? 100 : 0) : ((current - previous) / previous) * 100; }
function signed(value: number) { return `${value >= 0 ? '+' : ''}${value.toFixed(1)}`; }
function currency(cents: number) { return `RON ${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`; }
function dayMonth(date: CalendarDate) { return formatCalendarDate(date, { day: '2-digit', month: '2-digit' }); }
function periodName(type: PeriodAType | PeriodBType, range: CalendarDateRange) { const names: Record<PeriodAType | PeriodBType, string> = { this_month: 'Luna curentă', last_month: 'Luna trecută', this_week: 'Săptămâna curentă', last_week: 'Săptămâna trecută', this_year: 'Anul curent', last_year: 'Anul trecut', custom: `${formatCalendarDate(range.start, { day: '2-digit', month: 'short' })} - ${formatCalendarDate(range.end, { day: '2-digit', month: 'short' })}` }; return names[type]; }

const styles = StyleSheet.create({
  screen: { flex: 1 }, center: { flex: 1, alignItems: 'center', justifyContent: 'center' }, content: { padding: 16, paddingBottom: 32, gap: 16 }, error: { marginBottom: 8 },
  gymIndicator: { minHeight: 68, borderRadius: 12, borderWidth: 1, paddingHorizontal: 16, paddingVertical: 12, flexDirection: 'row', alignItems: 'center' }, gymCopy: { flex: 1, marginLeft: 10 }, tiny: { fontSize: 11 }, bold: { fontWeight: '700' }, changeGym: { minHeight: 40, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 4 }, changeGymText: { fontWeight: '600', marginLeft: 5 },
  card: { borderRadius: 16, borderWidth: StyleSheet.hairlineWidth, padding: 16, overflow: 'hidden' }, selectors: { marginTop: 0 }, selectorRow: { flexDirection: 'row', alignItems: 'center', marginTop: 16 }, selector: { flex: 1 }, selectorLabel: { fontWeight: '600' }, selectorButton: { height: 48, marginTop: 8, borderRadius: 8, borderWidth: 1, paddingHorizontal: 9, flexDirection: 'row', alignItems: 'center' }, selectorValue: { flex: 1, fontSize: 12 }, customLink: { fontSize: 10, lineHeight: 14, textDecorationLine: 'underline', marginTop: 6 }, swap: { width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center', marginHorizontal: 8 },
  summary: { borderRadius: 16, borderWidth: 2, padding: 20, alignItems: 'center', overflow: 'hidden' }, summaryChange: { flexDirection: 'row', alignItems: 'center' }, summaryPercent: { fontSize: 36, lineHeight: 44, fontWeight: '700', marginLeft: 12 }, summaryDifference: { fontSize: 18, lineHeight: 24, fontWeight: '600', marginTop: 8 }, centerText: { textAlign: 'center', marginTop: 4 },
  sideBySide: { flexDirection: 'row', gap: 12 }, periodCard: { flex: 1, minWidth: 0, borderRadius: 16, borderWidth: 1, padding: 16, overflow: 'hidden' }, periodTitleRow: { flexDirection: 'row', alignItems: 'flex-start' }, periodStripe: { width: 4, height: 20, borderRadius: 2, marginRight: 8 }, periodTitle: { flex: 1, fontSize: 13, lineHeight: 18, fontWeight: '700' }, periodDate: { marginTop: 4 }, periodRevenue: { fontSize: 18, lineHeight: 24, fontWeight: '700', marginTop: 14, marginBottom: 8 }, statRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 4, gap: 4 }, statValue: { fontSize: 12, lineHeight: 16, fontWeight: '600', textAlign: 'right', flexShrink: 1 },
  detailedHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }, legend: { flexDirection: 'row', gap: 12 }, legendItem: { flexDirection: 'row', alignItems: 'center' }, legendSquare: { width: 12, height: 12, borderRadius: 3 }, legendLabel: { fontWeight: '500', marginLeft: 4 }, metric: { paddingVertical: 10 }, metricHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }, metricLabelRow: { flexDirection: 'row', alignItems: 'center', flexShrink: 1, marginRight: 8, gap: 4 }, metricLabel: { fontWeight: '500' }, changePill: { borderRadius: 6, paddingHorizontal: 8, paddingVertical: 4, flexDirection: 'row', alignItems: 'center' }, changeText: { fontSize: 12, lineHeight: 16, fontWeight: '700', marginLeft: 4 }, dualBar: { height: 24, borderRadius: 6, overflow: 'hidden', flexDirection: 'row', marginTop: 8 }, barA: { backgroundColor: purple }, barB: { backgroundColor: blue }, barLabels: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: 6 }, legendValue: { maxWidth: '49%', flexDirection: 'row', alignItems: 'center', gap: 6 }, valueDot: { width: 10, height: 10, borderRadius: 2, flexShrink: 0 }, legendValueText: { fontSize: 11, lineHeight: 16, fontWeight: '600', flexShrink: 1 },
  topPlanHeader: { flexDirection: 'row', alignItems: 'center', marginBottom: 16 }, topPlanTitle: { fontWeight: '700', marginLeft: 8 }, topPlanCard: { flex: 1, minWidth: 0, borderRadius: 12, borderWidth: 1, padding: 12 }, topPlanName: { fontWeight: '700', marginTop: 8, minHeight: 40 }, topPlanRevenue: { fontSize: 13, lineHeight: 20, fontWeight: '600', marginTop: 8 }, showPlans: { alignSelf: 'center', flexDirection: 'row', alignItems: 'center', padding: 10, marginTop: 6 }, showPlansText: { fontWeight: '600', marginLeft: 6 },
  sheet: { borderTopLeftRadius: 20, borderTopRightRadius: 20, overflow: 'hidden' }, handle: { width: 40, height: 4, borderRadius: 2, alignSelf: 'center', marginTop: 12 }, sheetContent: { padding: 16, paddingBottom: 32 }, sheetTitle: { fontWeight: '700', marginBottom: 16 }, sheetOption: { minHeight: 54, borderRadius: 8, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12 }, sheetOptionLabel: { flex: 1, marginLeft: 14 },
  dialogBackdrop: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#00000066', padding: 20 }, dateDialog: { width: '100%', maxWidth: 480, borderRadius: 20, padding: 20 }, dateChoiceRow: { flexDirection: 'row', gap: 8, marginTop: 16 }, dateChoice: { flex: 1, borderWidth: 1, borderRadius: 8, padding: 10 }, dialogActions: { flexDirection: 'row', justifyContent: 'flex-end', marginTop: 12 }, dialogButton: { paddingHorizontal: 10, paddingVertical: 10, marginLeft: 4 },
  infoSheet: { borderTopLeftRadius: 20, borderTopRightRadius: 20, padding: 24 }, infoHeader: { flexDirection: 'row', alignItems: 'center' }, infoIcon: { padding: 10, borderRadius: 12 }, infoTitle: { flex: 1, marginLeft: 12, fontWeight: '700' }, infoDescription: { lineHeight: 22, marginTop: 20 }, infoDone: { minHeight: 48, borderRadius: 24, alignItems: 'center', justifyContent: 'center', marginTop: 24 },
  plansSheet: { borderTopLeftRadius: 20, borderTopRightRadius: 20, paddingTop: 20, overflow: 'hidden' }, plansHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 20 }, plansLegend: { flexDirection: 'row', gap: 16, paddingHorizontal: 20, marginTop: 12 }, divider: { height: StyleSheet.hairlineWidth, marginTop: 16 }, plansScroll: { flex: 1 }, plansList: { padding: 20 }, planSection: { marginBottom: 20 }, planSectionTitle: { fontWeight: '700', marginBottom: 8 }, planItem: { minHeight: 64, borderRadius: 10, borderWidth: 1, padding: 12, flexDirection: 'row', alignItems: 'center', marginBottom: 8 }, rank: { width: 28, height: 28, borderRadius: 14, alignItems: 'center', justifyContent: 'center' }, rankText: { fontSize: 12, lineHeight: 16, fontWeight: '700' }, planCopy: { flex: 1, marginHorizontal: 12 }, planAmount: { fontWeight: '700', fontSize: 13, flexShrink: 1 },
});
