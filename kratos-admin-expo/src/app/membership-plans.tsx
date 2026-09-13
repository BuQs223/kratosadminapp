import { parseFlutterDouble, parseFlutterInt } from '@/utils/flutter-number';
import { LinearGradient } from 'expo-linear-gradient';
import { BottomSheetScrollView, BottomSheetTextInput } from '@gorhom/bottom-sheet';
import { Stack } from 'expo-router';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/app-text';
import { BottomSheetModal } from '@/components/bottom-sheet-modal';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { MaterialIcon } from '@/components/material-icon';
import {
  getMembershipPlans,
  getPlanFormGyms,
  saveMembershipPlan,
  setMembershipPlanActive,
  type MembershipPlanInput,
  type MembershipPlanStatus,
} from '@/repositories/membership-plans-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

type Plan = Record<string, unknown>;
type Tier = 'bronze' | 'silver' | 'gold';

const tierDetails: Record<Tier, { color: string; emoji: string; label: string }> = {
  bronze: { color: '#CD7F32', emoji: '🥉', label: 'Bronze' },
  silver: { color: '#C0C0C0', emoji: '🥈', label: 'Silver' },
  gold: { color: '#FFD700', emoji: '🥇', label: 'Gold' },
};

export default function MembershipPlansScreen() {
  const { colors } = useAppTheme();
  const queryClient = useQueryClient();
  const [status, setStatus] = React.useState<MembershipPlanStatus>('all');
  const [editing, setEditing] = React.useState<Plan | null>();
  const [message, setMessage] = React.useState<{ text: string; error?: boolean }>();
  const plansQuery = useQuery({ queryKey: ['membership-plans-admin', status], queryFn: () => getMembershipPlans(status) });
  const toggle = useMutation({
    mutationFn: ({ id, active }: { id: string; active: boolean }) => setMembershipPlanActive(id, active),
    onSuccess: async (_, variables) => {
      setMessage({ text: variables.active ? 'Plan activat' : 'Plan dezactivat' });
      await queryClient.invalidateQueries({ queryKey: ['membership-plans-admin'] });
    },
    onError: (error) => setMessage({ text: `Eroare: ${error instanceof Error ? error.message : String(error)}`, error: true }),
  });

  const save = useMutation({
    mutationFn: ({ input, id }: { input: MembershipPlanInput; id?: string }) => saveMembershipPlan(input, id),
    onSuccess: async (_, variables) => {
      setEditing(undefined);
      setMessage({ text: variables.id ? 'Plan actualizat cu succes' : 'Plan creat cu succes' });
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['membership-plans-admin'] }),
        queryClient.invalidateQueries({ queryKey: ['membership-plan-lookups'] }),
      ]);
    },
    onError: (error) => setMessage({ text: `Eroare: ${error instanceof Error ? error.message : String(error)}`, error: true }),
  });

  React.useEffect(() => {
    if (!message) return;
    const timer = setTimeout(() => setMessage(undefined), 3200);
    return () => clearTimeout(timer);
  }, [message]);

  const plans = plansQuery.data ?? [];
  return <View style={[styles.screen, { backgroundColor: colors.surfaceContainerLowest }]}>
    <Stack.Screen options={{ title: 'Planuri Abonamente' }} />
    <View style={[styles.tabs, { backgroundColor: colors.surfaceContainerHighest }]}>{([['all', 'Toate'], ['active', 'Active'], ['inactive', 'Inactive']] as const).map(([value, label]) => <Pressable key={value} onPress={() => setStatus(value)} style={[styles.tab, status === value && { backgroundColor: colors.primary }]}><AppText color={status === value ? colors.onPrimary : colors.onSurfaceVariant} style={status === value ? styles.tabSelected : styles.tabText}>{label}</AppText></Pressable>)}</View>
    {plansQuery.isLoading ? <View style={styles.center}><ActivityIndicator size="large" color={colors.primary} /></View> : <ScrollView contentContainerStyle={plans.length ? styles.content : styles.emptyContent} contentInsetAdjustmentBehavior="automatic" refreshControl={<ManualRefreshControl onRefresh={() => plansQuery.refetch()} tintColor={colors.primary} colors={[colors.primary]} />}>
      {plansQuery.error ? <AppText selectable color={colors.error} style={styles.error}>Eroare: {plansQuery.error instanceof Error ? plansQuery.error.message : String(plansQuery.error)}</AppText> : null}
      {!plans.length ? <View style={styles.empty}><MaterialIcon name="card_membership_outlined" size={80} color={colorWithAlpha(colors.primary, 0.3)} /><AppText variant="titleLarge" style={styles.emptyTitle}>Niciun plan</AppText><AppText color={colors.onSurfaceVariant} style={styles.emptySubtitle}>Adaugă primul plan de abonament</AppText></View> : plans.map((plan) => <PlanCard key={String(plan.id)} plan={plan} toggling={toggle.isPending && toggle.variables?.id === String(plan.id)} onEdit={() => setEditing(plan)} onToggle={(active) => toggle.mutate({ id: String(plan.id), active })} />)}
    </ScrollView>}
    <Pressable accessibilityLabel="Plan Nou" onPress={() => setEditing(null)} style={[styles.fab, { backgroundColor: colors.primary }]}><MaterialIcon name="add" size={22} color={colors.onPrimary} /><AppText color={colors.onPrimary} style={styles.fabText}>Plan Nou</AppText></Pressable>
    {message ? <View style={[styles.snackbar, { backgroundColor: message.error ? colors.error : '#2E7D32' }]}><AppText color="#FFFFFF" style={styles.snackbarText}>{message.text}</AppText></View> : null}
    {editing !== undefined ? <PlanForm visible plan={editing ?? undefined} saving={save.isPending} serverError={save.error} onClose={() => { if (!save.isPending) setEditing(undefined); }} onSave={(input) => save.mutate({ input, id: editing ? String(editing.id) : undefined })} /> : null}
  </View>;
}

