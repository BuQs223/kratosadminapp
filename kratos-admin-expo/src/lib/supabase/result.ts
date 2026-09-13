import type { PostgrestError } from '@supabase/supabase-js';

export function unwrapSupabase<T>(result: { data: T | null; error: PostgrestError | null }): T {
  if (result.error) throw result.error;
  if (result.data === null) throw new Error('Supabase returned no data.');
  return result.data;
}

export function unwrapNullableSupabase<T>(result: {
  data: T | null;
  error: PostgrestError | null;
}): T | null {
  if (result.error) throw result.error;
  return result.data;
}
