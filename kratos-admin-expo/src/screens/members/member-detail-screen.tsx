import * as Clipboard from 'expo-clipboard';
import { BottomSheetTextInput } from '@gorhom/bottom-sheet';
import { LinearGradient } from 'expo-linear-gradient';
import { router } from 'expo-router';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import React from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  StyleSheet,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/app-text';
import { BottomSheetModal } from '@/components/bottom-sheet-modal';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { MaterialIcon } from '@/components/material-icon';
import type { MaterialIconName } from '@/constants/material-icons.generated';
import type { CheckIn } from '@/models/check-in';
import {
  membershipDaysUntilExpiry,
  membershipIsExpired,
  membershipStatusText,
  type Membership,
} from '@/models/membership';
import type { Profile } from '@/models/profile';
import {
  deleteMembership,
  getMemberCheckIns,
  getMemberMemberships,
  getMemberProfile,
  updateMemberName,
} from '@/repositories/members-repository';
import { MembershipFormSheet } from '@/screens/members/membership-form-sheet';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';
import { formatCalendarDate, type CalendarDate } from '@/utils/calendar-date';

interface MemberDetailData {
  profile: Profile;
  memberships: Membership[];
  checkIns: CheckIn[];
}

export function MemberDetailScreen({ memberId }: { memberId: string }) {
  const { colors } = useAppTheme();
  const insets = useSafeAreaInsets();
  const queryClient = useQueryClient();
  const [tab, setTab] = React.useState<'memberships' | 'checkIns'>('memberships');
  const [editNameVisible, setEditNameVisible] = React.useState(false);
  const [formVisible, setFormVisible] = React.useState(false);
  const [editingMembership, setEditingMembership] = React.useState<Membership | null>(null);
  const [notice, setNotice] = React.useState<string>();

  React.useEffect(() => {
    if (!notice) return;
    const timeout = setTimeout(() => setNotice(undefined), 2500);
    return () => clearTimeout(timeout);
  }, [notice]);

  const detailQuery = useQuery({
    queryKey: ['member-detail', memberId],
    queryFn: async (): Promise<MemberDetailData> => {
      const profile = await getMemberProfile(memberId);
      const [memberships, checkIns] = await Promise.all([
        getMemberMemberships(memberId),
        getMemberCheckIns(profile),
      ]);
      return { profile, memberships, checkIns };
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteMembership,
    onSuccess: async () => {
      setNotice('Abonamentul a fost șters');
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['member-detail', memberId] }),
        queryClient.invalidateQueries({ queryKey: ['members'] }),
        queryClient.invalidateQueries({ queryKey: ['dashboard-stats'] }),
      ]);
    },
    onError: (error) => setNotice(`Eroare: ${error instanceof Error ? error.message : String(error)}`),
  });

  if (detailQuery.isLoading) {
    return <View style={[styles.center, { backgroundColor: colors.surfaceContainerLowest }]}><ActivityIndicator size="large" color={colors.primary} /></View>;
  }

  if (!detailQuery.data) {
    return (
      <View style={[styles.center, styles.errorPage, { backgroundColor: colors.surfaceContainerLowest }]}>
        <MaterialIcon name="error_outline" size={56} color={colors.error} />
        <AppText selectable color={colors.error} style={styles.errorText}>
          {detailQuery.error instanceof Error ? detailQuery.error.message : 'Membrul nu a putut fi încărcat.'}
        </AppText>
      </View>
    );
  }

  const { profile, memberships, checkIns } = detailQuery.data;
  const activeMemberships = memberships.filter(
    (membership) => !membership.canceledAt && !membershipIsExpired(membership) && !membership.isFrozen,
  );

  const openNewMembership = () => {
    setEditingMembership(null);
    setFormVisible(true);
  };

  const confirmDelete = (membership: Membership) => {
    Alert.alert(
      'Șterge Abonament',
      `Sigur vrei să ștergi abonamentul "${membership.plan?.name ?? 'Unknown'}"?\n\nAceasta va șterge și înregistrarea din registrul de venituri.`,
      [
        { text: 'Anulează', style: 'cancel' },
        { text: 'Șterge', style: 'destructive', onPress: () => deleteMutation.mutate(membership.id) },
      ],
    );
  };

  return (
    <View style={[styles.screen, { backgroundColor: colors.surfaceContainerLowest }]}>
      <LinearGradient
        colors={[colors.surface, colors.surfaceContainer]}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={[styles.memberHeader, { paddingTop: insets.top }]}>
        <View style={styles.backRow}>
          <Pressable accessibilityRole="button" accessibilityLabel="Înapoi" onPress={() => router.back()} hitSlop={10} style={({ pressed }) => ({ opacity: pressed ? 0.5 : 1, padding: 8 })}>
            <MaterialIcon name="arrow_back" size={24} color={colors.onSurface} />
          </Pressable>
        </View>
        <View style={styles.memberIdentity}>
          <View style={[styles.largeAvatar, { backgroundColor: colors.primary }]}>
            <AppText variant="headlineLarge" color={colors.onPrimary} style={styles.bold}>
              {profile.fullName ? Array.from(profile.fullName)[0]?.toUpperCase() : '?'}
            </AppText>
          </View>
          <View style={styles.identityCopy}>
            <View style={styles.nameRow}>
              <AppText numberOfLines={2} style={styles.memberName}>{profile.fullName}</AppText>
              <Pressable accessibilityRole="button" accessibilityLabel="Editează nume" onPress={() => setEditNameVisible(true)} hitSlop={8} style={({ pressed }) => ({ opacity: pressed ? 0.5 : 1, padding: 8 })}>
                <MaterialIcon name="edit_outlined" size={24} color={colors.onSurfaceVariant} />
              </Pressable>
            </View>
            <View style={[styles.activeBadge, { backgroundColor: colorWithAlpha(activeMemberships.length ? '#4CAF50' : '#FF9800', 0.2) }]}>
              <AppText color={activeMemberships.length ? '#1B5E20' : '#E65100'} style={styles.activeText}>
                {activeMemberships.length
                  ? `✅ ${activeMemberships.length} Activ${activeMemberships.length > 1 ? 'e' : ''}`
                  : '⚠️ Fără abonament'}
              </AppText>
            </View>
          </View>
        </View>
      </LinearGradient>

      <View style={styles.summaryArea}>
        <View style={styles.summaryRow}>
          <InfoCard label="Membru din" value={formatDate(profile.createdAt)} icon="calendar_today" color="#8E24AA" />
          <View style={styles.summaryGap} />
          <InfoCard
            label="Client ID"
            value={profile.id.slice(0, 8)}
            icon="fingerprint"
            color="#1E88E5"
            monospace
            onPress={() => {
              void Clipboard.setStringAsync(profile.id);
              setNotice('ID copiat');
            }}
          />
        </View>
        <NavigationCard icon="history" label="Vezi istoricul complet al membrului" onPress={() => router.push({ pathname: '/member/[memberId]/history', params: { memberId } })} />
        <NavigationCard icon="payments_outlined" label="Vezi istoricul incasarilor" onPress={() => router.push({ pathname: '/member/[memberId]/revenue', params: { memberId } })} />
        <View style={[styles.tabs, { backgroundColor: colors.surfaceContainer }]}>
          <TabButton selected={tab === 'memberships'} icon="card_membership" label={`Abonamente (${memberships.length})`} onPress={() => setTab('memberships')} />
          <TabButton selected={tab === 'checkIns'} icon="check_circle_outline" label={`Check-ins (${checkIns.length})`} onPress={() => setTab('checkIns')} />
        </View>
      </View>

      <View style={styles.tabContent}>
        {tab === 'memberships' ? (
          <MembershipsTab
            memberships={memberships}
            onRefresh={() => detailQuery.refetch()}
            onAdd={openNewMembership}
            onEdit={(membership) => { setEditingMembership(membership); setFormVisible(true); }}
            onDelete={confirmDelete}
          />
        ) : (
          <CheckInsTab checkIns={checkIns} onRefresh={() => detailQuery.refetch()} />
        )}
      </View>

      {editNameVisible ? <EditNameSheet
        visible
        profile={profile}
        onClose={() => setEditNameVisible(false)}
        onSaved={async (name) => {
          await updateMemberName(memberId, name);
          queryClient.setQueryData<MemberDetailData>(['member-detail', memberId], (current) => current ? ({ ...current, profile: { ...current.profile, fullName: name } }) : current);
          await queryClient.invalidateQueries({ queryKey: ['members'] });
          setNotice('Numele a fost actualizat');
        }}
      /> : null}
      {formVisible ? <MembershipFormSheet
        visible
        memberId={memberId}
        membership={editingMembership}
        onClose={() => setFormVisible(false)}
        onSaved={() => {
          setNotice(editingMembership ? 'Abonamentul a fost actualizat' : 'Abonamentul a fost creat');
          void queryClient.invalidateQueries({ queryKey: ['member-detail', memberId] });
          void queryClient.invalidateQueries({ queryKey: ['members'] });
          void queryClient.invalidateQueries({ queryKey: ['dashboard-stats'] });
        }}
      /> : null}
      {notice ? (
        <View style={[styles.notice, { bottom: Math.max(insets.bottom, 12) + 8, backgroundColor: colors.onSurface }]}>
          <AppText selectable color={colors.surface}>{notice}</AppText>
        </View>
      ) : null}
    </View>
  );
}

