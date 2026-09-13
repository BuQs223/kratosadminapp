import { ActivityIndicator, Pressable, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppText } from '@/components/app-text';
import { MaterialIcon } from '@/components/material-icon';
import type { SyncDisplayState } from '@/providers/sync-status-provider';
import { useAppTheme } from '@/theme/theme';
import { calendarDateFromLocalDate, formatCalendarDate } from '@/utils/calendar-date';

interface SyncLaunchScreenProps {
  state: SyncDisplayState;
  isRetrying: boolean;
  onRetry: () => void;
  onContinueWithCachedData: () => void;
}

function lastSyncLabel(value?: Date): string {
  if (!value) return 'Nu există încă o sincronizare reușită.';
  const hour = String(value.getHours()).padStart(2, '0');
  const minute = String(value.getMinutes()).padStart(2, '0');
  return `${formatCalendarDate(calendarDateFromLocalDate(value))}, ${hour}:${minute}`;
}

function syncCopy(state: SyncDisplayState) {
  switch (state.kind) {
    case 'downloading': {
      const percentage = state.fraction === undefined ? undefined : Math.round(state.fraction * 100);
      return {
        title: 'Actualizăm datele',
        detail: percentage === undefined ? 'Descărcăm ultimele modificări…' : `${percentage}% descărcat`,
        progress: percentage,
      };
    }
    case 'complete':
      return { title: 'Sincronizare finalizată', detail: 'Datele locale sunt actualizate.', progress: 100 };
    case 'offline':
      return { title: 'Fără conexiune la internet', detail: 'Nu putem actualiza datele acum.' };
    case 'error':
      return { title: 'Sincronizarea nu a reușit', detail: 'Verifică conexiunea și încearcă din nou.' };
    case 'connecting':
    case 'hidden':
      return { title: 'Conectare securizată', detail: 'Pregătim datele tale locale.' };
  }
}