function PlanCard({ plan, toggling, onEdit, onToggle }: { plan: Plan; toggling: boolean; onEdit: () => void; onToggle: (active: boolean) => void }) {
  const { colors } = useAppTheme();
  const tier = String(plan.tier ?? 'silver');
  const details = tierDetails[tier.toLowerCase() as Tier] ?? { color: '#1E88E5', emoji: '💳', label: tier };
  const active = Boolean(plan.is_active);
  const gym = record(plan.gyms);
  return <View style={[styles.card, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5) }]}><LinearGradient colors={[colorWithAlpha(details.color, 0.08), colorWithAlpha(details.color, 0.02)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} /><View style={styles.cardHeader}><Pressable onPress={onEdit} style={styles.cardIdentity}><View style={[styles.tierIcon, { backgroundColor: colorWithAlpha(details.color, 0.15) }]}><AppText style={styles.tierEmoji}>{details.emoji}</AppText></View><View style={styles.cardTitleCopy}><AppText variant="titleMedium" style={styles.bold}>{String(plan.name ?? '')}</AppText><View style={styles.badges}><Badge label={tier.toUpperCase()} color={details.color} /><Badge label={active ? 'ACTIV' : 'INACTIV'} color={active ? '#4CAF50' : '#F44336'} /></View></View></Pressable>{toggling ? <ActivityIndicator color={colors.primary} style={styles.switchPlaceholder} /> : <Switch value={active} onValueChange={onToggle} trackColor={{ false: colors.surfaceContainerHighest, true: colorWithAlpha(colors.primary, 0.5) }} thumbColor={active ? colors.primary : colors.outline} />}</View><Pressable onPress={onEdit} style={styles.details}><Meta icon="schedule" text={duration(plan)} /><Meta icon="payments" text={currency(Number(plan.monthly_price_cents ?? 0))} />{gym?.name ? <Meta icon="fitness_center" text={String(gym.name)} /> : null}{plan.is_good_morning === true ? <SpecialBadge emoji="☀️" label="Good Morning" color="#FB8C00" /> : null}{plan.is_family_plan === true ? <SpecialBadge emoji="👨‍👩‍👧‍👦" label="Familie" color="#8E24AA" /> : null}</Pressable></View>;
}

function Badge({ label, color }: { label: string; color: string }) { return <View style={[styles.badge, { backgroundColor: colorWithAlpha(color, 0.15) }]}><AppText color={color} style={styles.badgeText}>{label}</AppText></View>; }
function SpecialBadge({ emoji, label, color }: { emoji: string; label: string; color: string }) { return <View style={[styles.specialBadge, { backgroundColor: colorWithAlpha(color, 0.15) }]}><AppText style={styles.specialEmoji}>{emoji}</AppText><AppText color={color} style={styles.specialText}>{label}</AppText></View>; }
function Meta({ icon, text }: { icon: 'schedule' | 'payments' | 'fitness_center'; text: string }) { const { colors } = useAppTheme(); return <View style={styles.meta}><MaterialIcon name={icon} size={16} color={colors.onSurfaceVariant} /><AppText style={styles.metaText}>{text}</AppText></View>; }