function InfoCard({ label, value, icon, color, monospace, onPress }: { label: string; value: string; icon: MaterialIconName; color: string; monospace?: boolean; onPress?: () => void }) {
  const { colors } = useAppTheme();
  return (
    <Pressable disabled={!onPress} onPress={onPress} style={({ pressed }) => [styles.infoCard, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5), opacity: pressed ? 0.72 : 1 }]}>
      <LinearGradient colors={[colorWithAlpha(color, 0.05), colorWithAlpha(color, 0.02)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} />
      <View style={[styles.infoIcon, { backgroundColor: colorWithAlpha(color, 0.15) }]}><MaterialIcon name={icon} size={20} color={color} /></View>
      <AppText numberOfLines={1} variant="titleLarge" style={[styles.infoValue, monospace ? styles.monospace : null]}>{value}</AppText>
      <AppText variant="bodySmall" color={color} style={styles.infoLabel}>{label}</AppText>
    </Pressable>
  );
}

function NavigationCard({ icon, label, onPress }: { icon: MaterialIconName; label: string; onPress: () => void }) {
  const { colors } = useAppTheme();
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.navigationCard, { backgroundColor: colors.surfaceContainer, borderColor: colorWithAlpha(colors.outlineVariant, 0.5), opacity: pressed ? 0.72 : 1 }]}>
      <MaterialIcon name={icon} size={24} color={colors.onSurface} />
      <AppText style={styles.navigationLabel}>{label}</AppText>
      <MaterialIcon name="arrow_forward_ios" size={16} color={colors.onSurfaceVariant} />
    </Pressable>
  );
}

