import React from 'react';
import { BottomSheetScrollView } from '@gorhom/bottom-sheet';
import { Pressable, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/app-text';
import { BottomSheetModal } from '@/components/bottom-sheet-modal';
import { DateRangeDialog } from '@/components/calendar-dialog';
import { MaterialIcon } from '@/components/material-icon';
import type { LookupOption } from '@/repositories/lookups-repository';
import type { RevenueFilters } from '@/repositories/revenue-repository';
import { useAppTheme } from '@/theme/theme';
import { calendarDateRangeLabel, todayCalendarDate } from '@/utils/calendar-date';

export type RevenueFilterState = Omit<RevenueFilters, 'search'>;
export const defaultRevenueFilters: RevenueFilterState = { paymentMethod: 'all', amount: 'all', deletedStatus: 'all' };

export function RevenueFilterSheet({ visible, value, gyms, plans, onClose, onApply, onClear }: { visible: boolean; value: RevenueFilterState; gyms: LookupOption[]; plans: LookupOption[]; onClose: () => void; onApply: (filters: RevenueFilterState) => void; onClear: () => void }) {
  const { colors } = useAppTheme();
  const [draft, setDraft] = React.useState(value);
  const [plansOpen, setPlansOpen] = React.useState(false);
  const [dateOpen, setDateOpen] = React.useState(false);
  const selectedPlan = plans.find((plan) => plan.id === draft.planId);
  const dateRange = draft.dateStart && draft.dateEnd ? { start: draft.dateStart, end: draft.dateEnd } : undefined;

  return <BottomSheetModal visible={visible} onClose={onClose} snapPoints={['50%', '85%']} initialIndex={1} scrollable sheetStyle={[styles.sheet, { backgroundColor: colors.surface }]}>
      <View style={styles.header}><AppText variant="titleLarge" style={styles.bold}>Filtre</AppText><Pressable accessibilityRole="button" onPress={() => { onClear(); onClose(); }} hitSlop={8}><AppText color={colors.primary}>Resetează</AppText></Pressable></View><View style={[styles.rule, { backgroundColor: colors.outlineVariant }]} />
          <BottomSheetScrollView contentInsetAdjustmentBehavior="automatic" style={styles.scroll} contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
            <FilterGroup title="Sală"><Chip label="Toate" selected={!draft.gymId} onPress={() => setDraft((current) => ({ ...current, gymId: undefined }))} />{gyms.map((gym) => <Chip key={gym.id} label={gym.name} selected={draft.gymId === gym.id} onPress={() => setDraft((current) => ({ ...current, gymId: current.gymId === gym.id ? undefined : gym.id }))} />)}</FilterGroup>
            <FilterGroup title="Metoda de plată">{([['all', 'Toate'], ['cash', '💵 Cash'], ['card', '💳 Card']] as const).map(([method, label]) => <Chip key={method} label={label} selected={(draft.paymentMethod ?? 'all') === method} onPress={() => setDraft((current) => ({ ...current, paymentMethod: method }))} />)}</FilterGroup>
            <FilterGroup title="Filtrează după sumă">{([['all', 'Toate'], ['zero', 'Doar 0 RON'], ['non_zero', 'Peste 0 RON']] as const).map(([amount, label]) => <Chip key={amount} label={label} selected={(draft.amount ?? 'all') === amount} onPress={() => setDraft((current) => ({ ...current, amount }))} />)}</FilterGroup>
            <FilterGroup title="Istoric șters"><Chip label="Normal" selected={(draft.deletedStatus ?? 'all') === 'all'} onPress={() => setDraft((current) => ({ ...current, deletedStatus: 'all' }))} /><Chip label="Șterse (audit)" selected={draft.deletedStatus === 'deleted'} onPress={() => setDraft((current) => ({ ...current, deletedStatus: 'deleted' }))} /></FilterGroup>
            <View style={styles.group}><AppText variant="titleMedium" style={styles.medium}>Plan abonament</AppText><Pressable accessibilityRole="button" onPress={() => setPlansOpen((open) => !open)} style={[styles.select, { borderColor: colors.outline }]}><AppText style={styles.selectText}>{selectedPlan?.name ?? 'Toate planurile'}</AppText><MaterialIcon name="arrow_drop_down" size={24} color={colors.onSurfaceVariant} style={plansOpen ? styles.rotate : undefined} /></Pressable>{plansOpen ? <View style={[styles.menu, { backgroundColor: colors.surfaceContainerHigh, borderColor: colors.outlineVariant }]}><Option label="Toate planurile" selected={!draft.planId} onPress={() => { setDraft((current) => ({ ...current, planId: undefined })); setPlansOpen(false); }} />{plans.map((plan) => <Option key={plan.id} label={plan.name} selected={draft.planId === plan.id} onPress={() => { setDraft((current) => ({ ...current, planId: plan.id })); setPlansOpen(false); }} />)}</View> : null}</View>
            <View style={styles.group}>
              <AppText variant="titleMedium" style={styles.medium}>Perioadă personalizată</AppText>
              <Pressable accessibilityRole="button" onPress={() => setDateOpen(true)} style={[styles.dateButton, { borderColor: colors.outline }]}>
                <MaterialIcon name="date_range" size={20} color={colors.primary} />
                <AppText style={styles.dateText}>{dateRange ? calendarDateRangeLabel(dateRange) : 'Selectează perioada'}</AppText>
                <MaterialIcon name="chevron_right" size={20} color={colors.onSurfaceVariant} />
              </Pressable>
              {dateRange ? <Pressable accessibilityRole="button" onPress={() => setDraft((current) => ({ ...current, dateStart: undefined, dateEnd: undefined }))} style={styles.clearDate}><MaterialIcon name="clear" size={16} color={colors.error} /><AppText color={colors.error} style={styles.clearText}>Șterge perioada</AppText></Pressable> : null}
              <DateRangeDialog visible={dateOpen} value={dateRange} minimumDate="2020-01-01" maximumDate={todayCalendarDate()} title="Perioadă venituri" onCancel={() => setDateOpen(false)} onApply={(range) => { setDraft((current) => ({ ...current, dateStart: range.start, dateEnd: range.end })); setDateOpen(false); }} />
            </View>
          </BottomSheetScrollView>
      <View style={[styles.applyArea, { borderTopColor: colors.outlineVariant }]}><Pressable accessibilityRole="button" onPress={() => { onApply(draft); onClose(); }} style={({ pressed }) => [styles.apply, { backgroundColor: colors.primary, opacity: pressed ? 0.72 : 1 }]}><AppText color={colors.onPrimary} style={styles.medium}>Aplică filtre</AppText></Pressable></View>
    </BottomSheetModal>;
}

function FilterGroup({ title, children }: React.PropsWithChildren<{ title: string }>) { return <View style={styles.group}><AppText variant="titleMedium" style={styles.medium}>{title}</AppText><View style={styles.chips}>{children}</View></View>; }
function Chip({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) { const { colors } = useAppTheme(); return <Pressable accessibilityRole="button" accessibilityState={{ selected }} onPress={onPress} style={({ pressed }) => [styles.chip, { backgroundColor: selected ? colors.secondaryContainer : colors.surfaceContainerLow, borderColor: selected ? colors.onSurfaceVariant : colors.outlineVariant, opacity: pressed ? 0.7 : 1 }]}><AppText>{label}</AppText></Pressable>; }
function Option({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) { const { colors } = useAppTheme(); return <Pressable accessibilityRole="button" accessibilityState={{ selected }} onPress={onPress} style={styles.option}><AppText color={selected ? colors.primary : undefined} style={selected ? styles.bold : undefined}>{label}</AppText></Pressable>; }

const styles = StyleSheet.create({
  sheet: { borderTopLeftRadius: 28, borderTopRightRadius: 28, overflow: 'hidden' }, header: { minHeight: 54, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 24, paddingBottom: 16 }, bold: { fontWeight: '700' }, medium: { fontWeight: '600' }, rule: { height: StyleSheet.hairlineWidth }, scroll: { flex: 1 }, content: { padding: 24, paddingBottom: 12 }, group: { marginBottom: 24, gap: 8 }, chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 }, chip: { minHeight: 40, borderWidth: StyleSheet.hairlineWidth, borderRadius: 20, paddingHorizontal: 12, alignItems: 'center', justifyContent: 'center' }, select: { minHeight: 56, borderWidth: 1, borderRadius: 8, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12 }, selectText: { flex: 1 }, rotate: { transform: [{ rotate: '180deg' }] }, menu: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 8, overflow: 'hidden' }, option: { minHeight: 44, paddingHorizontal: 16, justifyContent: 'center' }, dateButton: { minHeight: 56, borderWidth: 1, borderRadius: 8, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12 }, dateText: { flex: 1, marginLeft: 8 }, clearDate: { minHeight: 40, flexDirection: 'row', alignItems: 'center', alignSelf: 'flex-start' }, clearText: { marginLeft: 4 }, applyArea: { paddingHorizontal: 24, paddingTop: 16, paddingBottom: 24, borderTopWidth: StyleSheet.hairlineWidth }, apply: { minHeight: 52, borderRadius: 26, alignItems: 'center', justifyContent: 'center' },
});