function PlanForm({ visible, plan, saving, serverError, onClose, onSave }: { visible: boolean; plan?: Plan; saving: boolean; serverError: Error | null; onClose: () => void; onSave: (input: MembershipPlanInput) => void }) {
  const { colors } = useAppTheme();
  const insets = useSafeAreaInsets();
  const gymsQuery = useQuery({ queryKey: ['plan-form-gyms'], queryFn: getPlanFormGyms });
  const gyms = gymsQuery.data ?? [];
  const [name, setName] = React.useState(String(plan?.name ?? ''));
  const [price, setPrice] = React.useState(plan ? String(Number(plan.monthly_price_cents ?? 0) / 100) : '');
  const [months, setMonths] = React.useState(String(Number(plan?.duration_months ?? 0)));
  const [days, setDays] = React.useState(String(Number(plan?.duration_days ?? 0)));
  const [tier, setTier] = React.useState<string>(() => String(plan?.tier ?? 'silver'));
  const [gymId, setGymId] = React.useState<string | null>(plan?.gym_id ? String(plan.gym_id) : null);
  const [active, setActive] = React.useState(plan ? Boolean(plan.is_active) : true);
  const [family, setFamily] = React.useState(Boolean(plan?.is_family_plan));
  const [goodMorning, setGoodMorning] = React.useState(Boolean(plan?.is_good_morning));
  const [menu, setMenu] = React.useState<'tier' | 'gym'>();
  const [validation, setValidation] = React.useState<string>();

  const submit = () => {
    const parsedPrice = parseFlutterDouble(price);
    const parsedMonths = parseFlutterInt(months);
    const parsedDays = parseFlutterInt(days);
    if (!name) { setValidation('Introduceți numele planului'); return; }
    if (parsedPrice === null || !Number.isFinite(parsedPrice)) { setValidation('Preț invalid'); return; }
    if (parsedMonths === null || parsedDays === null) { setValidation('Durata trebuie să conțină numere întregi'); return; }
    setValidation(undefined);
    onSave({ name, tier, gymId, monthlyPriceCents: Math.trunc(parsedPrice * 100), isActive: active, isFamilyPlan: family, isGoodMorning: goodMorning, durationMonths: parsedMonths, durationDays: parsedDays });
  };

  return <BottomSheetModal visible={visible} onClose={onClose} keyboardAvoiding disableDismiss={saving} snapPoints={['50%', '90%']} initialIndex={1} scrollable sheetStyle={[styles.formSheet, { backgroundColor: colors.surface, paddingBottom: insets.bottom }]}><View style={[styles.handle, { backgroundColor: colorWithAlpha(colors.onSurfaceVariant, 0.4) }]} /><View style={styles.formHeader}><AppText variant="titleLarge" style={styles.bold}>{plan ? 'Editează Plan' : 'Plan Nou'}</AppText><Pressable hitSlop={10} onPress={onClose}><MaterialIcon name="close" size={24} color={colors.onSurfaceVariant} /></Pressable></View><View style={[styles.divider, { backgroundColor: colors.outlineVariant }]} /><BottomSheetScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.formContent}>
    <Field label="Nume Plan" icon="title" value={name} onChangeText={setName} />
    <SelectField label="Nivel" icon="star" value={tier in tierDetails ? `${tierDetails[tier as Tier].emoji} ${tierDetails[tier as Tier].label}` : tier} open={menu === 'tier'} onPress={() => setMenu(menu === 'tier' ? undefined : 'tier')}>{(Object.keys(tierDetails) as Tier[]).map((item) => <SelectOption key={item} label={`${tierDetails[item].emoji} ${tierDetails[item].label}`} selected={tier === item} onPress={() => { setTier(item); setMenu(undefined); }} />)}</SelectField>
    <Field label="Preț (RON)" icon="payments" value={price} onChangeText={setPrice} keyboardType="decimal-pad" />
    <View style={styles.durationRow}><View style={styles.durationField}><Field label="Luni" icon="calendar_month" value={months} onChangeText={setMonths} keyboardType="number-pad" /></View><View style={styles.durationField}><Field label="Zile" icon="calendar_today" value={days} onChangeText={setDays} keyboardType="number-pad" /></View></View>
    <SelectField label="Sală (Opțional)" icon="fitness_center" value={gymId ? gyms.find((gym) => gym.id === gymId)?.name ?? 'Necunoscut' : 'Toate sălile'} open={menu === 'gym'} onPress={() => setMenu(menu === 'gym' ? undefined : 'gym')}><SelectOption label="Toate sălile" selected={!gymId} onPress={() => { setGymId(null); setMenu(undefined); }} />{gyms.map((gym) => <SelectOption key={gym.id} label={gym.name} selected={gymId === gym.id} onPress={() => { setGymId(gym.id); setMenu(undefined); }} />)}</SelectField>
    <View style={styles.switches}><SwitchRow title="Plan Activ" subtitle="Vizibil pentru membri noi" value={active} onValueChange={setActive} /><SwitchRow title="Plan Familie" subtitle="Permite multiple persoane pe același abonament" value={family} onValueChange={setFamily} /><SwitchRow title="Good Morning" subtitle="Acces dimineața (6:00 - 12:00)" value={goodMorning} onValueChange={setGoodMorning} /></View>
    {validation ? <AppText color={colors.error} style={styles.formError}>{validation}</AppText> : null}{serverError ? <AppText selectable color={colors.error} style={styles.formError}>Eroare: {serverError.message}</AppText> : null}
  </BottomSheetScrollView><View style={[styles.saveArea, { borderTopColor: colors.outlineVariant }]}><Pressable disabled={saving} onPress={submit} style={[styles.saveButton, { backgroundColor: colors.primary, opacity: saving ? 0.55 : 1 }]}>{saving ? <ActivityIndicator color={colors.onPrimary} /> : <AppText color={colors.onPrimary} style={styles.bold}>{plan ? 'Salvează Modificări' : 'Creează Plan'}</AppText>}</Pressable></View></BottomSheetModal>;
}

