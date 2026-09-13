import React from 'react';
import { BottomSheetScrollView } from '@gorhom/bottom-sheet';
import { Pressable, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/app-text';
import { BottomSheetModal } from '@/components/bottom-sheet-modal';
import { DateRangeDialog } from '@/components/calendar-dialog';
import { MaterialIcon } from '@/components/material-icon';
import type { MaterialIconName } from '@/constants/material-icons.generated';
import type { MemberFilters, MembershipStatusFilter } from '@/repositories/members-repository';
import type { LookupOption } from '@/repositories/lookups-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';
import { formatCalendarDate, todayCalendarDate, type CalendarDate } from '@/utils/calendar-date';

export type AppliedMemberFilters = Omit<MemberFilters, 'search'>;

interface MembersFilterSheetProps {
  visible: boolean;
  value: AppliedMemberFilters;
  gyms: LookupOption[];
  plans: LookupOption[];
  onClose: () => void;
  onApply: (filters: AppliedMemberFilters) => void;
  onClear: () => void;
}

const emptyFilters: AppliedMemberFilters = {
  membershipStatus: 'all',
  frozenStatus: 'all',
};

export function MembersFilterSheet({
  visible,
  value,
  gyms,
  plans,
  onClose,
  onApply,
  onClear,
}: MembersFilterSheetProps) {
  const { colors } = useAppTheme();
  const [draft, setDraft] = React.useState<AppliedMemberFilters>(value);
  const [planOpen, setPlanOpen] = React.useState(false);

  const update = <Key extends keyof AppliedMemberFilters>(key: Key, next: AppliedMemberFilters[Key]) => {
    setDraft((current) => ({ ...current, [key]: next }));
  };

  const setMembershipStatus = (status: MembershipStatusFilter) => {
    setDraft((current) => ({
      ...current,
      membershipStatus: status,
      expiringInDays: status === 'expiring' ? current.expiringInDays : undefined,
    }));
  };

  const selectedPlan = plans.find((plan) => plan.id === draft.planId);

  return (
    <BottomSheetModal
      visible={visible}
      onClose={onClose}
      snapPoints={['50%', '85%']}
      initialIndex={1}
      scrollable
      sheetStyle={[styles.sheet, { backgroundColor: colors.surface }]}>

          <View style={styles.header}>
            <MaterialIcon name="filter_list" size={24} color={colors.primary} />
            <AppText variant="titleLarge" style={styles.headerTitle}>
              Filtre
            </AppText>
            <Pressable
              accessibilityRole="button"
              onPress={() => setDraft(emptyFilters)}
              hitSlop={8}
              style={({ pressed }) => ({ opacity: pressed ? 0.55 : 1, paddingVertical: 8 })}>
              <AppText color={colors.primary} style={styles.resetText}>
                Resetează
              </AppText>
            </Pressable>
          </View>
          <View style={[styles.rule, { backgroundColor: colors.outlineVariant }]} />

          <BottomSheetScrollView
            contentInsetAdjustmentBehavior="automatic"
            style={styles.filtersScroll}
            contentContainerStyle={styles.filters}
            showsVerticalScrollIndicator={false}>
            <FilterSection title="Sală">
              <Chip label="Toate" selected={!draft.gymId} onPress={() => update('gymId', undefined)} />
              {gyms.map((gym) => (
                <Chip
                  key={gym.id}
                  label={gym.name}
                  selected={draft.gymId === gym.id}
                  onPress={() => update('gymId', draft.gymId === gym.id ? undefined : gym.id)}
                />
              ))}
            </FilterSection>

            <FilterSection title="Status Abonament">
              <Chip label="Toate" selected={(draft.membershipStatus ?? 'all') === 'all'} onPress={() => setMembershipStatus('all')} />
              <Chip label="Activ" icon="check_circle" iconColor="#4CAF50" selected={draft.membershipStatus === 'active'} onPress={() => setMembershipStatus('active')} />
              <Chip label="Expiră în curând" icon="warning_amber" iconColor="#FF9800" selected={draft.membershipStatus === 'expiring'} onPress={() => setMembershipStatus('expiring')} />
              <Chip label="Expirat" icon="cancel" iconColor="#F44336" selected={draft.membershipStatus === 'expired'} onPress={() => setMembershipStatus('expired')} />
              <Chip label="Fără abonament" icon="no_accounts" iconColor="#9E9E9E" selected={draft.membershipStatus === 'inactive'} onPress={() => setMembershipStatus('inactive')} />
              <Chip label="Anulat" icon="block" iconColor="#9C27B0" selected={draft.membershipStatus === 'canceled'} onPress={() => setMembershipStatus('canceled')} />
            </FilterSection>

            {draft.membershipStatus === 'expiring' ? (
              <View style={styles.subsection}>
                <AppText variant="titleSmall">Expiră în</AppText>
                <View style={styles.chips}>
                  <Chip label="Toate (≤7 zile)" selected={draft.expiringInDays === undefined} onPress={() => update('expiringInDays', undefined)} />
                  <Chip label="Azi" selected={draft.expiringInDays === 0} onPress={() => update('expiringInDays', 0)} />
                  <Chip label="Mâine" selected={draft.expiringInDays === 1} onPress={() => update('expiringInDays', 1)} />
                  <Chip label="Poimâine" selected={draft.expiringInDays === 2} onPress={() => update('expiringInDays', 2)} />
                  <Chip label="În 3 zile" selected={draft.expiringInDays === 3} onPress={() => update('expiringInDays', 3)} />
                </View>
              </View>
            ) : null}

            <FilterSection title="Status Îngheț">
              <Chip label="Toate" selected={(draft.frozenStatus ?? 'all') === 'all'} onPress={() => update('frozenStatus', 'all')} />
              <Chip label="Nu" icon="check" iconColor="#4CAF50" selected={draft.frozenStatus === 'not_frozen'} onPress={() => update('frozenStatus', 'not_frozen')} />
              <Chip label="Da" icon="ac_unit" iconColor="#2196F3" selected={draft.frozenStatus === 'frozen'} onPress={() => update('frozenStatus', 'frozen')} />
            </FilterSection>

            <View style={styles.sectionBlock}>
              <AppText variant="titleMedium" style={styles.sectionTitle}>Tip Abonament</AppText>
              <Pressable
                accessibilityRole="button"
                onPress={() => setPlanOpen((open) => !open)}
                style={({ pressed }) => [
                  styles.select,
                  { borderColor: colors.outline, opacity: pressed ? 0.7 : 1 },
                ]}>
                <MaterialIcon name="card_membership" size={24} color={colors.onSurfaceVariant} />
                <AppText numberOfLines={1} variant="bodyLarge" style={styles.selectText}>
                  {selectedPlan?.name ?? 'Toate abonamentele'}
                </AppText>
                <MaterialIcon
                  name="arrow_drop_down"
                  size={24}
                  color={colors.onSurfaceVariant}
                  style={planOpen ? styles.rotatedIcon : undefined}
                />
              </Pressable>
              {planOpen ? (
                <View style={[styles.optionMenu, { borderColor: colors.outlineVariant, backgroundColor: colors.surfaceContainerLow }]}>
                  <PlanOption label="Toate abonamentele" selected={!draft.planId} onPress={() => { update('planId', undefined); setPlanOpen(false); }} />
                  {plans.map((plan) => (
                    <PlanOption key={plan.id} label={plan.name} selected={draft.planId === plan.id} onPress={() => { update('planId', plan.id); setPlanOpen(false); }} />
                  ))}
                </View>
              ) : null}
            </View>

            <DateRangeFilter
              title="Data Înregistrării"
              start={draft.registrationStart}
              end={draft.registrationEnd}
              onChange={(start, end) => setDraft((current) => ({ ...current, registrationStart: start, registrationEnd: end }))}
            />
            <DateRangeFilter
              title="Activitate Check-in"
              start={draft.checkInStart}
              end={draft.checkInEnd}
              onChange={(start, end) => setDraft((current) => ({ ...current, checkInStart: start, checkInEnd: end }))}
            />
          </BottomSheetScrollView>

          <View style={[styles.actions, {
            borderTopColor: colors.outlineVariant,
            backgroundColor: colorWithAlpha(colors.surfaceContainerHighest, 0.3),
            paddingBottom: 24,
          }]}>
            <ActionButton
              label="Anulează"
              outlined
              onPress={() => {
                onClear();
                onClose();
              }}
            />
            <ActionButton
              label="Aplică Filtre"
              onPress={() => {
                onApply(draft);
                onClose();
              }}
            />
          </View>
    </BottomSheetModal>
  );
}

function FilterSection({ title, children }: React.PropsWithChildren<{ title: string }>) {
  return (
    <View style={styles.sectionBlock}>
      <AppText variant="titleMedium" style={styles.sectionTitle}>{title}</AppText>
      <View style={styles.chips}>{children}</View>
    </View>
  );
}

function Chip({
  label,
  selected,
  onPress,
  icon,
  iconColor,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
  icon?: MaterialIconName;
  iconColor?: string;
}) {
  const { colors } = useAppTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected }}
      onPress={onPress}
      style={({ pressed }) => [
        styles.chip,
        {
          backgroundColor: selected ? colors.secondaryContainer : colors.surfaceContainerLow,
          borderColor: selected ? colors.onSurfaceVariant : colors.outlineVariant,
          opacity: pressed ? 0.7 : 1,
        },
      ]}>
      {icon ? <MaterialIcon name={icon} size={16} color={iconColor ?? colors.onSurfaceVariant} /> : null}
      <AppText variant="body" style={icon ? styles.chipWithIcon : undefined}>{label}</AppText>
    </Pressable>
  );
}

