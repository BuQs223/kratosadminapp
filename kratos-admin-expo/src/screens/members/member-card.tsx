import { LinearGradient } from 'expo-linear-gradient';
import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { AppText } from '@/components/app-text';
import { MaterialIcon } from '@/components/material-icon';
import type { MemberWithDetails } from '@/repositories/members-repository';
import { colorWithAlpha, useAppTheme } from '@/theme/theme';

const statusStyles: Record<string, { background: string; foreground: string; emoji: string }> = {
  Activ: { background: '#C8E6C9', foreground: '#2E7D32', emoji: '✅' },
  'Expiră în curând': { background: '#FFE0B2', foreground: '#EF6C00', emoji: '⚠️' },
  Expirat: { background: '#FFCDD2', foreground: '#C62828', emoji: '❌' },
  Anulat: { background: '#E1BEE7', foreground: '#6A1B9A', emoji: '🚫' },
  Inactiv: { background: '#F5F5F5', foreground: '#424242', emoji: '⏸️' },
  'Niciun abonament': { background: '#F5F5F5', foreground: '#424242', emoji: '⏸️' },
};

const fallbackStatus = { background: '#00000000', foreground: '#757575', emoji: '❓' };

function shortDate(date: Date): string {
  const day = String(date.getDate()).padStart(2, '0');
  const month = String(date.getMonth() + 1).padStart(2, '0');
  return `${day}/${month}/${date.getFullYear()}`;
}