type IconName = 'title' | 'payments' | 'calendar_month' | 'calendar_today';
function Field({ label, icon, value, onChangeText, keyboardType = 'default' }: { label: string; icon: IconName; value: string; onChangeText: (value: string) => void; keyboardType?: 'default' | 'decimal-pad' | 'number-pad' }) { const { colors } = useAppTheme(); return <View style={[styles.field, { borderColor: colors.outline }]}><MaterialIcon name={icon} size={22} color={colors.onSurfaceVariant} /><View style={styles.fieldCopy}><AppText variant="bodySmall" color={colors.onSurfaceVariant}>{label}</AppText><BottomSheetTextInput value={value} onChangeText={onChangeText} keyboardType={keyboardType} placeholderTextColor={colors.onSurfaceVariant} selectionColor={colors.primary} style={[styles.input, { color: colors.onSurface }]} /></View></View>; }
function SelectField({ label, icon, value, open, onPress, children }: React.PropsWithChildren<{ label: string; icon: 'star' | 'fitness_center'; value: string; open: boolean; onPress: () => void }>) { const { colors } = useAppTheme(); return <View><Pressable onPress={onPress} style={[styles.field, { borderColor: colors.outline }]}><MaterialIcon name={icon} size={22} color={colors.onSurfaceVariant} /><View style={styles.fieldCopy}><AppText variant="bodySmall" color={colors.onSurfaceVariant}>{label}</AppText><AppText style={styles.selectValue}>{value}</AppText></View><MaterialIcon name="arrow_drop_down" size={24} color={colors.onSurfaceVariant} style={open ? styles.rotated : undefined} /></Pressable>{open ? <View style={[styles.selectMenu, { borderColor: colors.outlineVariant, backgroundColor: colors.surfaceContainerLow }]}>{children}</View> : null}</View>; }
function SelectOption({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) { const { colors } = useAppTheme(); return <Pressable onPress={onPress} style={[styles.selectOption, selected && { backgroundColor: colors.secondaryContainer }]}><AppText style={styles.selectOptionText}>{label}</AppText>{selected ? <MaterialIcon name="check" size={20} color={colors.primary} /> : null}</Pressable>; }
function SwitchRow({ title, subtitle, value, onValueChange }: { title: string; subtitle: string; value: boolean; onValueChange: (value: boolean) => void }) { const { colors } = useAppTheme(); return <View style={styles.switchRow}><View style={styles.switchCopy}><AppText>{title}</AppText><AppText variant="bodySmall" color={colors.onSurfaceVariant}>{subtitle}</AppText></View><Switch value={value} onValueChange={onValueChange} trackColor={{ false: colors.surfaceContainerHighest, true: colorWithAlpha(colors.primary, 0.5) }} thumbColor={value ? colors.primary : colors.outline} /></View>; }

function record(value: unknown): Record<string, unknown> | undefined { return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : undefined; }

function duration(plan: Plan) { const months = Number(plan.duration_months ?? 0); const days = Number(plan.duration_days ?? 0); if (months > 0) return `${months} ${months === 1 ? 'lună' : 'luni'}`; if (days > 0) return `${days} ${days === 1 ? 'zi' : 'zile'}`; return 'Nedefinit'; }
function currency(cents: number) { return `RON ${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`; }

const styles = StyleSheet.create({
  screen: { flex: 1 }, center: { flex: 1, alignItems: 'center', justifyContent: 'center' }, tabs: { flexDirection: 'row', margin: 16, padding: 4, borderRadius: 12 }, tab: { flex: 1, minHeight: 44, alignItems: 'center', justifyContent: 'center', borderRadius: 8 }, tabText: { fontWeight: '500' }, tabSelected: { fontWeight: '700' }, content: { paddingHorizontal: 16, paddingBottom: 100 }, emptyContent: { flexGrow: 1, paddingBottom: 100 }, error: { marginBottom: 12 }, empty: { flex: 1, alignItems: 'center', justifyContent: 'center' }, emptyTitle: { fontWeight: '600', marginTop: 24 }, emptySubtitle: { marginTop: 8 },
  card: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 16, overflow: 'hidden', padding: 16, marginBottom: 12 }, cardHeader: { flexDirection: 'row', alignItems: 'center' }, cardIdentity: { flex: 1, flexDirection: 'row', alignItems: 'center' }, tierIcon: { width: 48, height: 48, borderRadius: 12, alignItems: 'center', justifyContent: 'center' }, tierEmoji: { fontSize: 24, lineHeight: 32 }, cardTitleCopy: { flex: 1, marginLeft: 12 }, bold: { fontWeight: '700' }, badges: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 4 }, badge: { borderRadius: 6, paddingHorizontal: 8, paddingVertical: 2 }, badgeText: { fontSize: 10, lineHeight: 14, fontWeight: '700' }, switchPlaceholder: { width: 51 }, details: { flexDirection: 'row', flexWrap: 'wrap', gap: 12, marginTop: 16 }, meta: { flexDirection: 'row', alignItems: 'center' }, metaText: { fontWeight: '500', marginLeft: 6 }, specialBadge: { flexDirection: 'row', alignItems: 'center', borderRadius: 8, paddingHorizontal: 8, paddingVertical: 4 }, specialEmoji: { fontSize: 12, lineHeight: 16 }, specialText: { fontSize: 11, lineHeight: 16, fontWeight: '700', marginLeft: 4 },
  fab: { position: 'absolute', right: 20, bottom: 20, height: 56, borderRadius: 18, paddingHorizontal: 20, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', shadowColor: '#000000', shadowOpacity: 0.22, shadowRadius: 4, shadowOffset: { width: 0, height: 3 }, elevation: 4 }, fabText: { fontWeight: '700', marginLeft: 8 }, snackbar: { position: 'absolute', left: 16, right: 16, bottom: 88, minHeight: 48, borderRadius: 8, paddingHorizontal: 16, justifyContent: 'center' }, snackbarText: { fontWeight: '500' },
  formSheet: { borderTopLeftRadius: 20, borderTopRightRadius: 20, overflow: 'hidden' }, handle: { width: 40, height: 4, borderRadius: 2, alignSelf: 'center', marginTop: 12, marginBottom: 8 }, formHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', padding: 16 }, divider: { height: StyleSheet.hairlineWidth }, formContent: { padding: 16, paddingBottom: 24, gap: 16 }, field: { minHeight: 58, borderWidth: 1, borderRadius: 4, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12 }, fieldCopy: { flex: 1, marginLeft: 12, paddingTop: 5 }, input: { minHeight: 32, paddingVertical: 2, fontSize: 16 }, selectValue: { minHeight: 32, paddingTop: 4 }, rotated: { transform: [{ rotate: '180deg' }] }, selectMenu: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 8, marginTop: 4, overflow: 'hidden' }, selectOption: { minHeight: 48, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16 }, selectOptionText: { flex: 1 }, durationRow: { flexDirection: 'row', gap: 12 }, durationField: { flex: 1 }, switches: { marginTop: 8 }, switchRow: { minHeight: 64, flexDirection: 'row', alignItems: 'center' }, switchCopy: { flex: 1, paddingRight: 12 }, formError: { marginTop: 4 }, saveArea: { borderTopWidth: StyleSheet.hairlineWidth, padding: 16 }, saveButton: { minHeight: 48, borderRadius: 24, alignItems: 'center', justifyContent: 'center' },
});
