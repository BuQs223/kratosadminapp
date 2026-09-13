import { useQuery } from '@tanstack/react-query';
import { BottomSheetScrollView } from '@gorhom/bottom-sheet';
import { Stack } from 'expo-router';
import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  View,
  useWindowDimensions,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Svg, {
  Circle,
  Defs,
  G,
  Line,
  LinearGradient,
  Path,
  Rect,
  Stop,
  Text as SvgText,
} from 'react-native-svg';

import { AppText } from '@/components/app-text';
import { BottomSheetModal } from '@/components/bottom-sheet-modal';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { MaterialIcon } from '@/components/material-icon';
import {
  type MembershipTrendMetric,
  type MembershipTrendPoint,
  type MembershipTrendRange,
} from '@/models/membership-trend';
import { lookupsRepository, type LookupOption } from '@/repositories/lookups-repository';
import { getMembershipAccessTrend } from '@/repositories/membership-analytics-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

const ranges: readonly { value: MembershipTrendRange; label: string }[] = [
  { value: '7d', label: '7Z' },
  { value: '30d', label: '30Z' },
  { value: '12w', label: '3L' },
  { value: '12m', label: '12L' },
];

const metricLabels: Record<MembershipTrendMetric, string> = {
  activeAccess: 'Acces activ',
  newActivations: 'Activări noi',
};

export default function MembershipAnalyticsScreen() {
  const { colors } = useAppTheme();
  const [metric, setMetric] = React.useState<MembershipTrendMetric>('activeAccess');
  const [range, setRange] = React.useState<MembershipTrendRange>('30d');
  const [gymId, setGymId] = React.useState<string>();
  const [gymFilterVisible, setGymFilterVisible] = React.useState(false);

  const trendQuery = useQuery({
    queryKey: ['membership-access-trend', range, gymId],
    queryFn: () => getMembershipAccessTrend({ range, gymId }),
  });
  const gymsQuery = useQuery({
    queryKey: ['gym-lookups'],
    queryFn: lookupsRepository.getGyms,
    staleTime: 5 * 60_000,
  });
  const selectedGym = gymsQuery.data?.find((gym) => gym.id === gymId);

  return (
    <View style={[styles.screen, { backgroundColor: colors.surfaceContainerLowest }]}>
      <Stack.Screen
        options={{
          title: 'Acces membri',
          headerRight: () => (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Filtrează după sala de vânzare"
              accessibilityHint={selectedGym ? `Selectată: ${selectedGym.name}` : 'Toate sălile'}
              hitSlop={10}
              onPress={() => setGymFilterVisible(true)}
              style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, padding: 6 })}>
              <MaterialIcon name="filter_list" size={24} color={colors.onSurfaceVariant} />
              {gymId ? <View style={[styles.filterBadge, { backgroundColor: colors.primary }]} /> : null}
            </Pressable>
          ),
        }}
      />

      {trendQuery.isLoading && !trendQuery.data ? (
        <View style={styles.center} accessibilityRole="progressbar" accessibilityLabel="Se încarcă analiza accesului">
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      ) : trendQuery.isError && !trendQuery.data ? (
        <ErrorState error={trendQuery.error} onRetry={() => void trendQuery.refetch()} />
      ) : (
        <ScrollView
          contentInsetAdjustmentBehavior="automatic"
          contentContainerStyle={styles.content}
          refreshControl={
            <ManualRefreshControl
              tintColor={colors.primary}
              colors={[colors.primary]}
              onRefresh={() => trendQuery.refetch()}
            />
          }>
          <View style={[styles.scopeCard, { backgroundColor: colors.primaryContainer }]}>
            <MaterialIcon name="query_stats" size={22} color={colors.onPrimaryContainer} />
            <View style={styles.scopeCopy}>
              <AppText variant="titleSmall" color={colors.onPrimaryContainer} style={styles.bold}>
                {selectedGym?.name ?? 'Toate sălile'}
              </AppText>
              <AppText variant="bodySmall" color={colors.onPrimaryContainer}>
                persoane unice cu acces din abonamente pachet
              </AppText>
            </View>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Schimbă sala de vânzare"
              onPress={() => setGymFilterVisible(true)}
              hitSlop={8}>
              <AppText color={colors.primary} style={styles.bold}>Schimbă</AppText>
            </Pressable>
          </View>

          <SegmentedControl
            value={metric}
            options={[
              { value: 'activeAccess', label: 'Acces activ' },
              { value: 'newActivations', label: 'Activări noi' },
            ]}
            onChange={setMetric}
          />
          <SegmentedControl value={range} options={ranges} onChange={setRange} compact />

          {trendQuery.error ? (
            <InlineError error={trendQuery.error} onRetry={() => void trendQuery.refetch()} />
          ) : null}

          {trendQuery.data?.some((point) => point.isEstimated) ? <EstimatedBanner /> : null}

          {trendQuery.data?.length ? (
            <AccessTrendChart points={trendQuery.data} metric={metric} range={range} />
          ) : (
            <EmptyState />
          )}

          <DefinitionCard metric={metric} range={range} />
        </ScrollView>
      )}

      <GymFilterSheet
        visible={gymFilterVisible}
        gyms={gymsQuery.data ?? []}
        selectedGymId={gymId}
        onClose={() => setGymFilterVisible(false)}
        onSelect={(nextGymId) => {
          setGymId(nextGymId);
          setGymFilterVisible(false);
        }}
      />
    </View>
  );
}

