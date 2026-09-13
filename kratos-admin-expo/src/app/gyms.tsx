import { Stack } from 'expo-router';
import { useQuery } from '@tanstack/react-query';
import React from 'react';
import { ActivityIndicator, ScrollView, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/app-text';
import { ManualRefreshControl } from '@/components/manual-refresh-control';
import { MaterialIcon } from '@/components/material-icon';
import { getGyms } from '@/repositories/gyms-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

export default function GymsScreen() {
  const { colors } = useAppTheme();
  const gymsQuery = useQuery({ queryKey: ['gyms'], queryFn: getGyms });

  if (gymsQuery.isLoading) {
    return <View style={[styles.center, { backgroundColor: colors.surfaceContainerLowest }]}><Stack.Screen options={{ title: 'Săli' }} /><ActivityIndicator size="large" color={colors.primary} /></View>;
  }

  const gyms = gymsQuery.data ?? [];
  return <View style={[styles.screen, { backgroundColor: colors.surfaceContainerLowest }]}><Stack.Screen options={{ title: 'Săli' }} />
    <ScrollView contentContainerStyle={gyms.length ? styles.content : styles.emptyContent} contentInsetAdjustmentBehavior="automatic" refreshControl={<ManualRefreshControl onRefresh={() => gymsQuery.refetch()} tintColor={colors.primary} colors={[colors.primary]} />}>
      {gymsQuery.error ? <AppText selectable color={colors.error} style={styles.error}>Eroare: {gymsQuery.error instanceof Error ? gymsQuery.error.message : String(gymsQuery.error)}</AppText> : null}
      {!gyms.length ? <View style={styles.empty}><MaterialIcon name="fitness_center" size={64} color={colors.onSurfaceVariant} /><AppText variant="titleLarge" style={styles.emptyTitle}>Nicio sală</AppText></View> : gyms.map((gym) => <View key={gym.id} style={[styles.card, { backgroundColor: colors.surface, borderColor: colorWithAlpha(colors.outlineVariant, 0.55) }]}><View style={styles.header}><AppText style={styles.name}>{gym.name}</AppText><View style={[styles.status, { backgroundColor: gym.isActive ? colorWithAlpha('#4CAF50', 0.1) : colors.surfaceContainerHighest }]}><AppText color={gym.isActive ? '#4CAF50' : colors.onSurfaceVariant} style={styles.statusText}>{gym.isActive ? 'ACTIV' : 'INACTIV'}</AppText></View></View>{gym.address ? <Detail icon="location_on" value={gym.address} /> : null}{gym.cityName ? <Detail icon="location_city" value={gym.cityName} /> : null}{gym.phoneNumber ? <Detail icon="phone" value={gym.phoneNumber} /> : null}{gym.emailAddress ? <Detail icon="email" value={gym.emailAddress} /> : null}</View>)}
    </ScrollView>
  </View>;
}

function Detail({ icon, value }: { icon: 'location_on' | 'location_city' | 'phone' | 'email'; value: string }) {
  const { colors } = useAppTheme();
  return <View style={styles.detail}><MaterialIcon name={icon} size={16} color={colors.onSurfaceVariant} /><AppText style={styles.detailText}>{value}</AppText></View>;
}

const styles = StyleSheet.create({ screen: { flex: 1 }, center: { flex: 1, alignItems: 'center', justifyContent: 'center' }, content: { padding: 16, paddingBottom: 24 }, emptyContent: { flexGrow: 1 }, error: { margin: 16 }, empty: { flex: 1, alignItems: 'center', justifyContent: 'center' }, emptyTitle: { marginTop: 16 }, card: { borderWidth: StyleSheet.hairlineWidth, borderRadius: 12, padding: 16, marginBottom: 12 }, header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }, name: { flex: 1, fontSize: 18, lineHeight: 24, fontWeight: '600', marginRight: 12 }, status: { paddingHorizontal: 12, paddingVertical: 6, borderRadius: 12 }, statusText: { fontSize: 12, lineHeight: 16, fontWeight: '700' }, detail: { flexDirection: 'row', alignItems: 'center', marginTop: 8 }, detailText: { flex: 1, marginLeft: 8 } });