function PlanOption({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  const { colors } = useAppTheme();
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.planOption, { opacity: pressed ? 0.6 : 1 }]}>
      <AppText variant="bodyLarge" color={selected ? colors.primary : colors.onSurface} style={selected ? styles.selectedOption : undefined}>{label}</AppText>
    </Pressable>
  );
}

function DateRangeFilter({
  title,
  start,
  end,
  onChange,
}: {
  title: string;
  start?: CalendarDate;
  end?: CalendarDate;
  onChange: (start?: CalendarDate, end?: CalendarDate) => void;
}) {
  const { colors } = useAppTheme();
  const [dialogOpen, setDialogOpen] = React.useState(false);

  return (
    <View style={styles.sectionBlock}>
      <AppText variant="titleMedium" style={styles.sectionTitle}>{title}</AppText>
      <View style={styles.dateRow}>
        <DateButton label="De la" date={start} onPress={() => setDialogOpen(true)} />
        <DateButton label="Până la" date={end} onPress={() => setDialogOpen(true)} />
      </View>
      {start && end ? (
        <Pressable onPress={() => onChange(undefined, undefined)} style={styles.clearDate}>
          <MaterialIcon name="clear" size={16} color={colors.error} />
          <AppText color={colors.error} style={styles.clearDateText}>Șterge filtru</AppText>
        </Pressable>
      ) : null}
      <DateRangeDialog visible={dialogOpen} value={start && end ? { start, end } : undefined}
        minimumDate="2020-01-01" maximumDate={todayCalendarDate()} title={title}
        onCancel={() => setDialogOpen(false)} onApply={(range) => { onChange(range.start, range.end); setDialogOpen(false); }} />
    </View>
  );
}