function TabButton({ selected, icon, label, onPress }: { selected: boolean; icon: MaterialIconName; label: string; onPress: () => void }) {
  const { colors } = useAppTheme();
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [styles.tabButton, { borderBottomColor: selected ? colors.primary : 'transparent', opacity: pressed ? 0.65 : 1 }]}>
      <MaterialIcon name={icon} size={18} color={selected ? colors.onPrimaryContainer : colors.onSurfaceVariant} />
      <AppText numberOfLines={1} color={selected ? colors.onPrimaryContainer : colors.onSurfaceVariant} style={styles.tabLabel}>{label}</AppText>
    </Pressable>
  );
}

function MembershipsTab({ memberships, onRefresh, onAdd, onEdit, onDelete }: { memberships: Membership[]; onRefresh: () => Promise<unknown> | void; onAdd: () => void; onEdit: (membership: Membership) => void; onDelete: (membership: Membership) => void }) {
  const { colors } = useAppTheme();
  return (
    <View style={styles.flex}>
      <FlatList
        data={memberships}
        contentInsetAdjustmentBehavior="automatic"
        keyExtractor={(membership) => membership.id}
        contentContainerStyle={memberships.length ? styles.tabList : styles.emptyTabList}
        ItemSeparatorComponent={() => <View style={styles.listGap} />}
        renderItem={({ item }) => <MembershipCard membership={item} onEdit={() => onEdit(item)} onDelete={() => onDelete(item)} />}
        refreshControl={<ManualRefreshControl tintColor={colors.primary} colors={[colors.primary]} onRefresh={onRefresh} />}
        ListEmptyComponent={<EmptyState icon="card_membership_outlined" title="Niciun abonament" subtitle="Acest membru nu are abonamente" />}
      />
      <Pressable accessibilityRole="button" accessibilityLabel="Adaugă abonament" onPress={onAdd} style={({ pressed }) => [styles.fab, { backgroundColor: colors.primaryContainer, opacity: pressed ? 0.75 : 1 }]}>
        <MaterialIcon name="add" size={24} color={colors.onPrimaryContainer} />
      </Pressable>
    </View>
  );
}

