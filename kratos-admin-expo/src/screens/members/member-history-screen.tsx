import { formatCalendarDate } from '@/utils/calendar-date';
import { flutterCalendarDate } from '@/utils/flutter-date';
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
import { membershipEventLabel, type MembershipEvent } from '@/models/membership-event';
import { getMemberHistory } from '@/repositories/members-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

const eventVisuals: Record<string, { icon: MaterialIconName; color: string }> = {
  created: { icon: 'add_circle', color: '#43A047' },
  extended: { icon: 'update', color: '#1E88E5' },
  canceled: { icon: 'cancel', color: '#E53935' },
  paused: { icon: 'pause_circle', color: '#7B1FA2' },
  upgraded: { icon: 'upgrade', color: '#FB8C00' },
  edited: { icon: 'edit', color: '#757575' },
  resumed: { icon: 'play_circle', color: '#00ACC1' },
};
const defaultVisual = { icon: 'info' as MaterialIconName, color: '#757575' };

export function MemberHistoryScreen({ memberId }: { memberId: string }) {
  const { colors } = useAppTheme();
  const historyQuery = useQuery({
    queryKey: ['member-history', memberId],
    queryFn: () => getMemberHistory(memberId),
  });

  if (historyQuery.isLoading) {
    return <View style={[styles.center, { backgroundColor: colors.surfaceContainerLowest }]}><ActivityIndicator size="large" color={colors.primary} /></View>;
  }

  const events = historyQuery.data ?? [];
  return (
    <FlatList
      style={{ backgroundColor: colors.surfaceContainerLowest }}
      contentInsetAdjustmentBehavior="automatic"
      contentContainerStyle={events.length ? styles.list : styles.emptyList}
      data={events}
      keyExtractor={(event) => event.id}
      renderItem={({ item, index }) => (
        <TimelineItem event={item} first={index === 0} last={index === events.length - 1} />
      )}
      refreshControl={<ManualRefreshControl tintColor={colors.primary} colors={[colors.primary]} onRefresh={() => historyQuery.refetch()} />}
      ListEmptyComponent={
        <View style={styles.center}>
          {historyQuery.error ? (
            <AppText selectable color={colors.error} style={styles.emptyCopy}>
              Eroare: {historyQuery.error instanceof Error ? historyQuery.error.message : String(historyQuery.error)}
            </AppText>
          ) : (
            <>
              <MaterialIcon name="history" size={80} color={colorWithAlpha(colors.primary, 0.3)} />
              <AppText variant="titleLarge" style={styles.emptyTitle}>Niciun eveniment</AppText>
              <AppText color={colors.onSurfaceVariant} style={styles.emptySubtitle}>Istoricul va apărea aici</AppText>
            </>
          )}
        </View>
      }
    />
  );
}

function TimelineItem({ event, first, last }: { event: MembershipEvent; first: boolean; last: boolean }) {
  const { colors } = useAppTheme();
  const visual = eventVisuals[event.eventType] ?? defaultVisual;
  return (
    <View style={styles.timelineItem}>
      <View style={styles.timelineRail}>
        {!first ? <View style={[styles.topLine, { backgroundColor: colorWithAlpha(colors.outlineVariant, 0.5) }]} /> : null}
        <View style={[styles.dot, { backgroundColor: colorWithAlpha(visual.color, 0.15), borderColor: visual.color }]}>
          <MaterialIcon name={visual.icon} size={16} color={visual.color} />
        </View>
        {!last ? <View style={[styles.bottomLine, { backgroundColor: colorWithAlpha(colors.outlineVariant, 0.5) }]} /> : null}
      </View>
      <View style={[styles.eventCard, { borderColor: colorWithAlpha(colors.outlineVariant, 0.5) }]}>
        <View style={styles.eventHeader}>
          <View style={[styles.eventBadge, { backgroundColor: colorWithAlpha(visual.color, 0.15) }]}>
            <AppText color={visual.color} style={styles.eventBadgeText}>{membershipEventLabel(event.eventType)}</AppText>
          </View>
          <AppText variant="bodySmall" color={colors.onSurfaceVariant} style={styles.eventTime}>{formatDateTime(event.at)}</AppText>
        </View>

        {event.planName ? <MetaRow icon="card_membership" text={event.planName} bold /> : null}
        {event.newStartDate || event.newEndDate ? <DateChange event={event} /> : null}
        {event.deltaDays !== null || event.deltaCents !== null ? (
          <View style={styles.infoChips}>
            {event.deltaDays !== null ? <InfoChip icon="calendar_today" text={`${event.deltaDays > 0 ? '+' : ''}${event.deltaDays} zile`} color={event.deltaDays > 0 ? '#4CAF50' : '#F44336'} /> : null}
            {event.deltaCents !== null ? <InfoChip icon="payments" text={`${(event.deltaCents / 100).toFixed(0)} RON`} color="#2196F3" /> : null}
          </View>
        ) : null}
        {event.byUserName ? <MetaRow icon="person_outline" text={`de ${event.byUserName}`} italic small /> : null}
        {event.notes ? (
          <View style={[styles.notes, { backgroundColor: colorWithAlpha(colors.surfaceContainerHighest, 0.5) }]}>
            <MaterialIcon name="notes" size={14} color={colors.onSurfaceVariant} />
            <AppText variant="bodySmall" color={colors.onSurfaceVariant} style={styles.notesCopy}>{event.notes}</AppText>
          </View>
        ) : null}
      </View>
    </View>
  );
}

