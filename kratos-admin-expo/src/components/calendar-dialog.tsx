import { Calendar, LocaleConfig, type DateData } from 'react-native-calendars';
import type { MarkedDates } from 'react-native-calendars/src/types';
import React from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/app-text';
import { MaterialIcon } from '@/components/material-icon';
import {
  calendarDateToLocalDate,
  compareCalendarDates,
  expandCalendarDateRange,
  formatCalendarDate,
  isCalendarDate,
  todayCalendarDate,
  type CalendarDate,
  type CalendarDateRange,
} from '@/utils/calendar-date';
import { useAppTheme } from '@/theme/theme';

LocaleConfig.locales.ro = {
  monthNames: ['Ianuarie', 'Februarie', 'Martie', 'Aprilie', 'Mai', 'Iunie', 'Iulie', 'August', 'Septembrie', 'Octombrie', 'Noiembrie', 'Decembrie'],
  monthNamesShort: ['Ian', 'Feb', 'Mar', 'Apr', 'Mai', 'Iun', 'Iul', 'Aug', 'Sep', 'Oct', 'Noi', 'Dec'],
  dayNames: ['Duminică', 'Luni', 'Marți', 'Miercuri', 'Joi', 'Vineri', 'Sâmbătă'],
  dayNamesShort: ['Du', 'Lu', 'Ma', 'Mi', 'Jo', 'Vi', 'Sâ'],
  today: 'Astăzi',
};
LocaleConfig.defaultLocale = 'ro';

interface CommonDateDialogProps {
  visible: boolean;
  minimumDate: CalendarDate;
  maximumDate: CalendarDate;
  title?: string;
  onCancel: () => void;
}

export interface SingleDateDialogProps extends CommonDateDialogProps {
  value: CalendarDate;
  onApply: (value: CalendarDate) => void;
}

export interface DateRangeDialogProps extends CommonDateDialogProps {
  value?: CalendarDateRange;
  onApply: (range: CalendarDateRange) => void;
}

function initialMonth(value: CalendarDate | undefined, minimumDate: CalendarDate, maximumDate: CalendarDate): CalendarDate {
  const date = value && isCalendarDate(value) ? value : todayCalendarDate();
  if (compareCalendarDates(date, minimumDate) < 0) return minimumDate;
  if (compareCalendarDates(date, maximumDate) > 0) return maximumDate;
  return date;
}

function withinRange(value: CalendarDate, minimumDate: CalendarDate, maximumDate: CalendarDate): boolean {
  return compareCalendarDates(value, minimumDate) >= 0 && compareCalendarDates(value, maximumDate) <= 0;
}

export function SingleDateDialog(props: SingleDateDialogProps) {
  if (!props.visible) return null;
  return <SingleDateDialogContent key={`${props.value}-${props.minimumDate}-${props.maximumDate}`} {...props} />;
}

function SingleDateDialogContent({ value, visible, minimumDate, maximumDate, title = 'Selectează data', onCancel, onApply }: SingleDateDialogProps) {
  const [draft, setDraft] = React.useState(value);
  const [month, setMonth] = React.useState(() => initialMonth(value, minimumDate, maximumDate));

  return (
    <CalendarDialogFrame title={title} visible={visible} minimumDate={minimumDate} maximumDate={maximumDate}
      month={month} onMonthChange={setMonth} onCancel={onCancel}
      applyDisabled={!withinRange(draft, minimumDate, maximumDate)}
      onApply={() => onApply(draft)}>
      <CalendarSurface currentMonth={month} minimumDate={minimumDate} maximumDate={maximumDate} onMonthChange={setMonth}
        selected={draft} onPress={(date) => { setDraft(date); setMonth(date); }} />
    </CalendarDialogFrame>
  );
}

export function DateRangeDialog(props: DateRangeDialogProps) {
  if (!props.visible) return null;
  return <DateRangeDialogContent key={`${props.value?.start ?? ''}-${props.value?.end ?? ''}-${props.minimumDate}-${props.maximumDate}`} {...props} />;
}