function SegmentedControl<Value extends string>({
  value,
  options,
  onChange,
  compact = false,
}: {
  value: Value;
  options: readonly { value: Value; label: string }[];
  onChange: (value: Value) => void;
  compact?: boolean;
}) {
  const { colors } = useAppTheme();
  return (
    <View
      accessibilityRole="tablist"
      style={[styles.segmented, { backgroundColor: colors.surfaceContainerHigh }]}
      testID={compact ? 'membership-range-control' : 'membership-metric-control'}>
      {options.map((option) => {
        const selected = option.value === value;
        return (
          <Pressable
            key={option.value}
            accessibilityRole="tab"
            accessibilityState={{ selected }}
            onPress={() => onChange(option.value)}
            style={({ pressed }) => [
              styles.segment,
              selected && { backgroundColor: colors.surfaceContainerLowest },
              { opacity: pressed ? 0.65 : 1 },
            ]}>
            <AppText
              variant={compact ? 'titleSmall' : 'body'}
              color={selected ? colors.primary : colors.onSurfaceVariant}
              style={selected ? styles.bold : undefined}>
              {option.label}
            </AppText>
          </Pressable>
        );
      })}
    </View>
  );
}

function AccessTrendChart({
  points,
  metric,
  range,
}: {
  points: MembershipTrendPoint[];
  metric: MembershipTrendMetric;
  range: MembershipTrendRange;
}) {
  const { colors } = useAppTheme();
  const { width } = useWindowDimensions();
  const [selectedIndex, setSelectedIndex] = React.useState<number | null>(null);
  const chartWidth = Math.max(280, width - 64);
  const height = 284;
  const left = 42;
  const right = 10;
  const top = 24;
  const bottom = 52;
  const plotWidth = chartWidth - left - right;
  const plotHeight = height - top - bottom;
  const values = points.map((point) => metric === 'activeAccess' ? point.activePeople : point.newActivations);
  const max = Math.max(...values, 1);
  const chartPoints = values.map((value, index) => ({
    x: left + (values.length === 1 ? plotWidth / 2 : index / (values.length - 1) * plotWidth),
    y: top + (1 - value / max) * plotHeight,
    point: points[index],
    value,
  }));
  const linePath = pathFor(chartPoints);
  const areaPath = `${linePath} L ${chartPoints.at(-1)?.x ?? left} ${top + plotHeight} L ${chartPoints[0]?.x ?? left} ${top + plotHeight} Z`;
  const markerIndexes = chartPoints
    .map((_chartPoint, index) => index)
    .filter((index) => shouldShowChartMarker(range, index, chartPoints.length));
  const selected = selectedIndex === null ? null : chartPoints[selectedIndex];
  const selectedValue = selected
    ? `${formatPeriod(selected.point, range)}: ${selected.value} ${metric === 'activeAccess' ? 'persoane cu acces activ' : 'activări noi'}${selected.point.isEstimated ? ', estimat' : ''}`
    : 'Niciun punct selectat';
  const tooltipWidth = 168;
  const tooltipHeight = 56;
  const tooltipX = selected ? Math.max(4, Math.min(chartWidth - tooltipWidth - 4, selected.x - tooltipWidth / 2)) : 0;
  const tooltipY = selected ? (selected.y > top + tooltipHeight + 14 ? selected.y - tooltipHeight - 10 : selected.y + 12) : 0;
  const estimatedPaths = segmentedPaths(chartPoints, true);
  const exactPaths = segmentedPaths(chartPoints, false);
  const selectClosestPoint = (locationX: number) => {
    const firstMarkerIndex = markerIndexes[0];
    if (firstMarkerIndex === undefined) return;

    const closestIndex = markerIndexes.reduce((closest, index) => (
      Math.abs(chartPoints[index].x - locationX) < Math.abs(chartPoints[closest].x - locationX)
        ? index
        : closest
    ), firstMarkerIndex);
    setSelectedIndex(closestIndex);
  };
  const moveSelectedPoint = (direction: 1 | -1) => {
    if (!markerIndexes.length) return;
    setSelectedIndex((current) => {
      const currentMarkerPosition = current === null ? -1 : markerIndexes.indexOf(current);
      const initialPosition = currentMarkerPosition === -1
        ? (direction > 0 ? 0 : markerIndexes.length - 1)
        : currentMarkerPosition;
      const nextPosition = Math.max(0, Math.min(markerIndexes.length - 1, initialPosition + direction));
      return markerIndexes[nextPosition];
    });
  };

  return (
    <View style={[styles.chartCard, { borderColor: colors.outlineVariant }]}>
      <View style={styles.chartHeading}>
        <View>
          <AppText variant="titleLarge" style={styles.bold}>{metricLabels[metric]}</AppText>
          <AppText variant="bodySmall" color={colors.onSurfaceVariant}>
            {rangeHint(range)}
          </AppText>
        </View>
        <AppText variant="headlineMedium" color={colors.primary} style={styles.total}>
          {values.at(-1) ?? 0}
        </AppText>
      </View>

      <View style={{ width: chartWidth, height }}>
        <Svg pointerEvents="none" width={chartWidth} height={height}>
          <Defs>
            <LinearGradient id="membership-access-area" x1="0" y1="0" x2="0" y2="1">
              <Stop offset="0" stopColor={colors.primary} stopOpacity="0.25" />
              <Stop offset="1" stopColor={colors.primary} stopOpacity="0.01" />
            </LinearGradient>
          </Defs>
          {[0, 0.5, 1].map((ratio) => {
            const y = top + (1 - ratio) * plotHeight;
            return (
              <React.Fragment key={ratio}>
                <Line x1={left} x2={chartWidth - right} y1={y} y2={y} stroke={colors.outlineVariant} strokeOpacity={0.7} strokeWidth={StyleSheet.hairlineWidth} />
                <SvgText x={left - 7} y={y + 4} fill={colors.onSurfaceVariant} fontSize={10} textAnchor="end">
                  {Math.round(max * ratio)}
                </SvgText>
              </React.Fragment>
            );
          })}
          <Path d={areaPath} fill="url(#membership-access-area)" />
          {exactPaths.map((path, index) => <Path key={`exact-${index}`} d={path} fill="none" stroke={colors.primary} strokeWidth={3} strokeLinecap="round" strokeLinejoin="round" />)}
          {estimatedPaths.map((path, index) => <Path key={`estimated-${index}`} d={path} fill="none" stroke={colors.primary} strokeWidth={3} strokeDasharray={[7, 5]} strokeLinecap="round" strokeLinejoin="round" />)}
          {markerIndexes.map((index) => {
            const chartPoint = chartPoints[index];
            return (
            <Circle
              key={chartPoint.point.periodStart.toISOString()}
              testID={`membership-trend-marker-${index}`}
              cx={chartPoint.x}
              cy={chartPoint.y}
              r={5}
              fill={colors.surfaceContainerLowest}
              stroke={colors.primary}
              strokeWidth={2.5}
            />
            );
          })}
          {selected ? (
            <G accessible accessibilityLabel={`Detalii punct: ${formatPeriod(selected.point, range)}, ${selected.value}${selected.point.isEstimated ? ', estimat' : ''}`}>
              <Line x1={selected.x} x2={selected.x} y1={top} y2={top + plotHeight} stroke={colors.primary} strokeOpacity={0.35} strokeDasharray={[3, 4]} />
              <Rect x={tooltipX} y={tooltipY} width={tooltipWidth} height={tooltipHeight} rx={10} fill={colors.surface} stroke={colors.outlineVariant} />
              <SvgText x={tooltipX + 10} y={tooltipY + 20} fill={colors.onSurfaceVariant} fontSize={11}>
                {formatPeriod(selected.point, range)}
              </SvgText>
              <SvgText x={tooltipX + 10} y={tooltipY + 41} fill={colors.onSurface} fontSize={16} fontWeight="700">
                {selected.value} {selected.point.isEstimated ? '· estimat' : ''}
              </SvgText>
            </G>
          ) : null}
          {chartPoints.map((chartPoint, index) => (
            <SvgText
              key={`label-${chartPoint.point.periodStart.toISOString()}`}
              x={chartPoint.x}
              y={height - 17}
              fill={colors.onSurfaceVariant}
              fontSize={10}
              textAnchor="middle">
              {axisLabel(chartPoint.point, range, index, chartPoints.length)}
            </SvgText>
          ))}
        </Svg>
        <Pressable
          testID="membership-trend-chart"
          accessibilityRole="adjustable"
          accessibilityLabel={`${metricLabels[metric]}, grafic pentru ${range}`}
          accessibilityHint={range === '30d'
            ? 'Atinge oriunde în grafic pentru marcajul săptămânal cel mai apropiat. Folosește acțiunile următorul și precedentul punct pentru detalii cu cititorul de ecran.'
            : 'Atinge oriunde în grafic pentru punctul cel mai apropiat. Folosește acțiunile următorul și precedentul punct pentru detalii cu cititorul de ecran.'}
          accessibilityValue={{ text: selectedValue }}
          accessibilityActions={[
            { name: 'increment', label: 'Următorul punct' },
            { name: 'decrement', label: 'Punctul precedent' },
          ]}
          onAccessibilityAction={(event) => moveSelectedPoint(event.nativeEvent.actionName === 'increment' ? 1 : -1)}
          onPress={(event) => selectClosestPoint(event.nativeEvent.locationX)}
          style={StyleSheet.absoluteFill}
        />
      </View>
      <AppText variant="bodySmall" color={colors.onSurfaceVariant} style={styles.chartInstructions}>
        {range === '30d'
          ? 'Atinge oriunde în grafic pentru marcajul săptămânal cel mai apropiat. Linia punctată indică o perioadă estimată.'
          : 'Atinge oriunde în grafic pentru detalii. Linia punctată indică o perioadă estimată.'}
      </AppText>
    </View>
  );
}

