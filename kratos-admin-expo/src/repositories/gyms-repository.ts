import { getSupabase } from '@/lib/supabase/client';
import { parseGym, type Gym } from '@/models/gym';
import { asRecords } from '@/utils/parsing';

export async function getGyms(): Promise<Gym[]> {
  const { data, error } = await getSupabase().from('gyms').select().order('name');
  if (error) throw error;
  return asRecords(data).map(parseGym);
}