export function MemberCard({ member, onPress }: { member: MemberWithDetails; onPress: () => void }) {
  const { colors } = useAppTheme();
  const status = statusStyles[member.membershipStatus] ?? fallbackStatus;
  const initial = member.profile.fullName ? Array.from(member.profile.fullName)[0]?.toUpperCase() : '?';

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Deschide ${member.profile.fullName}`}
      onPress={onPress}
      style={({ pressed }) => [
        styles.card,
        { borderColor: colors.outlineVariant, opacity: pressed ? 0.82 : 1 },
      ]}>
      <LinearGradient
        colors={[
          colorWithAlpha(status.background, 0.05),
          colorWithAlpha(status.background, 0.02),
        ]}
        start={{ x: 0, y: 0 }}
        end={{ x: 1, y: 1 }}
        style={StyleSheet.absoluteFill}
      />
      <View style={styles.content}>
        <View style={styles.header}>
          <LinearGradient
            colors={[colorWithAlpha(colors.primary, 0.2), colorWithAlpha(colors.primary, 0.1)]}
            start={{ x: 0, y: 0 }}
            end={{ x: 1, y: 1 }}
            style={styles.avatar}>
            <AppText color={colors.primary} style={styles.initial}>
              {initial}
            </AppText>
          </LinearGradient>
          <View style={styles.nameColumn}>
            <AppText numberOfLines={1} variant="titleMedium" style={styles.name}>
              {member.profile.fullName}
            </AppText>
            <View style={[styles.statusBadge, { backgroundColor: colorWithAlpha(status.background, 0.15) }]}>
              <AppText style={styles.statusEmoji}>{status.emoji}</AppText>
              <AppText color={status.foreground} style={styles.statusText}>
                {member.membershipStatus || 'Necunoscut'}
              </AppText>
            </View>
          </View>
          <MaterialIcon name="chevron_right_rounded" size={24} color={colors.onSurfaceVariant} />
        </View>

        {member.profile.isAdmin || member.profile.isEmployee ? (
          <View style={styles.roles}>
            {member.profile.isAdmin ? (
              <RoleBadge emoji="👑" label="ADMIN" color="#FF9800" borderColor="#FF98004D" />
            ) : null}
            {member.profile.isEmployee ? (
              <RoleBadge emoji="💼" label="ANGAJAT" color="#2196F3" borderColor="#2196F31A" />
            ) : null}
          </View>
        ) : null}

        {member.membershipPlan ? (
          <View
            style={[
              styles.infoBox,
              {
                backgroundColor: colorWithAlpha(colors.surfaceContainerHighest, 0.2),
                borderColor: colorWithAlpha(colors.outlineVariant, 0.5),
              },
            ]}>
            <View style={[styles.planIcon, { backgroundColor: colorWithAlpha(colors.primary, 0.075) }]}>
              <AppText style={styles.infoEmoji}>💳</AppText>
            </View>
            <View style={styles.infoCopy}>
              <AppText numberOfLines={1} style={styles.planName}>
                {member.membershipPlan}
              </AppText>
              {member.membershipExpiry ? (
                <View style={styles.inline}>
                  <AppText style={styles.tinyEmoji}>⏰</AppText>
                  <AppText variant="bodySmall" color={colors.onSurfaceVariant}>
                    Expiră: {shortDate(member.membershipExpiry)}
                  </AppText>
                </View>
              ) : null}
            </View>
          </View>
        ) : null}

        <View
          style={[
            styles.infoBox,
            styles.visits,
            {
              backgroundColor: colorWithAlpha(colors.surfaceContainerHighest, 0.2),
              borderColor: colorWithAlpha(colors.outlineVariant, 0.5),
            },
          ]}>
          <InfoCell
            emoji={member.lastCheckIn ? '✅' : '⏸️'}
            label="Ultima vizită"
            value={member.lastCheckIn ? shortDate(member.lastCheckIn) : 'Niciodată'}
          />
          <View style={[styles.divider, { backgroundColor: colorWithAlpha(colors.outline, 0.2) }]} />
          <InfoCell emoji="📅" label="Membru din" value={shortDate(member.profile.createdAt)} />
        </View>
      </View>
    </Pressable>
  );
}

function RoleBadge({ emoji, label, color, borderColor }: { emoji: string; label: string; color: string; borderColor: string }) {
  const { colors } = useAppTheme();
  return (
    <View
      style={[
        styles.roleBadge,
        { backgroundColor: colorWithAlpha(colors.secondary, 0.1), borderColor },
      ]}>
      <AppText style={styles.roleEmoji}>{emoji}</AppText>
      <AppText color={color} style={styles.roleText}>
        {label}
      </AppText>
    </View>
  );
}

function InfoCell({ emoji, label, value }: { emoji: string; label: string; value: string }) {
  const { colors } = useAppTheme();
  return (
    <View style={styles.infoCell}>
      <AppText style={styles.infoEmoji}>{emoji}</AppText>
      <View style={styles.infoCopy}>
        <AppText color={colors.onSurfaceVariant} style={styles.infoLabel}>
          {label}
        </AppText>
        <AppText numberOfLines={1} style={styles.infoValue}>
          {value}
        </AppText>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    marginBottom: 12,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: 16,
    borderCurve: 'continuous',
    overflow: 'hidden',
  },
  content: { padding: 16 },
  header: { flexDirection: 'row', alignItems: 'center' },
  avatar: {
    width: 56,
    height: 56,
    borderRadius: 16,
    borderCurve: 'continuous',
    alignItems: 'center',
    justifyContent: 'center',
  },
  initial: { fontWeight: '700', fontSize: 24, lineHeight: 32 },
  nameColumn: { flex: 1, alignItems: 'flex-start', marginLeft: 12 },
  name: { fontWeight: '700', fontSize: 16, lineHeight: 24 },
  statusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 8,
    borderCurve: 'continuous',
    marginTop: 4,
  },
  statusEmoji: { fontSize: 12, lineHeight: 16 },
  statusText: { fontSize: 11, lineHeight: 16, fontWeight: '700', marginLeft: 4 },
  roles: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: 12 },
  roleBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderWidth: 1,
    borderRadius: 8,
    borderCurve: 'continuous',
  },
  roleEmoji: { fontSize: 12, lineHeight: 16 },
  roleText: { fontSize: 11, lineHeight: 16, fontWeight: '700', marginLeft: 4 },
  infoBox: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 12,
    borderRadius: 12,
    borderCurve: 'continuous',
    borderWidth: StyleSheet.hairlineWidth,
    marginTop: 12,
  },
  planIcon: { padding: 8, borderRadius: 8, borderCurve: 'continuous' },
  infoEmoji: { fontSize: 16, lineHeight: 24 },
  tinyEmoji: { fontSize: 10, lineHeight: 16, marginRight: 4 },
  infoCopy: { flex: 1, marginLeft: 8 },
  planName: { fontSize: 14, lineHeight: 20, fontWeight: '600' },
  inline: { flexDirection: 'row', alignItems: 'center', marginTop: 2 },
  visits: { marginTop: 12 },
  infoCell: { flex: 1, flexDirection: 'row', alignItems: 'center' },
  divider: { width: 1, height: 32, marginHorizontal: 12 },
  infoLabel: { fontSize: 10, lineHeight: 14 },
  infoValue: { fontSize: 13, lineHeight: 18, fontWeight: '600' },
});