function pathFor(points: readonly { x: number; y: number }[]) {
  return points.map((point, index) => `${index ? 'L' : 'M'} ${point.x} ${point.y}`).join(' ');
}

function shouldShowChartMarker(range: MembershipTrendRange, index: number, count: number) {
  if (range !== '30d' || count <= 7) return true;
  return index === 0 || index === count - 1 || index % 7 === 0;
}

function segmentedPaths(
  points: readonly { x: number; y: number; point: MembershipTrendPoint }[],
  estimated: boolean,
) {
  const paths: string[] = [];
  let segment: { x: number; y: number; point: MembershipTrendPoint }[] = [];
  for (const point of points) {
    if (point.point.isEstimated === estimated) {
      if (!segment.length) {
        const previous = points[points.indexOf(point) - 1];
        if (previous) segment.push(previous);
      }
      segment.push(point);
    } else if (segment.length) {
      paths.push(pathFor(segment));
      segment = [];
    }
  }
  if (segment.length) paths.push(pathFor(segment));
  return paths;
}

function EstimatedBanner() {
  const { colors } = useAppTheme();
  return (
    <View style={[styles.estimatedBanner, { backgroundColor: colors.tertiaryContainer }]}>
      <MaterialIcon name="warning_amber" size={20} color={colors.onTertiaryContainer} />
      <AppText variant="bodySmall" color={colors.onTertiaryContainer} style={styles.bannerCopy}>
        Perioadele punctate sunt reconstruite din istoricul abonamentelor și pot diferi ușor de valorile exacte care se acumulează zilnic.
      </AppText>
    </View>
  );
}

