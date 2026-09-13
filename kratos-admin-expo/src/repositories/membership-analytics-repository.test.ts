import { describe, expect, jest, test } from '@jest/globals';
import { getMembershipAccessTrend } from '@/repositories/membership-analytics-repository';

const mockRpc = jest.fn<(...args: unknown[]) => Promise<unknown>>();

jest.mock('@/lib/supabase/client', () => ({
  getSupabase: () => ({ rpc: mockRpc }),
}));

describe('membership analytics repository', () => {
  test('passes the selected range and optional selling gym to the RPC', async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        {
          period_start: '2026-08-01',
          period_end: '2026-08-01',
          active_people: 876,
          new_activations: 7,
          is_estimated: false,
          computed_at: '2026-08-02T00:15:00.000Z',
        },
      ],
      error: null,
    });

    const result = await getMembershipAccessTrend({ range: '30d', gymId: 'gym-1' });

    expect(mockRpc).toHaveBeenCalledWith('get_admin_membership_access_trend', {
      p_range: '30d',
      p_gym_id: 'gym-1',
    });
    expect(result[0]).toMatchObject({ activePeople: 876, newActivations: 7 });
  });

  test('uses null for the all-gyms scope and rethrows the Supabase error', async () => {
    const error = new Error('Admin access required');
    mockRpc.mockResolvedValueOnce({ data: null, error });

    await expect(getMembershipAccessTrend({ range: '7d' })).rejects.toThrow(error);
    expect(mockRpc).toHaveBeenLastCalledWith('get_admin_membership_access_trend', {
      p_range: '7d',
      p_gym_id: null,
    });
  });
});