function MembershipCard({ membership, onEdit, onDelete }: { membership: Membership; onEdit: () => void; onDelete: () => void }) {
  const { colors } = useAppTheme();
  const status = membershipVisualStatus(membership);
  const days = membership.daysLeft ?? membershipDaysUntilExpiry(membership);
  return (
    <View style={[styles.listCard, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5) }]}>
      <LinearGradient colors={[colorWithAlpha(status.color, 0.05), colorWithAlpha(status.color, 0.02)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} />
      <View style={styles.listCardContent}>
        <View style={styles.listCardHeader}>
          <View style={[styles.statusCircle, { backgroundColor: colorWithAlpha(status.color, 0.15) }]}><AppText style={styles.statusCircleEmoji}>{status.emoji}</AppText></View>
          <View style={styles.listCardTitle}>
            <AppText numberOfLines={1} variant="titleMedium" style={styles.bold}>{membership.plan?.name ?? 'Unknown'}</AppText>
            <AppText variant="bodySmall" color={status.color} style={styles.statusSubtitle}>{membershipStatusText(membership)}</AppText>
          </View>
          <Pressable accessibilityRole="button" accessibilityLabel="Editează" hitSlop={8} onPress={onEdit} style={({ pressed }) => ({ opacity: pressed ? 0.5 : 1, padding: 8 })}><MaterialIcon name="edit" size={24} color={status.color} /></Pressable>
          <Pressable accessibilityRole="button" accessibilityLabel="Șterge" hitSlop={8} onPress={onDelete} style={({ pressed }) => ({ opacity: pressed ? 0.5 : 1, padding: 8 })}><MaterialIcon name="delete" size={24} color="#F44336" /></Pressable>
        </View>
        <View style={styles.membershipMeta}>
          <Meta icon="calendar_today" text={`${formatDate(membership.effectiveStartDate ?? membership.startDate)} - ${formatDate(membership.endDate)}`} />
          {membership.gym ? <Meta icon="fitness_center" text={membership.gym.name} /> : null}
          {!membership.canceledAt && !membershipIsExpired(membership) && days >= 0 ? <Meta icon="timer" text={`${days}z rămase`} color={days <= 7 ? '#FF9800' : '#4CAF50'} /> : null}
        </View>
      </View>
    </View>
  );
}

