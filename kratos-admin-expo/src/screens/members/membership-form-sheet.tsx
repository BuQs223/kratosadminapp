import { BottomSheetScrollView, BottomSheetTextInput } from '@gorhom/bottom-sheet';
import { LinearGradient } from 'expo-linear-gradient';
import { useMutation, useQuery } from '@tanstack/react-query';
import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Switch,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/app-text';
import { BottomSheetModal } from '@/components/bottom-sheet-modal';
import { SingleDateDialog } from '@/components/calendar-dialog';
import { MaterialIcon } from '@/components/material-icon';
import type { MaterialIconName } from '@/constants/material-icons.generated';
import type { Membership } from '@/models/membership';
import {
  getMembershipFormOptions,
  saveMembership,
  createMembershipId,
} from '@/repositories/members-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';
import {
  addCalendarDays,
  compareCalendarDates,
  formatCalendarDate,
  todayCalendarDate,
  type CalendarDate,
} from '@/utils/calendar-date';

interface MembershipFormSheetProps {
  visible: boolean;
  memberId: string;
  membership: Membership | null;
  onClose: () => void;
  onSaved: () => void;
}

export function MembershipFormSheet({
  visible,
  memberId,
  membership,
  onClose,
  onSaved,
}: MembershipFormSheetProps) {
  const { colors } = useAppTheme();
  const insets = useSafeAreaInsets();
  const optionsQuery = useQuery({
    queryKey: ['membership-form-options'],
    queryFn: getMembershipFormOptions,
    enabled: visible,
    staleTime: 5 * 60_000,
  });
  const [planId, setPlanId] = React.useState<string | undefined>(membership?.planId || undefined);
  const [gymId, setGymId] = React.useState<string | undefined>(membership?.soldAtGymId || undefined);
  const [membershipId] = React.useState(() => membership?.id ?? createMembershipId());
  const [startDate, setStartDate] = React.useState<CalendarDate>(membership?.startDate ?? todayCalendarDate());
  const [endDate, setEndDate] = React.useState<CalendarDate>(() => membership?.endDate ?? addCalendarDays(todayCalendarDate(), 30));
  const [isActive, setIsActive] = React.useState(membership?.isActive ?? true);
  const [membershipType] = React.useState(membership?.membershipType ?? 'monthly');
  const [price, setPrice] = React.useState(((membership?.pricePaidCents ?? 0) / 100).toFixed(2));
  const [paymentMethod, setPaymentMethod] = React.useState(membership?.paymentMethod ?? 'cash');
  const [openSelect, setOpenSelect] = React.useState<'plan' | 'gym' | 'payment' | null>(null);
  const [editingDate, setEditingDate] = React.useState<'start' | 'end' | null>(null);
  const [validationError, setValidationError] = React.useState<string>();

  const saveMutation = useMutation({
    mutationFn: () => {
      if (!planId || !gymId) throw new Error('Selectează planul și sala');
      if (!price.trim()) throw new Error('Introduceți prețul');
      const numericPrice = Number.parseFloat(price.replace(',', '.'));
      if (!Number.isFinite(numericPrice) || numericPrice < 0) throw new Error('Preț invalid');
      return saveMembership({
        memberId,
        membershipId,
        planId,
        gymId,
        startDate,
        endDate,
        isActive,
        membershipType,
        pricePaidCents: Math.round(numericPrice * 100),
        paymentMethod,
      });
    },
    onSuccess: () => {
      onSaved();
      onClose();
    },
    onError: (error) => setValidationError(error instanceof Error ? error.message : String(error)),
  });

  const options = optionsQuery.data;
  const selectedPlan = options?.plans.find((plan) => plan.id === planId);
  const selectedGym = options?.gyms.find((gym) => gym.id === gymId);

  const changeDate = (date: CalendarDate) => {
    if (!editingDate) return;
    if (editingDate === 'start') {
      setStartDate(date);
      if (compareCalendarDates(endDate, date) < 0) setEndDate(addCalendarDays(date, 30));
    } else {
      setEndDate(date);
    }
    setEditingDate(null);
  };

  return (
    <>
    <BottomSheetModal
      visible={visible}
      onClose={onClose}
      keyboardAvoiding
      snapPoints={['60%', '90%']}
      initialIndex={1}
      scrollable
      disableDismiss={saveMutation.isPending}
      sheetStyle={[
        styles.sheet,
        { backgroundColor: colors.surface, paddingBottom: insets.bottom },
      ]}>
          <LinearGradient
            colors={[colorWithAlpha(colors.primary, 0.08), colorWithAlpha(colors.primary, 0.03)]}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={styles.header}>
            <View style={[styles.headerIcon, { backgroundColor: colorWithAlpha(colors.primary, 0.15) }]}>
              <MaterialIcon name="card_membership" size={24} color={colors.primary} />
            </View>
            <AppText variant="headlineMedium" style={styles.headerTitle}>
              {membership ? 'Editează Abonament' : 'Abonament Nou'}
            </AppText>
            <Pressable accessibilityRole="button" accessibilityLabel="Închide" onPress={onClose} hitSlop={10} style={({ pressed }) => ({ opacity: pressed ? 0.5 : 1, padding: 4 })}>
              <MaterialIcon name="close" size={24} color={colors.onSurfaceVariant} />
            </Pressable>
          </LinearGradient>

          {optionsQuery.isLoading ? (
            <View style={styles.loading}>
              <ActivityIndicator size="large" color={colors.primary} />
              <AppText color={colors.onSurfaceVariant} style={styles.loadingText}>Se încarcă...</AppText>
            </View>
          ) : optionsQuery.error ? (
            <View style={styles.loading}>
              <AppText selectable color={colors.error} style={styles.centerText}>
                Eroare: {optionsQuery.error instanceof Error ? optionsQuery.error.message : String(optionsQuery.error)}
              </AppText>
            </View>
          ) : (
            <BottomSheetScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.content}>
              {validationError ? (
                <View style={[styles.error, { backgroundColor: colorWithAlpha(colors.error, 0.1) }]}>
                  <AppText selectable color={colors.error}>{validationError}</AppText>
                </View>
              ) : null}

              <FormSelectCard
                label="Plan Abonament"
                value={selectedPlan?.name ?? 'Selectează un plan'}
                color="#1E88E5"
                icon="card_membership"
                open={openSelect === 'plan'}
                onToggle={() => setOpenSelect((current) => current === 'plan' ? null : 'plan')}>
                {options?.plans.map((plan) => (
                  <SelectOption key={plan.id} label={plan.name} selected={plan.id === planId} onPress={() => { setPlanId(plan.id); setOpenSelect(null); }} />
                ))}
              </FormSelectCard>

              <FormSelectCard
                label="Sală"
                value={selectedGym?.name ?? 'Selectează o sală'}
                color="#43A047"
                icon="fitness_center"
                open={openSelect === 'gym'}
                onToggle={() => setOpenSelect((current) => current === 'gym' ? null : 'gym')}>
                {options?.gyms.map((gym) => (
                  <SelectOption key={gym.id} label={gym.name} selected={gym.id === gymId} onPress={() => { setGymId(gym.id); setOpenSelect(null); }} />
                ))}
              </FormSelectCard>

              <View style={styles.row}>
                <GradientFieldCard color="#FB8C00" icon="payments" style={styles.flex}>
                  <AppText color={colors.onSurfaceVariant} style={styles.fieldLabel}>Preț (RON)</AppText>
                  <BottomSheetTextInput
                    value={price}
                    onChangeText={setPrice}
                    keyboardType="decimal-pad"
                    selectionColor={colors.primary}
                    style={[styles.fieldInput, { color: colors.onSurface }]}
                  />
                </GradientFieldCard>
                <View style={styles.columnGap} />
                <FormSelectCard
                  compact
                  label="Plată"
                  value={paymentMethod === 'card' ? 'Card' : 'Cash'}
                  color="#8E24AA"
                  icon="credit_card"
                  open={openSelect === 'payment'}
                  style={styles.flex}
                  onToggle={() => setOpenSelect((current) => current === 'payment' ? null : 'payment')}>
                  <SelectOption label="Cash" selected={paymentMethod === 'cash'} onPress={() => { setPaymentMethod('cash'); setOpenSelect(null); }} />
                  <SelectOption label="Card" selected={paymentMethod === 'card'} onPress={() => { setPaymentMethod('card'); setOpenSelect(null); }} />
                </FormSelectCard>
              </View>

              <View style={styles.row}>
                <DateCard label="Data Start" date={startDate} color="#00ACC1" icon="calendar_today" onPress={() => setEditingDate((current) => current === 'start' ? null : 'start')} />
                <View style={styles.columnGap} />
                <DateCard label="Data Sfârșit" date={endDate} color="#E53935" icon="event" onPress={() => setEditingDate((current) => current === 'end' ? null : 'end')} />
              </View>

              <GradientFieldCard color={isActive ? '#43A047' : '#757575'} icon={isActive ? 'check_circle' : 'cancel'}>
                <View style={styles.activeRow}>
                  <AppText variant="titleMedium" style={styles.activeLabel}>Abonament Activ</AppText>
                  <Switch value={isActive} onValueChange={setIsActive} trackColor={{ true: colors.primaryContainer }} thumbColor={isActive ? colors.primary : undefined} />
                </View>
              </GradientFieldCard>

              <View style={styles.actions}>
                <Pressable disabled={saveMutation.isPending} onPress={onClose} style={({ pressed }) => [styles.cancelButton, { borderColor: colors.outline, opacity: pressed ? 0.65 : 1 }]}>
                  <AppText variant="titleSmall" color={colors.primary}>Anulează</AppText>
                </Pressable>
                <Pressable disabled={saveMutation.isPending} onPress={() => { setValidationError(undefined); saveMutation.mutate(); }} style={({ pressed }) => [styles.saveButton, { backgroundColor: colors.primary, opacity: pressed ? 0.72 : 1 }]}>
                  {saveMutation.isPending ? <ActivityIndicator color={colors.onPrimary} /> : (
                    <AppText variant="titleSmall" color={colors.onPrimary} style={styles.bold}>
                      {membership ? 'Salvează Modificări' : 'Creează Abonament'}
                    </AppText>
                  )}
                </Pressable>
              </View>
            </BottomSheetScrollView>
          )}
    </BottomSheetModal>
    {editingDate ? <SingleDateDialog visible value={editingDate === 'start' ? startDate : endDate}
      minimumDate="2020-01-01" maximumDate="2030-12-31"
      title={editingDate === 'start' ? 'Data de început' : 'Data de sfârșit'}
      onCancel={() => setEditingDate(null)} onApply={changeDate} /> : null}
    </>
  );
}