function DefinitionCard({ metric, range }: { metric: MembershipTrendMetric; range: MembershipTrendRange }) {
  const { colors } = useAppTheme();
  const metricDescription = metric === 'activeAccess'
    ? 'O persoană unică acoperită de un plan pachet început, neexpirat, neanulat și neînghețat. Abonamentele de o zi nu sunt incluse.'
    : 'O persoană unică care a primit acces în perioadă. Extensiile nu sunt numărate ca activări noi.';
  return (
    <View style={[styles.definitionCard, { backgroundColor: colors.surfaceContainerLow, borderColor: colors.outlineVariant }]}>
      <MaterialIcon name="query_stats" size={20} color={colors.primary} />
      <View style={styles.definitionCopy}>
        <AppText variant="titleSmall" style={styles.bold}>{metricLabels[metric]}</AppText>
        <AppText variant="bodySmall" color={colors.onSurfaceVariant}>{metricDescription}</AppText>
        <AppText variant="bodySmall" color={colors.onSurfaceVariant}>
          {range === '12w' ? 'Săptămânile sunt luni–duminică.' : range === '12m' ? 'Lunile sunt calendaristice.' : 'Fiecare punct reprezintă o zi.'}
        </AppText>
      </View>
    </View>
  );
}

function EmptyState() {
  const { colors } = useAppTheme();
  return (
    <View style={[styles.empty, { backgroundColor: colors.surfaceContainerLow, borderColor: colors.outlineVariant }]}>
      <MaterialIcon name="query_stats" size={40} color={colors.onSurfaceVariant} />
      <AppText variant="titleMedium" style={styles.bold}>Nu există încă puncte pentru acest interval</AppText>
      <AppText color={colors.onSurfaceVariant} style={styles.emptyCopy}>
        Alege o altă sală sau revino după primul snapshot zilnic.
      </AppText>
    </View>
  );
}