function CheckInsTab({ checkIns, onRefresh }: { checkIns: CheckIn[]; onRefresh: () => Promise<unknown> | void }) {
  const { colors } = useAppTheme();
  return (
    <FlatList
      data={checkIns}
      contentInsetAdjustmentBehavior="automatic"
      keyExtractor={(checkIn) => checkIn.id}
      contentContainerStyle={checkIns.length ? styles.tabList : styles.emptyTabList}
      ItemSeparatorComponent={() => <View style={styles.listGap} />}
      renderItem={({ item }) => <CheckInCard checkIn={item} />}
      refreshControl={<ManualRefreshControl tintColor={colors.primary} colors={[colors.primary]} onRefresh={onRefresh} />}
      ListEmptyComponent={<EmptyState icon="check_circle_outline" title="Niciun check-in" subtitle="Check-in-urile vor apărea aici" />}
    />
  );
}

function CheckInCard({ checkIn }: { checkIn: CheckIn }) {
  const { colors } = useAppTheme();
  const denied = checkIn.status === 'denied' || checkIn.status === 'expired' || checkIn.status === 'no_access';
  const status = checkIn.status === 'success' ? { color: '#43A047', emoji: '✅' } : checkIn.status === 'expiring' ? { color: '#FB8C00', emoji: '⚠️' } : denied ? { color: '#E53935', emoji: '❌' } : { color: '#1E88E5', emoji: '⏰' };
  return (
    <View style={[styles.listCard, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5) }]}>
      <LinearGradient colors={[colorWithAlpha(status.color, 0.05), colorWithAlpha(status.color, 0.02)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={StyleSheet.absoluteFill} />
      <View style={styles.listCardContent}>
        <View style={styles.listCardHeader}>
          <View style={[styles.statusCircle, { backgroundColor: colorWithAlpha(status.color, 0.15) }]}><AppText style={styles.statusCircleEmoji}>{status.emoji}</AppText></View>
          <View style={styles.listCardTitle}>
            <AppText numberOfLines={1} variant="titleMedium" style={styles.bold}>{checkIn.gym?.name ?? 'Unknown'}</AppText>
            <AppText variant="bodySmall" color={colors.onSurfaceVariant}>{formatDateTime(checkIn.checkedInAt)}</AppText>
          </View>
        </View>
        {checkIn.message ? (
          <View style={[styles.messageBox, { backgroundColor: denied ? colorWithAlpha('#F44336', 0.1) : colorWithAlpha(colors.surfaceContainerHighest, 0.5) }]}>
            <MaterialIcon name={denied ? 'error_outline' : 'info_outline'} size={16} color={denied ? '#F44336' : status.color} />
            <AppText variant="bodySmall" style={styles.messageText}>{checkIn.message}</AppText>
          </View>
        ) : null}
      </View>
    </View>
  );
}

function Meta({ icon, text, color }: { icon: MaterialIconName; text: string; color?: string }) {
  const { colors } = useAppTheme();
  return <View style={styles.meta}><MaterialIcon name={icon} size={16} color={color ?? colors.onSurfaceVariant} /><AppText color={color} style={[styles.metaText, color ? styles.medium : null]}>{text}</AppText></View>;
}

function EmptyState({ icon, title, subtitle }: { icon: MaterialIconName; title: string; subtitle: string }) {
  const { colors } = useAppTheme();
  return <View style={styles.emptyState}><MaterialIcon name={icon} size={80} color={colorWithAlpha(colors.primary, 0.3)} /><AppText variant="titleLarge" style={styles.emptyStateTitle}>{title}</AppText><AppText color={colors.onSurfaceVariant} style={styles.emptyStateSubtitle}>{subtitle}</AppText></View>;
}

