import { router } from 'expo-router';
import React from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Pressable,
  ScrollView,
  View,
} from 'react-native';

import { AppText } from '@/components/app-text';
import { MaterialIcon } from '@/components/material-icon';
import { OutlinedTextField } from '@/components/outlined-text-field';
import { authService } from '@/services/auth-service';
import { useAppTheme } from '@/theme/theme';

export default function LoginScreen() {
  const { colors } = useAppTheme();
  const [email, setEmail] = React.useState('');
  const [password, setPassword] = React.useState('');
  const [obscurePassword, setObscurePassword] = React.useState(true);
  const [isLoading, setIsLoading] = React.useState(false);
  const [errors, setErrors] = React.useState<{ email?: string; password?: string; form?: string }>({});

  const signIn = async () => {
    const nextErrors: typeof errors = {};
    if (!email) nextErrors.email = 'Vă rugăm introduceți email-ul';
    else if (!email.includes('@')) nextErrors.email = 'Email invalid';
    if (!password) nextErrors.password = 'Vă rugăm introduceți parola';
    else if (password.length < 6) nextErrors.password = 'Parola trebuie să aibă cel puțin 6 caractere';
    setErrors(nextErrors);
    if (Object.keys(nextErrors).length) return;

    setIsLoading(true);
    try {
      await authService.signIn(email.trim(), password);
      router.replace('/(tabs)/dashboard');
    } catch (error) {
      setErrors({ form: `Eroare: ${error instanceof Error ? error.message : String(error)}` });
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <KeyboardAvoidingView
      behavior={process.env.EXPO_OS === 'ios' ? 'padding' : undefined}
      style={{ flex: 1, backgroundColor: colors.surface }}>
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ flexGrow: 1, justifyContent: 'center', padding: 24 }}>
        <View style={{ alignItems: 'center' }}>
          <MaterialIcon name="fitness_center" size={80} color={colors.primary} />
          <AppText variant="headlineMedium" style={{ fontWeight: '700', marginTop: 24 }}>
            Kratos Gym
          </AppText>
          <AppText variant="bodyLarge" color={colors.onSurfaceVariant} style={{ marginTop: 8 }}>
            Panou de Administrare
          </AppText>
        </View>

        <View style={{ gap: 16, marginTop: 48 }}>
          <OutlinedTextField
            label="Email"
            icon="email_outlined"
            value={email}
            error={errors.email}
            keyboardType="email-address"
            autoCapitalize="none"
            autoComplete="email"
            onChangeText={(value) => {
              setEmail(value);
              if (errors.email || errors.form) setErrors({ ...errors, email: undefined, form: undefined });
            }}
          />
          <OutlinedTextField
            label="Parolă"
            icon="lock_outlined"
            suffixIcon={obscurePassword ? 'visibility_outlined' : 'visibility_off_outlined'}
            onSuffixPress={() => setObscurePassword((value) => !value)}
            value={password}
            error={errors.password}
            secureTextEntry={obscurePassword}
            autoCapitalize="none"
            autoComplete="current-password"
            onSubmitEditing={() => void signIn()}
            onChangeText={(value) => {
              setPassword(value);
              if (errors.password || errors.form) setErrors({ ...errors, password: undefined, form: undefined });
            }}
          />
          {errors.form ? (
            <AppText selectable color={colors.error} style={{ textAlign: 'center' }}>
              {errors.form}
            </AppText>
          ) : null}
          <Pressable
            accessibilityRole="button"
            disabled={isLoading}
            onPress={() => void signIn()}
            style={({ pressed }) => ({
              minHeight: 52,
              marginTop: 8,
              borderRadius: 24,
              borderCurve: 'continuous',
              backgroundColor: isLoading ? colors.surfaceContainerHighest : colors.primary,
              alignItems: 'center',
              justifyContent: 'center',
              opacity: pressed ? 0.82 : 1,
              padding: 16,
            })}>
            {isLoading ? (
              <ActivityIndicator color={colors.onPrimary} />
            ) : (
              <AppText variant="titleSmall" color={colors.onPrimary}>
                Autentificare
              </AppText>
            )}
          </Pressable>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