function DateChange({ event }: { event: MembershipEvent }) {
  const { colors } = useAppTheme();
  if (!event.newEndDate) return null;
  return (
    <View style={styles.dateChange}>
      <MaterialIcon name="date_range" size={16} color={colors.onSurfaceVariant} />
      {event.oldEndDate ? <AppText variant="bodySmall" color={colors.onSurfaceVariant} style={styles.oldDate}>{formatDate(event.oldEndDate)}</AppText> : null}
      {event.oldEndDate ? <MaterialIcon name="arrow_forward" size={14} color={colors.onSurfaceVariant} style={styles.dateArrow} /> : null}
      <AppText variant="bodySmall" color="#4CAF50" style={styles.newDate}>{formatDate(event.newEndDate)}</AppText>
    </View>
  );
}

function MetaRow({ icon, text, bold, italic, small }: { icon: MaterialIconName; text: string; bold?: boolean; italic?: boolean; small?: boolean }) {
  const { colors } = useAppTheme();
  return (
    <View style={styles.metaRow}>
      <MaterialIcon name={icon} size={small ? 14 : 16} color={colors.onSurfaceVariant} />
      <AppText variant={small ? 'bodySmall' : 'body'} color={small ? colors.onSurfaceVariant : undefined} style={[styles.metaCopy, bold ? styles.bold : null, italic ? styles.italic : null]}>{text}</AppText>
    </View>
  );
}

function InfoChip({ icon, text, color }: { icon: MaterialIconName; text: string; color: string }) {
  return (
    <View style={[styles.infoChip, { backgroundColor: colorWithAlpha(color, 0.1) }]}>
      <MaterialIcon name={icon} size={14} color={color} />
      <AppText color={color} style={styles.infoChipText}>{text}</AppText>
    </View>
  );
}

function formatDate(date: Date): string {
  return formatCalendarDate(flutterCalendarDate(date));
}
function formatDateTime(date: Date): string {
  return `${formatDate(new Date(date.getTime()))}, ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  list: { padding: 16 },
  emptyList: { flexGrow: 1, padding: 24 },
  emptyTitle: { fontWeight: '700', marginTop: 24 },
  emptySubtitle: { marginTop: 8 },
  emptyCopy: { textAlign: 'center' },
  timelineItem: { flexDirection: 'row', alignItems: 'stretch' },
  timelineRail: { width: 48, alignItems: 'center' },
  topLine: { width: 2, height: 12 },
  dot: { width: 32, height: 32, borderRadius: 16, borderWidth: 2, alignItems: 'center', justifyContent: 'center' },
  bottomLine: { width: 2, flex: 1, minHeight: 16 },
  eventCard: { flex: 1, borderWidth: StyleSheet.hairlineWidth, borderRadius: 12, padding: 16, marginLeft: 12, marginBottom: 16 },
  eventHeader: { flexDirection: 'row', alignItems: 'center' },
  eventBadge: { borderRadius: 6, paddingHorizontal: 8, paddingVertical: 4 },
  eventBadgeText: { fontSize: 12, lineHeight: 16, fontWeight: '700' },
  eventTime: { flex: 1, textAlign: 'right', marginLeft: 8 },
  metaRow: { flexDirection: 'row', alignItems: 'center', marginTop: 12 },
  metaCopy: { flexShrink: 1, marginLeft: 6 },
  bold: { fontWeight: '600' },
  italic: { fontStyle: 'italic' },
  dateChange: { flexDirection: 'row', alignItems: 'center', marginTop: 8 },
  oldDate: { textDecorationLine: 'line-through', marginLeft: 6 },
  dateArrow: { marginHorizontal: 4 },
  newDate: { fontWeight: '600' },
  infoChips: { flexDirection: 'row', flexWrap: 'wrap', gap: 12, marginTop: 8 },
  infoChip: { borderRadius: 6, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, paddingVertical: 4 },
  infoChipText: { fontSize: 12, lineHeight: 16, fontWeight: '600', marginLeft: 4 },
  notes: { borderRadius: 6, flexDirection: 'row', alignItems: 'flex-start', padding: 8, marginTop: 8 },
  notesCopy: { flex: 1, marginLeft: 6 },
});
