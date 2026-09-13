import { LinearGradient } from 'expo-linear-gradient';
import { useQuery } from '@tanstack/react-query';
import React from 'react';
import {
  ActivityIndicator,
  ScrollView,
  StyleSheet,
  View,
  useWindowDimensions,
} from 'react-native';

import { AppText } from '@/components/app-text';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { getDashboardStats, type DashboardStats } from '@/repositories/dashboard-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

const cards: readonly {
  key: keyof DashboardStats;
  title: string;
  icon: string;
  color: string;
}[] = [
  { key: 'totalMembers', title: 'Total Membri', icon: '👥', color: '#1E88E5' },
  { key: 'activeMemberships', title: 'Abonamente Active', icon: '💳', color: '#43A047' },
  { key: 'todayCheckIns', title: 'Check-ins Astăzi', icon: '✅', color: '#FB8C00' },
  { key: 'monthlyRevenue', title: 'Venituri Luna', icon: '💰', color: '#8E24AA' },
  { key: 'wau', title: 'WAU', icon: '📅', color: '#00897B' },
  { key: 'mau', title: 'MAU', icon: '📈', color: '#3949AB' },
];

export default function DashboardScreen() {
  const { colors } = useAppTheme();
  const { width } = useWindowDimensions();
  const contentWidth = width - 32;
  const cardSize = (contentWidth - 4) / 2;
  const statsQuery = useQuery({ queryKey: ['dashboard-stats'], queryFn: () => getDashboardStats() });

  if (statsQuery.isLoading && !statsQuery.data) {
    return (
      <View style={[styles.center, { backgroundColor: colors.surfaceContainerLowest }]}>
        <ActivityIndicator size="large" color={colors.primary} />
      </View>
    );
  }

  const stats = statsQuery.data ?? {
    totalMembers: 0,
    activeMemberships: 0,
    todayCheckIns: 0,
    monthlyRevenue: 0,
    wau: 0,
    mau: 0,
    dauYesterday: 0,
  };

  return (
    <ScrollView
      style={{ backgroundColor: colors.surfaceContainerLowest }}
      contentContainerStyle={styles.content}
      contentInsetAdjustmentBehavior="automatic"
      refreshControl={
        <ManualRefreshControl
          tintColor={colors.primary}
          colors={[colors.primary]}
          onRefresh={() => statsQuery.refetch()}
        />
      }>
      <AppText variant="headlineLarge" style={styles.bold}>
        Kratos Gym
      </AppText>
      <AppText variant="bodyLarge" color={colors.onSurfaceVariant} style={styles.subtitle}>
        Panou de Administrare
      </AppText>

      {statsQuery.error ? (
        <View style={[styles.error, { backgroundColor: colorWithAlpha(colors.error, 0.1) }]}>
          <AppText selectable color={colors.error}>
            Eroare: {statsQuery.error instanceof Error ? statsQuery.error.message : String(statsQuery.error)}
          </AppText>
        </View>
      ) : null}

      <View style={styles.grid}>
        {cards.map((card) => {
          const cardView = (
            <StatCard
              title={card.title}
              icon={card.icon}
              color={card.color}
              value={
                card.key === 'monthlyRevenue'
                  ? `${stats.monthlyRevenue.toFixed(0)} RON`
                  : String(stats[card.key])
              }
              size={cardSize}
            />
          );
          return <React.Fragment key={card.key}>{cardView}</React.Fragment>;
        })}
      </View>

      <StatCard
        compact
        title="DAU Ieri"
        icon="🌙"
        color="#D81B60"
        value={String(stats.dauYesterday)}
        size={contentWidth}
      />
    </ScrollView>
  );
}

function StatCard({
  title,
  value,
  icon,
  color,
  compact = false,
  size,
}: {
  title: string;
  value: string;
  icon: string;
  color: string;
  compact?: boolean;
  size: number;
}) {
  const { colors } = useAppTheme();
  return (
    <View
      style={[
        styles.card,
        {
          width: size,
          height: compact ? 98 : size,
          borderColor: colors.outlineVariant,
        },
      ]}>
      <LinearGradient
        colors={[colorWithAlpha(color, 0.05), colorWithAlpha(color, 0.02)]}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={StyleSheet.absoluteFill}
      />
      {compact ? (
        <View style={styles.compactContent}>
          <View style={[styles.iconBox, { backgroundColor: colorWithAlpha(color, 0.15) }]}>
            <AppText style={styles.compactEmoji}>{icon}</AppText>
          </View>
          <View style={styles.compactCopy}>
            <AppText numberOfLines={1} variant="titleLarge" style={styles.bold}>
              {value}
            </AppText>
            <AppText numberOfLines={1} color={color} style={styles.compactTitle}>
              {title}
            </AppText>
          </View>
        </View>
      ) : (
        <View style={styles.cardContent}>
          <View style={[styles.iconBox, { backgroundColor: colorWithAlpha(color, 0.15) }]}>
            <AppText style={styles.emoji}>{icon}</AppText>
          </View>
          <View>
            <AppText numberOfLines={1} variant="headlineMedium" style={styles.value}>
              {value}
            </AppText>
            <View style={[styles.pill, { backgroundColor: colorWithAlpha(color, 0.15) }]}>
              <AppText numberOfLines={1} color={color} style={styles.pillText}>
                {title}
              </AppText>
            </View>
          </View>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  content: { padding: 16, paddingBottom: 24 },
  bold: { fontWeight: '700' },
  subtitle: { marginTop: 4, marginBottom: 24 },
  error: { borderRadius: 12, borderCurve: 'continuous', padding: 12, marginBottom: 12 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 4, marginBottom: 8 },
  card: {
    borderRadius: 16,
    borderCurve: 'continuous',
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  cardContent: { flex: 1, padding: 16, justifyContent: 'space-between', alignItems: 'flex-start' },
  iconBox: {
    width: 48,
    height: 48,
    borderRadius: 12,
    borderCurve: 'continuous',
    alignItems: 'center',
    justifyContent: 'center',
  },
  emoji: { fontSize: 28, lineHeight: 36 },
  compactEmoji: { fontSize: 24, lineHeight: 32 },
  value: { fontWeight: '700', fontSize: 24, lineHeight: 32 },
  pill: {
    alignSelf: 'flex-start',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 8,
    borderCurve: 'continuous',
    marginTop: 6,
    maxWidth: '100%',
  },
  pillText: { fontSize: 12, lineHeight: 16, fontWeight: '600' },
  compactContent: { flex: 1, flexDirection: 'row', alignItems: 'center', padding: 16 },
  compactCopy: { flex: 1, marginLeft: 12 },
  compactTitle: { fontSize: 12, lineHeight: 16, fontWeight: '600', marginTop: 4 },
});