function ErrorState({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  const { colors } = useAppTheme();
  return (
    <View style={[styles.errorState, { backgroundColor: colors.surfaceContainerLowest }]}>
      <MaterialIcon name="warning_amber" size={44} color={colors.error} />
      <AppText variant="titleLarge" style={styles.bold}>Analiza nu poate fi încărcată</AppText>
      <AppText selectable color={colors.onSurfaceVariant} style={styles.errorCopy}>
        {errorMessage(error)}
      </AppText>
      <Pressable accessibilityRole="button" onPress={onRetry} style={[styles.retryButton, { backgroundColor: colors.primary }]}>
        <MaterialIcon name="refresh" size={20} color={colors.onPrimary} />
        <AppText color={colors.onPrimary} style={styles.bold}>Reîncearcă</AppText>
      </Pressable>
    </View>
  );
}

function InlineError({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  const { colors } = useAppTheme();
  return (
    <View style={[styles.inlineError, { backgroundColor: colorWithAlpha(colors.error, 0.1) }]}>
      <AppText selectable color={colors.error} style={styles.inlineErrorCopy}>Actualizarea online a eșuat: {errorMessage(error)}</AppText>
      <Pressable accessibilityRole="button" onPress={onRetry}><AppText color={colors.error} style={styles.bold}>Reîncearcă</AppText></Pressable>
    </View>
  );
}

function GymFilterSheet({
  visible,
  gyms,
  selectedGymId,
  onClose,
  onSelect,
}: {
  visible: boolean;
  gyms: LookupOption[];
  selectedGymId?: string;
  onClose: () => void;
  onSelect: (gymId?: string) => void;
}) {
  const { colors } = useAppTheme();
  const insets = useSafeAreaInsets();
  return (
    <BottomSheetModal
      visible={visible}
      onClose={onClose}
      snapPoints={['50%', '72%']}
      initialIndex={0}
      scrollable
      sheetStyle={[styles.sheet, { backgroundColor: colors.surface, paddingBottom: insets.bottom }]}> 
      <View style={styles.sheetHandleArea}><View style={[styles.sheetHandle, { backgroundColor: colors.outline }]} /></View>
      <View style={styles.sheetHeader}>
        <View>
          <AppText variant="titleLarge" style={styles.bold}>Sala de vânzare</AppText>
          <AppText variant="bodySmall" color={colors.onSurfaceVariant}>Filtrează accesul după sala care a vândut abonamentul</AppText>
        </View>
      </View>
      <BottomSheetScrollView contentContainerStyle={styles.sheetOptions} showsVerticalScrollIndicator={false}>
        <GymOption label="Toate sălile" selected={!selectedGymId} onPress={() => onSelect(undefined)} />
        {gyms.map((gym) => <GymOption key={gym.id} label={gym.name} selected={gym.id === selectedGymId} onPress={() => onSelect(gym.id)} />)}
      </BottomSheetScrollView>
    </BottomSheetModal>
  );
}

function GymOption({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  const { colors } = useAppTheme();
  return (
    <Pressable
      accessibilityRole="radio"
      accessibilityState={{ selected }}
      onPress={onPress}
      style={({ pressed }) => [styles.gymOption, { backgroundColor: selected ? colors.primaryContainer : colors.surfaceContainerLow, opacity: pressed ? 0.65 : 1 }]}>
      <MaterialIcon name="check_circle" size={22} color={selected ? colors.primary : colorWithAlpha(colors.onSurfaceVariant, 0.35)} />
      <AppText variant="bodyLarge" style={styles.gymOptionText}>{label}</AppText>
    </Pressable>
  );
}

function rangeHint(range: MembershipTrendRange) {
  if (range === '12w') return 'Active la închiderea săptămânii · activări cumulate';
  if (range === '12m') return 'Active la închiderea lunii · activări cumulate';
  return 'Active la închiderea zilei · activări în zi';
}

function axisLabel(point: MembershipTrendPoint, range: MembershipTrendRange, index: number, count: number) {
  if (count > 8 && index % Math.ceil(count / 5) !== 0 && index !== count - 1) return '';
  if (range === '12m') return point.periodStart.toLocaleDateString('ro-RO', { month: 'short' }).replace('.', '');
  if (range === '12w') return point.periodStart.toLocaleDateString('ro-RO', { day: '2-digit', month: 'short' }).replace('.', '');
  return point.periodStart.toLocaleDateString('ro-RO', { day: '2-digit', month: '2-digit' });
}

function formatPeriod(point: MembershipTrendPoint, range: MembershipTrendRange) {
  const formatter = new Intl.DateTimeFormat('ro-RO', { day: '2-digit', month: 'short', year: 'numeric' });
  if (range === '7d' || range === '30d' || point.periodStart.getTime() === point.periodEnd.getTime()) return formatter.format(point.periodStart);
  return `${formatter.format(point.periodStart)} – ${formatter.format(point.periodEnd)}`;
}

function errorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  if (!error || typeof error !== 'object') return String(error);

  // PostgREST errors are plain objects in React Native rather than Error
  // instances. String(error) turns them into "[object Object]" and hides the
  // useful database message, detail, and hint.
  const fields = error as Record<string, unknown>;
  const parts = [fields.message, fields.details, fields.hint, fields.code]
    .filter((value): value is string => typeof value === 'string' && value.trim().length > 0);
  return parts.length ? parts.join('\n') : 'A apărut o eroare neașteptată.';
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  content: { padding: 16, paddingBottom: 32, gap: 14 },
  bold: { fontWeight: '700' },
  filterBadge: { position: 'absolute', right: 4, top: 4, width: 7, height: 7, borderRadius: 4 },
  scopeCard: { minHeight: 68, padding: 14, borderRadius: 16, borderCurve: 'continuous', flexDirection: 'row', alignItems: 'center', gap: 10 },
  scopeCopy: { flex: 1, gap: 2 },
  segmented: { height: 46, padding: 4, borderRadius: 14, borderCurve: 'continuous', flexDirection: 'row', gap: 4 },
  segment: { flex: 1, alignItems: 'center', justifyContent: 'center', borderRadius: 10, borderCurve: 'continuous' },
  estimatedBanner: { borderRadius: 14, borderCurve: 'continuous', padding: 12, flexDirection: 'row', gap: 10, alignItems: 'flex-start' },
  bannerCopy: { flex: 1 },
  chartCard: { borderRadius: 18, borderCurve: 'continuous', borderWidth: StyleSheet.hairlineWidth, backgroundColor: 'transparent', overflow: 'hidden', paddingVertical: 16 },
  chartHeading: { paddingHorizontal: 16, flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 6 },
  total: { fontWeight: '700', fontVariant: ['tabular-nums'] },
  chartInstructions: { paddingHorizontal: 16, marginTop: 2 },
  definitionCard: { padding: 14, borderRadius: 16, borderCurve: 'continuous', borderWidth: StyleSheet.hairlineWidth, flexDirection: 'row', gap: 10, alignItems: 'flex-start' },
  definitionCopy: { flex: 1, gap: 4 },
  empty: { minHeight: 200, borderRadius: 18, borderCurve: 'continuous', borderWidth: StyleSheet.hairlineWidth, alignItems: 'center', justifyContent: 'center', padding: 24, gap: 10 },
  emptyCopy: { textAlign: 'center' },
  errorState: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 32, gap: 14 },
  errorCopy: { textAlign: 'center' },
  retryButton: { minHeight: 46, borderRadius: 23, borderCurve: 'continuous', paddingHorizontal: 18, flexDirection: 'row', gap: 8, alignItems: 'center', justifyContent: 'center' },
  inlineError: { borderRadius: 14, borderCurve: 'continuous', padding: 12, flexDirection: 'row', alignItems: 'center', gap: 10 },
  inlineErrorCopy: { flex: 1 },
  sheet: { borderTopLeftRadius: 28, borderTopRightRadius: 28, borderCurve: 'continuous' },
  sheetHandleArea: { alignItems: 'center', paddingVertical: 10 },
  sheetHandle: { width: 36, height: 4, borderRadius: 2 },
  sheetHeader: { paddingHorizontal: 20, paddingBottom: 12 },
  sheetOptions: { padding: 12, gap: 8 },
  gymOption: { minHeight: 52, borderRadius: 12, borderCurve: 'continuous', paddingHorizontal: 14, flexDirection: 'row', alignItems: 'center', gap: 12 },
  gymOptionText: { flex: 1 },
});