function EditNameSheet({ visible, profile, onClose, onSaved }: { visible: boolean; profile: Profile; onClose: () => void; onSaved: (name: string) => Promise<void> }) {
  const { colors } = useAppTheme();
  const insets = useSafeAreaInsets();
  const [name, setName] = React.useState(profile.fullName);
  const [saving, setSaving] = React.useState(false);
  const [error, setError] = React.useState<string>();
  const save = async () => {
    const trimmed = name.trim();
    if (!trimmed || trimmed === profile.fullName) return;
    setSaving(true);
    try { await onSaved(trimmed); onClose(); } catch (cause) { setError(cause instanceof Error ? cause.message : String(cause)); } finally { setSaving(false); }
  };
  return (
    <BottomSheetModal
      visible={visible}
      onClose={onClose}
      keyboardAvoiding
      disableDismiss={saving}
      snapPoints={['20%', '30%', '40%']}
      initialIndex={1}
      sheetStyle={[styles.editSheet, { backgroundColor: colors.surface, paddingBottom: Math.max(insets.bottom, 16) }]}>
          <View style={[styles.editHandle, { backgroundColor: colorWithAlpha(colors.onSurfaceVariant, 0.4) }]} />
          <AppText variant="titleLarge" style={styles.editTitle}>Editează Nume</AppText>
          <View style={[styles.editRule, { backgroundColor: colors.outlineVariant }]} />
          <View style={styles.editContent}>
            <View style={[styles.nameField, { borderColor: error ? colors.error : colors.outline }]}>
              <MaterialIcon name="person_outline" size={24} color={colors.onSurfaceVariant} />
              <View style={styles.nameFieldCopy}><AppText variant="bodySmall" color={colors.onSurfaceVariant}>Nume complet</AppText><BottomSheetTextInput autoFocus value={name} onChangeText={setName} textContentType="name" autoCapitalize="words" selectionColor={colors.primary} style={[styles.nameInput, { color: colors.onSurface }]} /></View>
            </View>
            {error ? <AppText selectable variant="bodySmall" color={colors.error}>{error}</AppText> : null}
          </View>
          <View style={styles.editActions}>
            <Pressable disabled={saving} onPress={onClose} style={({ pressed }) => [styles.editButton, { borderColor: colors.outline, opacity: pressed ? 0.65 : 1 }]}><AppText color={colors.primary}>Anulează</AppText></Pressable>
            <Pressable disabled={saving} onPress={() => void save()} style={({ pressed }) => [styles.editButton, { borderColor: colors.primary, backgroundColor: colors.primary, opacity: pressed ? 0.72 : 1 }]}>{saving ? <ActivityIndicator color={colors.onPrimary} /> : <AppText color={colors.onPrimary}>Salvează</AppText>}</Pressable>
          </View>
    </BottomSheetModal>
  );
}

function membershipVisualStatus(membership: Membership): { color: string; emoji: string } {
  if (membership.canceledAt) return { color: '#7B1FA2', emoji: '🚫' };
  if (membership.isFrozen) return { color: '#1E88E5', emoji: '❄️' };
  if (membershipIsExpired(membership)) return { color: '#E53935', emoji: '❌' };
  const days = membership.daysLeft ?? membershipDaysUntilExpiry(membership);
  return days <= 7 ? { color: '#FB8C00', emoji: '⚠️' } : { color: '#43A047', emoji: '✅' };
}

function formatDate(date: Date | CalendarDate): string {
  if (typeof date === 'string') return formatCalendarDate(date);
  return `${String(date.getDate()).padStart(2, '0')} ${date.toLocaleDateString('en-GB', { month: 'short' })} ${date.getFullYear()}`;
}

