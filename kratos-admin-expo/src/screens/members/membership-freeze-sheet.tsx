import { BottomSheetScrollView } from '@gorhom/bottom-sheet';
import { useMutation, useQuery } from '@tanstack/react-query';
import React from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/app-text';
import { BottomSheetModal } from '@/components/bottom-sheet-modal';
import { SingleDateDialog } from '@/components/calendar-dialog';
import { MaterialIcon } from '@/components/material-icon';
import {
  applyFreezeAction, canFreezeMembership, getFreezeData, isThreeMonthMembership,
  preservedDays, scheduleMaximum, type FreezeAction, type FreezeMode,
} from '@/repositories/membership-freeze-repository';
import { useAppTheme } from '@/theme/theme';
import { addCalendarDays, formatCalendarDate, todayCalendarDate } from '@/utils/calendar-date';
import { parseFlutterDate } from '@/utils/flutter-date';

export function MembershipFreezeSheet({ memberId, onClose, onSaved }: {
  memberId: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { colors } = useAppTheme();
  const [selectedId, setSelectedId] = React.useState<string>();
  const [mode, setMode] = React.useState<FreezeMode>('manual');
  const [scheduled, setScheduled] = React.useState(false);
  const [start, setStart] = React.useState(() => addCalendarDays(todayCalendarDate(), 1));
  const [calendarOpen, setCalendarOpen] = React.useState(false);
  const query = useQuery({ queryKey: ['membership-freeze', memberId], queryFn: () => getFreezeData(memberId), networkMode: 'always' });
  const mutation = useMutation({
    networkMode: 'always',
    mutationFn: (action: FreezeAction) => applyFreezeAction(memberId, action),
    onSuccess: () => { onSaved(); onClose(); },
  });
  const membership = query.data?.memberships.find((item) => item.id === selectedId)
    ?? query.data?.memberships.find((item) => item.is_frozen || canFreezeMembership(item))
    ?? query.data?.memberships[0];
  const pending = query.data?.schedules.find((item) => item.membership_id === membership?.id);
  const threeMonth = membership ? isThreeMonthMembership(membership) : false;
  const tomorrow = addCalendarDays(todayCalendarDate(), 1);
  const maximum = membership ? scheduleMaximum(membership) : tomorrow;
  const canSchedule = maximum >= tomorrow;
  const busy = mutation.isPending;

  function submit() {
    if (!membership || busy) return;
    if (pending) {
      Alert.alert('Anulați înghețarea programată?', 'Abonamentul va continua fără această înghețare.', [
        { text: 'Înapoi', style: 'cancel' },
        { text: 'Anulează programarea', style: 'destructive', onPress: () => mutation.mutate({ kind: 'cancel', membershipId: membership.id, scheduleId: pending.id }) },
      ]);
    } else if (membership.is_frozen) {
      mutation.mutate({ kind: 'resume', membershipId: membership.id });
    } else if (scheduled) {
      mutation.mutate({ kind: 'schedule', membershipId: membership.id, start, durationDays: mode === 'auto_14_days' ? 14 : 5 });
    } else {
      mutation.mutate({ kind: 'freeze', membershipId: membership.id, mode });
    }
  }

  const disabled = busy || !membership || Boolean(query.error)
    || (!pending && !membership.is_frozen && (!canFreezeMembership(membership) || (scheduled && (!canSchedule || start < tomorrow || start > maximum))));
  const actionLabel = pending ? 'Anulează programarea' : membership?.is_frozen ? 'Dezgheață abonamentul' : scheduled ? 'Programează înghețarea' : 'Îngheață abonamentul';

  return <>
    <BottomSheetModal visible onClose={onClose} disableDismiss={busy} scrollable sheetStyle={{ backgroundColor: colors.surface }}>
      <BottomSheetScrollView contentContainerStyle={styles.content}>
        <View style={styles.header}>
          <MaterialIcon name="ac_unit" size={28} color={colors.primary} />
          <AppText variant="titleLarge" style={styles.title}>Înghețare abonament</AppText>
          <Pressable accessibilityRole="button" accessibilityLabel="Închide" disabled={busy} onPress={onClose} style={styles.close}><MaterialIcon name="close" size={24} color={colors.onSurfaceVariant} /></Pressable>
        </View>
        {query.isLoading ? <ActivityIndicator color={colors.primary} /> : null}
        {query.error ? <View style={styles.section}>
          <AppText color={colors.error}>Abonamentele nu au putut fi încărcate: {errorMessage(query.error)}</AppText>
          <Option title="Încearcă din nou" onPress={() => { void query.refetch(); }} />
        </View> : null}
        {query.data?.memberships.length === 0 ? <AppText>Acest client nu are abonamente proprii. Abonamentele de familie se gestionează din profilul titularului.</AppText> : null}
        {query.data && membership ? <>
          <View style={styles.section}>
            <AppText variant="titleMedium">Alege abonamentul</AppText>
            {query.data.memberships.map((item) => <Option key={item.id}
              title={item.plan_name ?? 'Abonament'}
              subtitle={`${formatCalendarDate(scheduleMaximum(item))} • ${item.is_frozen ? 'Înghețat' : canFreezeMembership(item) ? 'Activ' : 'Inactiv'}`}
              selected={membership.id === item.id} disabled={busy}
              onPress={() => { setSelectedId(item.id); setMode('manual'); setScheduled(false); setStart(tomorrow); mutation.reset(); }} />)}
          </View>
          {pending ? <View style={styles.section}>
            <AppText variant="titleMedium">Înghețare programată</AppText>
            <AppText>{formatCalendarDate(pending.scheduled_start_date)} • {pending.duration_days} zile</AppText>
            <AppText color={colors.onSurfaceVariant}>Anulează programarea înainte de a alege o altă înghețare.</AppText>
          </View> : membership.is_frozen ? <View style={styles.section}>
            <AppText variant="titleMedium">{preservedDays(membership.days_left_when_frozen)} zile păstrate</AppText>
            <AppText>{membership.auto_unfreeze_at ? `Dezghețare automată: ${parseFlutterDate(membership.auto_unfreeze_at).toLocaleString('ro-RO')}` : 'Abonamentul este înghețat manual.'}</AppText>
            <AppText color={colors.onSurfaceVariant}>La dezghețare, data de expirare devine data de azi plus zilele păstrate. Zero zile înseamnă ultima zi valabilă.</AppText>
          </View> : canFreezeMembership(membership) ? <>
            <View style={styles.section}>
              <AppText variant="titleMedium">Când începe?</AppText>
              <View style={styles.row}>
                <View style={styles.flex}><Option title="Acum" selected={!scheduled} disabled={busy} onPress={() => setScheduled(false)} /></View>
                <View style={styles.flex}><Option title="La o dată viitoare" selected={scheduled} disabled={busy || !canSchedule} onPress={() => { setScheduled(true); if (mode === 'manual') setMode('auto_5_days'); }} /></View>
              </View>
              {!canSchedule ? <AppText color={colors.onSurfaceVariant}>Programarea necesită cel puțin o zi viitoare înainte de expirare.</AppText> : null}
              {scheduled ? <Option title={formatCalendarDate(start)} subtitle="Înghețarea pornește la 00:00 în ziua aleasă." disabled={busy} onPress={() => setCalendarOpen(true)} /> : null}
            </View>
            <View style={styles.section}>
              <AppText variant="titleMedium">Durata înghețării</AppText>
              {!scheduled ? <Option title="Manuală" subtitle="Până la dezghețarea din profil." selected={mode === 'manual'} disabled={busy} onPress={() => setMode('manual')} /> : null}
              <Option title="5 zile" subtitle="Dezghețare automată după 5 zile." selected={mode === 'auto_5_days'} disabled={busy} onPress={() => setMode('auto_5_days')} />
              {threeMonth ? <Option title="14 zile" subtitle="Pentru abonamentele de 3 luni." selected={mode === 'auto_14_days'} disabled={busy} onPress={() => setMode('auto_14_days')} /> : null}
              <AppText color={colors.onSurfaceVariant}>Zilele rămase se păstrează la momentul înghețării și se restaurează la dezghețare.</AppText>
            </View>
          </> : <AppText color={colors.onSurfaceVariant}>Acest abonament este inactiv sau anulat și nu poate fi înghețat.</AppText>}
          {mutation.error ? <AppText accessibilityRole="alert" color={colors.error}>{errorMessage(mutation.error)}</AppText> : null}
          <Pressable accessibilityRole="button" accessibilityState={{ disabled }} disabled={disabled} onPress={submit} style={[styles.apply, { backgroundColor: colors.primary, opacity: disabled ? 0.45 : 1 }]}>
            {busy ? <ActivityIndicator color={colors.onPrimary} /> : <AppText color={colors.onPrimary} style={styles.bold}>{actionLabel}</AppText>}
          </Pressable>
          <AppText variant="bodySmall" color={colors.onSurfaceVariant}>Modificările se sincronizează când există conexiune. Programările și dezghețarea automată sunt procesate de server după sincronizare.</AppText>
        </> : null}
      </BottomSheetScrollView>
    </BottomSheetModal>
    {membership && calendarOpen ? <SingleDateDialog visible value={start} minimumDate={tomorrow} maximumDate={maximum} title="Data înghețării" onCancel={() => setCalendarOpen(false)} onApply={(date) => { setStart(date); setCalendarOpen(false); }} /> : null}
  </>;
}

function errorMessage(error: unknown) { return error instanceof Error ? error.message : String(error); }

function Option({ title, subtitle, selected, disabled, onPress }: { title: string; subtitle?: string; selected?: boolean; disabled?: boolean; onPress: () => void }) {
  const { colors } = useAppTheme();
  return <Pressable accessibilityRole="button" accessibilityState={{ selected, disabled }} disabled={disabled} onPress={onPress}
    style={({ pressed }) => [styles.option, { backgroundColor: selected ? colors.primaryContainer : colors.surfaceContainerLow, borderColor: selected ? colors.primary : colors.outlineVariant, opacity: disabled || pressed ? 0.5 : 1 }]}>
    <AppText style={styles.bold}>{title}</AppText>
    {subtitle ? <AppText variant="bodySmall" color={colors.onSurfaceVariant}>{subtitle}</AppText> : null}
  </Pressable>;
}

const styles = StyleSheet.create({
  content: { padding: 24, paddingBottom: 40, gap: 20 },
  header: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  title: { flex: 1 }, close: { padding: 10 },
  section: { gap: 12 }, row: { flexDirection: 'row', gap: 12 }, flex: { flex: 1 },
  option: { padding: 16, gap: 6, borderRadius: 12, borderWidth: 1, minHeight: 52 },
  apply: { minHeight: 52, borderRadius: 26, alignItems: 'center', justifyContent: 'center', padding: 12 },
  bold: { fontWeight: '700' },
});