function DateButton({ label, date, onPress }: { label: string; date?: CalendarDate; onPress: () => void }) {
  const { colors } = useAppTheme();
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.dateButton, { borderColor: colors.outline, opacity: pressed ? 0.65 : 1 }]}>
      <MaterialIcon name="date_range" size={20} color={colors.primary} />
      <View style={styles.dateCopy}>
        <AppText color={colors.onSurfaceVariant} style={styles.dateLabel}>{label}</AppText>
        <AppText style={styles.dateValue}>{date ? formatDate(date) : 'Selectează'}</AppText>
      </View>
    </Pressable>
  );
}

function ActionButton({ label, onPress, outlined = false }: { label: string; onPress: () => void; outlined?: boolean }) {
  const { colors } = useAppTheme();
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [
        styles.actionButton,
        {
          backgroundColor: outlined ? 'transparent' : colors.primary,
          borderColor: outlined ? colors.outline : colors.primary,
          opacity: pressed ? 0.72 : 1,
        },
      ]}>
      <AppText variant="titleSmall" color={outlined ? colors.primary : colors.onPrimary}>{label}</AppText>
    </Pressable>
  );
}

function formatDate(date: CalendarDate): string { return formatCalendarDate(date); }

const styles = StyleSheet.create({
  sheet: { borderTopLeftRadius: 28, borderTopRightRadius: 28, overflow: 'hidden' },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 24, paddingBottom: 16 },
  headerTitle: { flex: 1, fontWeight: '700', marginLeft: 12 },
  resetText: { fontWeight: '500' },
  rule: { height: StyleSheet.hairlineWidth },
  filtersScroll: { flex: 1 },
  filters: { padding: 24, paddingBottom: 12 },
  sectionBlock: { marginBottom: 32 },
  sectionTitle: { fontWeight: '700', marginBottom: 12 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: {
    minHeight: 32,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 12,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 8,
    borderCurve: 'continuous',
  },
  chipWithIcon: { marginLeft: 4 },
  subsection: { marginTop: -16, marginBottom: 32 },
  select: {
    minHeight: 56,
    borderWidth: 1,
    borderRadius: 12,
    borderCurve: 'continuous',
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
  },
  selectText: { flex: 1, marginLeft: 12 },
  optionMenu: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 12, marginTop: 6, overflow: 'hidden' },
  planOption: { paddingHorizontal: 16, paddingVertical: 12 },
  selectedOption: { fontWeight: '700' },
  rotatedIcon: { transform: [{ rotate: '180deg' }] },
  dateRow: { flexDirection: 'row', gap: 8 },
  dateButton: { flex: 1, minHeight: 56, borderWidth: 1, borderRadius: 12, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 10 },
  dateCopy: { flex: 1, marginLeft: 6 },
  dateLabel: { fontSize: 10, lineHeight: 14 },
  dateValue: { fontSize: 12, lineHeight: 18, fontWeight: '600' },
  pickerPanel: { borderRadius: 12, marginTop: 8, padding: 8 },
  doneButton: { alignSelf: 'flex-end', padding: 10 },
  clearDate: { flexDirection: 'row', alignItems: 'center', alignSelf: 'flex-start', marginTop: 8, paddingVertical: 4 },
  clearDateText: { marginLeft: 4, fontWeight: '500' },
  actions: { flexDirection: 'row', gap: 12, borderTopWidth: StyleSheet.hairlineWidth, padding: 24 },
  actionButton: { flex: 1, minHeight: 52, borderRadius: 24, borderCurve: 'continuous', borderWidth: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 10 },
});