function DateRangeDialogContent({ value, visible, minimumDate, maximumDate, title = 'Selectează intervalul', onCancel, onApply }: DateRangeDialogProps) {
  const [draftStart, setDraftStart] = React.useState<CalendarDate | undefined>(value?.start);
  const [draftEnd, setDraftEnd] = React.useState<CalendarDate | undefined>(value?.end);
  const [month, setMonth] = React.useState(() => initialMonth(value?.start, minimumDate, maximumDate));

  const choose = (date: CalendarDate) => {
    if (!draftStart || draftEnd) {
      setDraftStart(date);
      setDraftEnd(undefined);
    } else if (compareCalendarDates(date, draftStart) < 0) {
      setDraftStart(date);
      setDraftEnd(undefined);
    } else {
      setDraftEnd(date);
    }
    setMonth(date);
  };
  const complete = Boolean(draftStart && draftEnd && withinRange(draftStart, minimumDate, maximumDate) && withinRange(draftEnd, minimumDate, maximumDate) && compareCalendarDates(draftStart, draftEnd) <= 0);

  return (
    <CalendarDialogFrame title={title} visible={visible} minimumDate={minimumDate} maximumDate={maximumDate}
      month={month} onMonthChange={setMonth} onCancel={onCancel} applyDisabled={!complete}
      onApply={() => { if (draftStart && draftEnd) onApply({ start: draftStart, end: draftEnd }); }}>
      <View style={styles.rangeSummary}>
        <RangeSummary label="De la" value={draftStart} />
        <RangeSummary label="Până la" value={draftEnd} />
      </View>
      <CalendarSurface currentMonth={month} minimumDate={minimumDate} maximumDate={maximumDate} onMonthChange={setMonth}
        markedRange={draftStart ? { start: draftStart, end: draftEnd ?? draftStart } : undefined}
        onPress={choose} />
    </CalendarDialogFrame>
  );
}

function CalendarDialogFrame({ visible, title, minimumDate, maximumDate, month, onMonthChange, onCancel, onApply, applyDisabled, children }: React.PropsWithChildren<CommonDateDialogProps & {
  month: CalendarDate;
  onMonthChange: (date: CalendarDate) => void;
  onApply: () => void;
  applyDisabled: boolean;
}>) {
  const { colors } = useAppTheme();
  const [monthYearOpen, setMonthYearOpen] = React.useState(false);
  const current = calendarDateToLocalDate(month);
  const currentYear = current.getFullYear();
  const currentMonth = current.getMonth();
  const setCalendarMonth = (year: number, monthIndex: number) => {
    const candidate = `${year}-${String(monthIndex + 1).padStart(2, '0')}-01`;
    const startOfRange = compareCalendarDates(candidate, minimumDate) < 0 ? minimumDate : candidate;
    onMonthChange(startOfRange);
    setMonthYearOpen(false);
  };

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onCancel} statusBarTranslucent>
      <View style={styles.backdrop}>
        <Pressable accessibilityRole="button" accessibilityLabel="Închide selectorul de dată" style={StyleSheet.absoluteFill} onPress={onCancel} />
        <View accessibilityViewIsModal style={[styles.dialog, { backgroundColor: colors.surface }]}>
          <View style={styles.header}>
            <AppText variant="titleLarge" style={styles.title}>{title}</AppText>
            <Pressable accessibilityRole="button" accessibilityLabel="Închide" onPress={onCancel} hitSlop={10} style={styles.close}>
              <MaterialIcon name="close" size={22} color={colors.onSurfaceVariant} />
            </Pressable>
          </View>
          <Pressable accessibilityRole="button" accessibilityLabel={`Luna selectată: ${formatCalendarDate(month, { month: 'long', year: 'numeric' })}. Alege luna și anul.`}
            onPress={() => setMonthYearOpen((open) => !open)} style={[styles.monthTrigger, { backgroundColor: colors.surfaceContainerLow }]}> 
            <AppText variant="titleMedium" style={styles.monthTriggerText}>{formatCalendarDate(month, { month: 'long', year: 'numeric' })}</AppText>
            <MaterialIcon name="expand_more" size={22} color={colors.primary} />
          </Pressable>
          {monthYearOpen ? (
            <MonthYearChooser year={currentYear} selectedMonth={currentMonth} minimumDate={minimumDate} maximumDate={maximumDate} onSelect={setCalendarMonth} />
          ) : children}
          <View style={styles.actions}>
            <Pressable accessibilityRole="button" accessibilityLabel="Anulează selecția" onPress={onCancel} style={styles.actionButton}>
              <AppText color={colors.primary} style={styles.actionText}>Anulează</AppText>
            </Pressable>
            <Pressable accessibilityRole="button" accessibilityLabel="Aplică selecția" disabled={applyDisabled} onPress={onApply} style={[styles.actionButton, { opacity: applyDisabled ? 0.4 : 1 }]}> 
              <AppText color={colors.primary} style={styles.actionText}>Aplică</AppText>
            </Pressable>
          </View>
        </View>
      </View>
    </Modal>
  );
}

