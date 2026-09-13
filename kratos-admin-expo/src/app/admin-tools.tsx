import { router, Stack } from 'expo-router';
import React from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/app-text';
import { MaterialIcon } from '@/components/material-icon';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

const tools = [
  { title: 'Săli', subtitle: 'Locații, date de contact și status', icon: 'fitness_center' as const, color: '#1E88E5', route: '/gyms' as const },
  { title: 'Planuri Abonamente', subtitle: 'Prețuri, durate și disponibilitate', icon: 'card_membership' as const, color: '#8E24AA', route: '/membership-plans' as const },
  { title: 'Analiză acces membri', subtitle: 'Acces activ și activări estimate', icon: 'analytics_outlined' as const, color: '#00897B', route: '/membership-analytics' as const },
];

export default function AdminToolsScreen() {
  const { colors } = useAppTheme();
  return <ScrollView style={{ backgroundColor: colors.surfaceContainerLowest }} contentContainerStyle={styles.content}><Stack.Screen options={{ title: 'Administrare' }} /><AppText variant="headlineMedium" style={styles.title}>Instrumente Admin</AppText><AppText color={colors.onSurfaceVariant} style={styles.subtitle}>Ecranele operaționale și de configurare internă</AppText>{tools.map((tool) => <Pressable key={tool.route} onPress={() => router.push(tool.route)} style={({ pressed }) => [styles.card, { borderColor: colors.outlineVariant, opacity: pressed ? .68 : 1 }]}><View style={[styles.icon, { backgroundColor: colorWithAlpha(tool.color, .15) }]}><MaterialIcon name={tool.icon} size={26} color={tool.color} /></View><View style={styles.copy}><AppText variant="titleMedium" style={styles.cardTitle}>{tool.title}</AppText><AppText variant="bodySmall" color={colors.onSurfaceVariant} style={styles.cardSubtitle}>{tool.subtitle}</AppText></View><MaterialIcon name="chevron_right" size={24} color={colors.onSurfaceVariant} /></Pressable>)}</ScrollView>;
}

const styles = StyleSheet.create({ content: { padding: 16, paddingBottom: 28 }, title: { fontWeight: '700' }, subtitle: { marginTop: 4, marginBottom: 20 }, card: { minHeight: 82, borderWidth: StyleSheet.hairlineWidth, borderRadius: 14, flexDirection: 'row', alignItems: 'center', padding: 14, marginBottom: 12 }, icon: { width: 50, height: 50, borderRadius: 12, alignItems: 'center', justifyContent: 'center' }, copy: { flex: 1, marginLeft: 14, marginRight: 8 }, cardTitle: { fontWeight: '700' }, cardSubtitle: { marginTop: 3 } });
