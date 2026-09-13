import { memberProfileSnapshot } from '@/navigation/member-profile-snapshot';
import { useQuery } from '@tanstack/react-query';
import React from 'react';
import {
  ActivityIndicator,
  FlatList,
  StyleSheet,
  View,
} from 'react-native';

import { AppText } from '@/components/app-text';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { MaterialIcon } from '@/components/material-icon';
import type { MaterialIconName } from '@/constants/material-icons.generated';
import type { RevenueLedger } from '@/models/revenue-ledger';
import { getMemberProfile, getMemberRevenueHistory } from '@/repositories/members-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

export function MemberRevenueHistoryScreen({ memberId }: { memberId: string }) {
  const { colors } = useAppTheme();
  const profileRef = React.useRef<Awaited<ReturnType<typeof getMemberProfile>> | undefined>(memberProfileSnapshot(memberId));
  const revenueQuery = useQuery({
    queryKey: ['member-revenue-history', memberId],
    queryFn: async () => {
      const profile = profileRef.current ?? await getMemberProfile(memberId);
      profileRef.current = profile;
      const entries = await getMemberRevenueHistory(profile);
      return { profile, entries };
    },
  });

  if (revenueQuery.isLoading) {
    return <View style={[styles.center, { backgroundColor: colors.surfaceContainerLowest }]}><ActivityIndicator size="large" color={colors.primary} /></View>;
  }

  const entries = revenueQuery.data?.entries ?? [];
  const memberName = revenueQuery.data?.profile.fullName ?? '';
  const totalCents = entries
    .filter((entry) => !entry.isDeleted)
    .reduce((sum, entry) => sum + (entry.entryKind === 'refund' ? -entry.amountCents : entry.amountCents), 0);

  return (
    <FlatList
      style={{ backgroundColor: colors.surfaceContainerLowest }}
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={entries.length ? styles.list : styles.emptyList}
      data={entries}
      keyExtractor={(entry) => entry.id}
      renderItem={({ item }) => <RevenueCard entry={item} memberName={memberName} />}
      refreshControl={<ManualRefreshControl tintColor={colors.primary} colors={[colors.primary]} onRefresh={() => revenueQuery.refetch()} />}
      ListHeaderComponent={entries.length ? <RevenueSummary totalCents={totalCents} count={entries.length} /> : null}
      ListEmptyComponent={
        <View style={styles.empty}>
          {revenueQuery.error ? (
            <AppText selectable color={colors.error} style={styles.errorText}>
              Eroare la încărcarea încasărilor: {revenueQuery.error instanceof Error ? revenueQuery.error.message : String(revenueQuery.error)}
            </AppText>
          ) : (
            <>
              <MaterialIcon name="receipt_long_outlined" size={72} color={colorWithAlpha(colors.primary, 0.35)} />
              <AppText variant="titleMedium" style={styles.emptyTitle}>Nicio încasare</AppText>
            </>
          )}
        </View>
      }
    />
  );
}

function RevenueSummary({ totalCents, count }: { totalCents: number; count: number }) {
  const { colors } = useAppTheme();
  return (
    <View style={[styles.summary, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5) }]}>
      <View style={[styles.summaryIcon, { backgroundColor: colorWithAlpha(colors.primaryContainer, 0.55) }]}>
        <MaterialIcon name="payments_outlined" size={24} color={colors.onPrimaryContainer} />
      </View>
      <View style={styles.summaryCopy}>
        <AppText variant="titleLarge" style={styles.bold}>{(totalCents / 100).toFixed(2)} RON</AppText>
        <AppText variant="bodySmall" color={colors.onSurfaceVariant}>{count} tranzacții</AppText>
      </View>
    </View>
  );
}