function CalendarSurface({ currentMonth, minimumDate, maximumDate, selected, markedRange, onPress, onMonthChange }: {
  currentMonth: CalendarDate;
  minimumDate: CalendarDate;
  maximumDate: CalendarDate;
  selected?: CalendarDate;
  markedRange?: CalendarDateRange;
  onPress: (date: CalendarDate) => void;
  onMonthChange: (date: CalendarDate) => void;
}) {
  const { colors } = useAppTheme();
  const markedDates = React.useMemo<MarkedDates>(() => {
    if (selected) return { [selected]: { selected: true, selectedColor: colors.primary, selectedTextColor: colors.onPrimary } };
    if (!markedRange) return {};
    const dates = expandCalendarDateRange(markedRange);
    return Object.fromEntries(dates.map((date) => [date, {
      startingDay: date === markedRange.start,
      endingDay: date === markedRange.end,
      color: date === markedRange.start || date === markedRange.end ? colors.primary : colors.primaryContainer,
      textColor: date === markedRange.start || date === markedRange.end ? colors.onPrimary : colors.onPrimaryContainer,
    }])) as MarkedDates;
  }, [colors.onPrimary, colors.onPrimaryContainer, colors.primary, colors.primaryContainer, markedRange, selected]);

  return <Calendar current={currentMonth} minDate={minimumDate} maxDate={maximumDate} firstDay={1} markingType="period"
    markedDates={markedDates} enableSwipeMonths onMonthChange={(day: DateData) => onMonthChange(day.dateString)} onDayPress={(day: DateData) => onPress(day.dateString)}
    theme={{
      calendarBackground: colors.surface,
      textSectionTitleColor: colors.onSurfaceVariant,
      monthTextColor: colors.onSurface,
      dayTextColor: colors.onSurface,
      todayTextColor: colors.primary,
      arrowColor: colors.primary,
      textDisabledColor: colors.outlineVariant,
      textDayFontWeight: '500',
      textMonthFontWeight: '700',
      textDayHeaderFontWeight: '600',
    }} />;
}