function formatDateTime(date: Date): string {
  return `${formatDate(date)}, ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  screen: { flex: 1 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  errorPage: { padding: 24 },
  errorText: { textAlign: 'center', marginTop: 16 },
  memberHeader: { paddingBottom: 16 },
  backRow: { height: 56, paddingHorizontal: 8, justifyContent: 'center', alignItems: 'flex-start' },
  memberIdentity: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16 },
  largeAvatar: { width: 72, height: 72, borderRadius: 36, alignItems: 'center', justifyContent: 'center' },
  identityCopy: { flex: 1, marginLeft: 16, alignItems: 'flex-start' },
  nameRow: { flexDirection: 'row', alignItems: 'center', alignSelf: 'stretch' },
  memberName: { flex: 1, fontSize: 24, lineHeight: 32, fontWeight: '700' },
  activeBadge: { borderRadius: 8, paddingHorizontal: 10, paddingVertical: 4, marginTop: 4 },
  activeText: { fontSize: 12, lineHeight: 16, fontWeight: '700' },
  bold: { fontWeight: '700' },
  medium: { fontWeight: '500' },
  summaryArea: { padding: 16, paddingBottom: 0 },
  summaryRow: { flexDirection: 'row' },
  summaryGap: { width: 12 },
  infoCard: { flex: 1, minHeight: 136, borderWidth: StyleSheet.hairlineWidth, borderRadius: 16, overflow: 'hidden', padding: 16, alignItems: 'flex-start' },
  infoIcon: { width: 40, height: 40, borderRadius: 10, alignItems: 'center', justifyContent: 'center' },
  infoValue: { fontWeight: '700', marginTop: 12 },
  infoLabel: { fontWeight: '600', marginTop: 4 },
  monospace: { fontFamily: 'monospace' },
  navigationCard: { minHeight: 56, flexDirection: 'row', alignItems: 'center', borderRadius: 16, borderWidth: StyleSheet.hairlineWidth, padding: 16, marginTop: 16 },
  navigationLabel: { flex: 1, marginLeft: 12 },
  tabs: { height: 52, borderRadius: 12, marginTop: 16, flexDirection: 'row' },
  tabButton: { flex: 1, borderBottomWidth: 2, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 4 },
  tabLabel: { fontSize: 13, fontWeight: '500', marginLeft: 8 },
  tabContent: { flex: 1 },
  tabList: { padding: 16, paddingBottom: 88 },
  emptyTabList: { flexGrow: 1, padding: 16 },
  listGap: { height: 12 },
  listCard: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 16, overflow: 'hidden' },
  listCardContent: { padding: 16 },
  listCardHeader: { flexDirection: 'row', alignItems: 'center' },
  statusCircle: { width: 48, height: 48, borderRadius: 24, alignItems: 'center', justifyContent: 'center' },
  statusCircleEmoji: { fontSize: 24, lineHeight: 32 },
  listCardTitle: { flex: 1, marginLeft: 12 },
  statusSubtitle: { fontWeight: '600', marginTop: 2 },
  membershipMeta: { flexDirection: 'row', flexWrap: 'wrap', gap: 16, marginTop: 16 },
  meta: { flexDirection: 'row', alignItems: 'center' },
  metaText: { marginLeft: 6 },
  messageBox: { flexDirection: 'row', alignItems: 'center', borderRadius: 8, padding: 12, marginTop: 12 },
  messageText: { flex: 1, marginLeft: 8, fontWeight: '500' },
  emptyState: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  emptyStateTitle: { fontWeight: '700', marginTop: 24 },
  emptyStateSubtitle: { marginTop: 8 },
  fab: { position: 'absolute', right: 16, bottom: 16, width: 56, height: 56, borderRadius: 16, alignItems: 'center', justifyContent: 'center', elevation: 5, shadowColor: '#000', shadowOpacity: 0.2, shadowRadius: 4, shadowOffset: { width: 0, height: 3 } },
  notice: { position: 'absolute', alignSelf: 'center', paddingHorizontal: 16, paddingVertical: 12, borderRadius: 8, maxWidth: '90%' },
  editSheet: { minHeight: '30%', maxHeight: '45%', borderTopLeftRadius: 20, borderTopRightRadius: 20 },
  editHandle: { width: 40, height: 4, borderRadius: 2, alignSelf: 'center', marginTop: 12, marginBottom: 8 },
  editTitle: { fontWeight: '700', textAlign: 'center', padding: 16 },
  editRule: { height: StyleSheet.hairlineWidth },
  editContent: { flex: 1, padding: 16, gap: 6 },
  nameField: { minHeight: 56, borderWidth: 1, borderRadius: 4, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12 },
  nameFieldCopy: { flex: 1, marginLeft: 12 },
  nameInput: { fontSize: 16, lineHeight: 22, paddingVertical: 0 },
  editActions: { flexDirection: 'row', gap: 12, paddingHorizontal: 16 },
  editButton: { flex: 1, minHeight: 44, borderWidth: 1, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
});