export function SyncLaunchScreen({ state, isRetrying, onRetry, onContinueWithCachedData }: SyncLaunchScreenProps) {
  const { colors } = useAppTheme();
  const insets = useSafeAreaInsets();
  const copy = syncCopy(state);
  const needsDecision = state.kind === 'offline' || state.kind === 'error';
  const fraction = state.kind === 'downloading' ? state.fraction : state.kind === 'complete' ? 1 : undefined;
  const percentage = copy.progress;
  const progressWidth: `${number}%` = fraction === undefined ? '28%' : `${Math.max(6, Math.min(100, fraction * 100))}%`;
  const lastSuccessfulAt = needsDecision ? state.lastSuccessfulAt : undefined;

  return (
    <View style={[styles.screen, { backgroundColor: colors.surface, paddingTop: insets.top + 32, paddingBottom: Math.max(insets.bottom + 24, 36) }]}>
      <View style={styles.content}>
        <View style={styles.brandCopy}>
          <AppText variant="headlineMedium" style={styles.brandName}>Kratos Admin</AppText>
          <AppText color={colors.onSurfaceVariant} style={styles.intro}>Îți pregătim spațiul de lucru.</AppText>
        </View>

        <View style={[styles.statusCard, { backgroundColor: colors.surfaceContainer }]}>
          <View style={styles.statusHeader}>
            <View style={styles.statusIndicator}>
              {needsDecision ? (
                <MaterialIcon name="error_outline" size={26} color={state.kind === 'error' ? colors.error : colors.onSurfaceVariant} />
              ) : state.kind === 'complete' ? (
                <MaterialIcon name="check_circle" size={26} color={colors.primary} />
              ) : (
                <ActivityIndicator size="small" color={colors.primary} />
              )}
            </View>
            <View style={styles.statusCopy}>
              <AppText variant="titleLarge" style={styles.statusTitle}>{copy.title}</AppText>
              <AppText color={colors.onSurfaceVariant} style={styles.statusDetail}>{copy.detail}</AppText>
            </View>
          </View>

          {!needsDecision ? (
            <View
              accessibilityLiveRegion="polite"
              accessibilityRole="progressbar"
              accessibilityValue={percentage === undefined ? { text: copy.title } : { min: 0, max: 100, now: percentage, text: copy.detail }}>
              <View style={[styles.progressTrack, { backgroundColor: colors.surfaceContainerHighest }]}>
                <View style={[styles.progressFill, { width: progressWidth, backgroundColor: colors.primary }]} />
              </View>
            </View>
          ) : (
            <View style={[styles.offlineNotice, { backgroundColor: state.kind === 'error' ? colors.errorContainer : colors.surfaceContainerHighest }]}>
              <AppText color={state.kind === 'error' ? colors.onErrorContainer : colors.onSurface} style={styles.offlineNoticeTitle}>Ultima sincronizare reușită</AppText>
              <AppText color={state.kind === 'error' ? colors.onErrorContainer : colors.onSurfaceVariant} style={styles.offlineNoticeCopy}>{lastSyncLabel(lastSuccessfulAt)}</AppText>
              <AppText color={state.kind === 'error' ? colors.onErrorContainer : colors.onSurfaceVariant} style={styles.offlineNoticeCopy}>Datele afișate pot fi neactualizate.</AppText>
              {state.kind === 'error' ? <AppText selectable color={colors.onErrorContainer} style={styles.errorDetail}>Detalii: {state.message}</AppText> : null}
            </View>
          )}

          {needsDecision ? (
            <View style={styles.actions}>
              <Pressable
                accessibilityRole="button"
                disabled={isRetrying}
                onPress={onRetry}
                style={({ pressed }) => [styles.retryButton, { backgroundColor: colors.primary, opacity: pressed || isRetrying ? 0.65 : 1 }]}>
                {isRetrying ? <ActivityIndicator size="small" color={colors.onPrimary} /> : <MaterialIcon name="refresh" size={20} color={colors.onPrimary} />}
                <AppText color={colors.onPrimary} style={styles.retryText}>{isRetrying ? 'Se reconectează…' : 'Reîncearcă'}</AppText>
              </Pressable>
              <Pressable
                accessibilityRole="button"
                onPress={onContinueWithCachedData}
                style={({ pressed }) => [styles.continueButton, { borderColor: colors.outline, opacity: pressed ? 0.65 : 1 }]}>
                <AppText color={colors.primary} style={styles.continueText}>Deschide datele salvate</AppText>
              </Pressable>
            </View>
          ) : null}
        </View>
      </View>

      {!needsDecision ? <AppText color={colors.onSurfaceVariant} style={styles.footer}>Prima sincronizare poate dura puțin mai mult.</AppText> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, paddingHorizontal: 24, justifyContent: 'space-between' },
  content: { flex: 1, justifyContent: 'center', maxWidth: 480, width: '100%', alignSelf: 'center', paddingBottom: 104 },
  brandCopy: { alignItems: 'center' },
  brandName: { fontWeight: '700', letterSpacing: -0.4, textAlign: 'center' },
  intro: { fontSize: 16, lineHeight: 24, marginTop: 4, textAlign: 'center' },
  statusCard: { borderRadius: 24, borderCurve: 'continuous', padding: 18, marginTop: 28, gap: 20, boxShadow: '0 8px 24px rgba(0, 0, 0, 0.16)' },
  statusHeader: { flexDirection: 'row', alignItems: 'center' },
  statusIndicator: { width: 26, alignItems: 'center', justifyContent: 'center' },
  statusCopy: { flex: 1, marginLeft: 10 },
  statusTitle: { fontWeight: '700' },
  statusDetail: { marginTop: 3, fontSize: 14, lineHeight: 20 },
  progressTrack: { height: 8, borderRadius: 4, overflow: 'hidden' },
  progressFill: { height: '100%', minWidth: 22, borderRadius: 4 },
  offlineNotice: { borderRadius: 18, borderCurve: 'continuous', padding: 14, gap: 4 },
  offlineNoticeTitle: { fontSize: 13, lineHeight: 18, fontWeight: '700' },
  offlineNoticeCopy: { fontSize: 13, lineHeight: 18 },
  errorDetail: { marginTop: 6, fontSize: 12, lineHeight: 17 },
  actions: { gap: 10 },
  retryButton: { minHeight: 52, borderRadius: 26, flexDirection: 'row', alignItems: 'center', justifyContent: 'center' },
  retryText: { marginLeft: 8, fontSize: 16, lineHeight: 22, fontWeight: '700' },
  continueButton: { minHeight: 52, borderWidth: 1, borderRadius: 26, alignItems: 'center', justifyContent: 'center' },
  continueText: { fontSize: 15, lineHeight: 22, fontWeight: '700' },
  footer: { alignSelf: 'center', textAlign: 'center', fontSize: 13, lineHeight: 18 },
});