function MonthYearChooser({ year, selectedMonth, minimumDate, maximumDate, onSelect }: {
  year: number;
  selectedMonth: number;
  minimumDate: CalendarDate;
  maximumDate: CalendarDate;
  onSelect: (year: number, month: number) => void;
}) {
  const { colors } = useAppTheme();
  const [displayYear, setDisplayYear] = React.useState(year);
  const minYear = Number(minimumDate.slice(0, 4));
  const maxYear = Number(maximumDate.slice(0, 4));
  const months = LocaleConfig.locales.ro.monthNamesShort;
  return <View style={styles.monthChooser}>
    <View style={styles.yearControls}>
      <Pressable accessibilityRole="button" accessibilityLabel="Anul anterior" disabled={displayYear <= minYear} onPress={() => setDisplayYear((value) => value - 1)} style={({ pressed }) => [styles.yearButton, { opacity: pressed || displayYear <= minYear ? 0.4 : 1 }]}><MaterialIcon name="arrow_back" size={24} color={colors.primary} /></Pressable>
      <AppText variant="titleMedium" style={styles.yearText}>{displayYear}</AppText>
      <Pressable accessibilityRole="button" accessibilityLabel="Anul următor" disabled={displayYear >= maxYear} onPress={() => setDisplayYear((value) => value + 1)} style={({ pressed }) => [styles.yearButton, { opacity: pressed || displayYear >= maxYear ? 0.4 : 1 }]}><MaterialIcon name="chevron_right" size={24} color={colors.primary} /></Pressable>
    </View>
    <ScrollView contentContainerStyle={styles.monthGrid}>
      {months.map((label: string, monthIndex: number) => {
        const candidate = `${displayYear}-${String(monthIndex + 1).padStart(2, '0')}-01`;
        const nextMonth = monthIndex === 11 ? `${displayYear + 1}-01-01` : `${displayYear}-${String(monthIndex + 2).padStart(2, '0')}-01`;
        const disabled = compareCalendarDates(nextMonth, minimumDate) <= 0 || compareCalendarDates(candidate, maximumDate) > 0;
        const selected = displayYear === year && monthIndex === selectedMonth;
        return <Pressable key={label} accessibilityRole="button" accessibilityState={{ selected, disabled }} accessibilityLabel={`${label} ${displayYear}`} disabled={disabled} onPress={() => onSelect(displayYear, monthIndex)} style={({ pressed }) => [styles.monthOption, { backgroundColor: selected ? colors.primaryContainer : colors.surfaceContainerLow, opacity: pressed || disabled ? 0.45 : 1 }]}><AppText color={selected ? colors.onPrimaryContainer : colors.onSurface}>{label}</AppText></Pressable>;
      })}
    </ScrollView>
  </View>;
}

function RangeSummary({ label, value }: { label: string; value?: CalendarDate }) {
  const { colors } = useAppTheme();
  return <View style={[styles.rangeItem, { borderColor: colors.outlineVariant }]}><AppText variant="bodySmall" color={colors.onSurfaceVariant}>{label}</AppText><AppText numberOfLines={1} style={styles.rangeValue}>{value ? formatCalendarDate(value) : 'Alege data'}</AppText></View>;
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: '#00000066', alignItems: 'center', justifyContent: 'center', padding: 20 },
  dialog: { width: '100%', maxWidth: 440, borderRadius: 28, borderCurve: 'continuous', padding: 20 },
  header: { minHeight: 36, flexDirection: 'row', alignItems: 'center' }, title: { flex: 1, fontWeight: '700' }, close: { minWidth: 44, minHeight: 44, alignItems: 'center', justifyContent: 'center' },
  monthTrigger: { minHeight: 48, borderRadius: 12, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, marginTop: 8 }, monthTriggerText: { flex: 1, fontWeight: '700' },
  actions: { flexDirection: 'row', justifyContent: 'flex-end', marginTop: 8, gap: 4 }, actionButton: { minWidth: 72, minHeight: 48, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 10 }, actionText: { fontWeight: '700' },
  rangeSummary: { flexDirection: 'row', gap: 8, marginTop: 12, paddingHorizontal: 8 }, rangeItem: { flex: 1, minWidth: 0, borderWidth: StyleSheet.hairlineWidth, borderRadius: 10, padding: 10 }, rangeValue: { fontWeight: '700', marginTop: 2 },
  monthChooser: { minHeight: 306, paddingVertical: 12 }, yearControls: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 20 }, yearButton: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' }, yearText: { minWidth: 72, textAlign: 'center', fontWeight: '700' }, monthGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, padding: 8 }, monthOption: { width: '30%', minHeight: 44, borderRadius: 10, alignItems: 'center', justifyContent: 'center' },
});