function GradientFieldCard({ color, icon, children, style }: React.PropsWithChildren<{ color: string; icon: MaterialIconName; style?: object }>) {
  const { colors } = useAppTheme();
  return (
    <View style={[styles.gradientCard, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5) }, style]}>
      <LinearGradient colors={[colorWithAlpha(color, 0.05), colorWithAlpha(color, 0.02)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} />
      <View style={[styles.cardIcon, { backgroundColor: colorWithAlpha(color, 0.15) }]}>
        <MaterialIcon name={icon} size={20} color={color} />
      </View>
      <View style={styles.cardBody}>{children}</View>
    </View>
  );
}

function FormSelectCard({ label, value, color, icon, open, onToggle, children, compact, style }: React.PropsWithChildren<{ label: string; value: string; color: string; icon: MaterialIconName; open: boolean; onToggle: () => void; compact?: boolean; style?: object }>) {
  const { colors } = useAppTheme();
  return (
    <View style={[styles.selectWrapper, style]}>
      <Pressable onPress={onToggle} style={({ pressed }) => ({ opacity: pressed ? 0.72 : 1 })}>
        <GradientFieldCard color={color} icon={icon}>
          <View style={styles.selectValueRow}>
            <View style={styles.flex}>
              <AppText color={colors.onSurfaceVariant} style={styles.fieldLabel}>{label}</AppText>
              <AppText numberOfLines={1} variant={compact ? 'body' : 'bodyLarge'} style={styles.selectValue}>{value}</AppText>
            </View>
            <MaterialIcon name="arrow_drop_down" size={24} color={colors.onSurfaceVariant} style={open ? styles.rotate : undefined} />
          </View>
        </GradientFieldCard>
      </Pressable>
      {open ? <View style={[styles.selectMenu, { backgroundColor: colors.surfaceContainerLow, borderColor: colors.outlineVariant }]}>{children}</View> : null}
    </View>
  );
}