function RevenueCard({ entry, memberName }: { entry: RevenueLedger; memberName: string }) {
  const { colors } = useAppTheme();
  const isRefund = entry.entryKind === 'refund';
  const amount = `${(entry.amountCents / 100).toFixed(2)} ${entry.currency}`;
  const amountLabel = entry.isDeleted ? `${amount} • ȘTERS` : isRefund ? `- ${amount}` : `+ ${amount}`;
  const amountColor = entry.isDeleted ? colors.onErrorContainer : isRefund ? colors.error : '#4CAF50';

  return (
    <View style={[styles.card, { borderColor: entry.isDeleted ? colorWithAlpha(colors.error, 0.35) : colorWithAlpha(colors.outlineVariant, 0.5) }]}>
      <View style={styles.cardHeader}>
        <AppText numberOfLines={2} style={styles.clientName}>{entry.clientProfile?.fullName ?? memberName}</AppText>
        <View style={[styles.amountBadge, { backgroundColor: entry.isDeleted || isRefund ? colorWithAlpha(colors.errorContainer, 0.45) : colorWithAlpha('#4CAF50', 0.15) }]}>
          <AppText color={amountColor} style={styles.amountText}>{amountLabel}</AppText>
        </View>
      </View>

      <View style={styles.metaWrap}>
        <Meta icon="event" label={formatDateTime(entry.paidAt)} />
        <Meta icon={entry.paymentMethod === 'cash' ? 'money' : 'credit_card'} label={entry.paymentMethod} />
        {entry.gym ? <Meta icon="fitness_center" label={entry.gym.name} /> : null}
        {entry.recordedByProfile ? <Meta icon="person_outline" label={`Înregistrat de ${entry.recordedByProfile.fullName}`} /> : null}
      </View>

      {entry.isDeleted ? (
        <View style={[styles.deletedBadge, { backgroundColor: colorWithAlpha(colors.errorContainer, 0.35) }]}>
          <MaterialIcon name="delete_outline" size={14} color={colors.onErrorContainer} />
          <AppText variant="bodySmall" color={colors.onErrorContainer} style={styles.deletedText}>
            {entry.deletedAt ? `Șters la ${formatDateTime(entry.deletedAt)}` : 'Marcat ca șters'}
          </AppText>
        </View>
      ) : null}

      {entry.plan ? (
        <View style={[styles.planBadge, { backgroundColor: colorWithAlpha(colors.primaryContainer, 0.5) }]}>
          <MaterialIcon name="card_membership" size={12} color={colors.onPrimaryContainer} />
          <AppText variant="bodySmall" color={colors.onPrimaryContainer} style={styles.planText}>{entry.plan.name}</AppText>
        </View>
      ) : null}
      {entry.notes ? <AppText variant="bodySmall" style={styles.notes}>{entry.notes}</AppText> : null}
    </View>
  );
}

function Meta({ icon, label }: { icon: MaterialIconName; label: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={styles.meta}>
      <MaterialIcon name={icon} size={14} color={colors.onSurfaceVariant} />
      <AppText variant="bodySmall" style={styles.metaLabel}>{label}</AppText>
    </View>
  );
}

function formatDateTime(date: Date): string {
  const day = String(date.getDate()).padStart(2, '0');
  const month = date.toLocaleDateString('en-GB', { month: 'short' });
  return `${day} ${month} ${date.getFullYear()}, ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  list: { padding: 16 },
  emptyList: { flexGrow: 1 },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 },
  emptyTitle: { marginTop: 16 },
  errorText: { textAlign: 'center' },
  summary: { minHeight: 76, borderWidth: StyleSheet.hairlineWidth, borderRadius: 12, padding: 16, flexDirection: 'row', alignItems: 'center', marginBottom: 12 },
  summaryIcon: { width: 44, height: 44, borderRadius: 10, alignItems: 'center', justifyContent: 'center' },
  summaryCopy: { flex: 1, marginLeft: 12 },
  bold: { fontWeight: '700' },
  card: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 12, padding: 16, marginBottom: 12 },
  cardHeader: { flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between' },
  clientName: { flex: 1, fontSize: 16, lineHeight: 24, fontWeight: '600', marginRight: 8 },
  amountBadge: { borderRadius: 8, paddingHorizontal: 12, paddingVertical: 6 },
  amountText: { fontSize: 14, lineHeight: 20, fontWeight: '700' },
  metaWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 16, rowGap: 8, marginTop: 12 },
  meta: { flexDirection: 'row', alignItems: 'center' },
  metaLabel: { marginLeft: 4 },
  deletedBadge: { alignSelf: 'flex-start', flexDirection: 'row', alignItems: 'center', borderRadius: 8, paddingHorizontal: 10, paddingVertical: 6, marginTop: 8 },
  deletedText: { flexShrink: 1, fontWeight: '600', marginLeft: 6 },
  planBadge: { alignSelf: 'flex-start', flexDirection: 'row', alignItems: 'center', borderRadius: 6, paddingHorizontal: 10, paddingVertical: 4, marginTop: 8 },
  planText: { fontWeight: '500', marginLeft: 4 },
  notes: { fontStyle: 'italic', marginTop: 8 },
});