function SelectOption({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  const { colors } = useAppTheme();
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.option, { opacity: pressed ? 0.6 : 1 }]}>
      <AppText color={selected ? colors.primary : colors.onSurface} style={selected ? styles.bold : undefined}>{label}</AppText>
    </Pressable>
  );
}

function DateCard({ label, date, icon, color, onPress }: { label: string; date: CalendarDate; icon: MaterialIconName; color: string; onPress: () => void }) {
  const { colors } = useAppTheme();
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.dateCard, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5), opacity: pressed ? 0.72 : 1 }]}>
      <LinearGradient colors={[colorWithAlpha(color, 0.05), colorWithAlpha(color, 0.02)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} />
      <View style={styles.dateTop}>
        <View style={[styles.dateIcon, { backgroundColor: colorWithAlpha(color, 0.15) }]}><MaterialIcon name={icon} size={16} color={color} /></View>
        <MaterialIcon name="arrow_drop_down" size={24} color={color} />
      </View>
      <AppText variant="bodySmall" color={colors.onSurfaceVariant} style={styles.dateTitle}>{label}</AppText>
      <AppText variant="titleMedium" style={styles.bold}>{formatDate(date)}</AppText>
    </Pressable>
  );
}

function formatDate(date: CalendarDate): string { return formatCalendarDate(date); }

const styles = StyleSheet.create({
  sheet: { borderTopLeftRadius: 20, borderTopRightRadius: 20, overflow: 'hidden' },
  header: { flexDirection: 'row', alignItems: 'center', padding: 24 },
  headerIcon: { width: 48, height: 48, borderRadius: 12, alignItems: 'center', justifyContent: 'center' },
  headerTitle: { flex: 1, fontSize: 24, lineHeight: 32, fontWeight: '700', marginLeft: 16 },
  loading: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 },
  loadingText: { marginTop: 16 },
  centerText: { textAlign: 'center' },
  content: { padding: 24, paddingBottom: 32, gap: 16 },
  error: { borderRadius: 12, padding: 12 },
  gradientCard: { minHeight: 72, borderWidth: StyleSheet.hairlineWidth, borderRadius: 16, overflow: 'hidden', flexDirection: 'row', alignItems: 'center', padding: 16 },
  cardIcon: { width: 40, height: 40, borderRadius: 10, alignItems: 'center', justifyContent: 'center' },
  cardBody: { flex: 1, marginLeft: 12 },
  fieldLabel: { fontSize: 12, lineHeight: 16, fontWeight: '500' },
  fieldInput: { paddingVertical: 2, fontSize: 16, lineHeight: 24, fontWeight: '500' },
  selectWrapper: { zIndex: 2 },
  selectValueRow: { flexDirection: 'row', alignItems: 'center' },
  selectValue: { fontWeight: '500', marginTop: 2 },
  selectMenu: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 12, marginTop: 4, overflow: 'hidden' },
  option: { paddingHorizontal: 16, paddingVertical: 12 },
  rotate: { transform: [{ rotate: '180deg' }] },
  row: { flexDirection: 'row', alignItems: 'flex-start' },
  flex: { flex: 1 },
  columnGap: { width: 16 },
  dateCard: { flex: 1, minHeight: 132, borderWidth: StyleSheet.hairlineWidth, borderRadius: 16, overflow: 'hidden', padding: 16 },
  dateTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  dateIcon: { width: 32, height: 32, borderRadius: 8, alignItems: 'center', justifyContent: 'center' },
  dateTitle: { fontWeight: '500', marginTop: 12, marginBottom: 4 },
  picker: { borderRadius: 12, padding: 8 },
  pickerDone: { alignSelf: 'flex-end', padding: 10 },
  activeRow: { flexDirection: 'row', alignItems: 'center' },
  activeLabel: { flex: 1, fontWeight: '600' },
  actions: { flexDirection: 'row', gap: 12, marginTop: 16 },
  cancelButton: { flex: 1, minHeight: 52, borderWidth: 1, borderRadius: 24, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 10 },
  saveButton: { flex: 2, minHeight: 52, borderRadius: 24, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 10 },
  bold: { fontWeight: '700' },
});
