import {
  asBoolean,
  asDate,
  asInteger,
  asRecord,
} from '@/utils/parsing';

export type MembershipTrendRange = '7d' | '30d' | '12w' | '12m';

export type MembershipTrendMetric = 'activeAccess' | 'newActivations';

export interface MembershipTrendPoint {
  periodStart: Date;
  periodEnd: Date;
  activePeople: number;
  newActivations: number;
  isEstimated: boolean;
  computedAt: Date;
}

export function parseMembershipTrendPoint(value: unknown): MembershipTrendPoint {
  const row = asRecord(value);
  return {
    periodStart: asDate(row.period_start),
    periodEnd: asDate(row.period_end),
    activePeople: asInteger(row.active_people),
    newActivations: asInteger(row.new_activations),
    isEstimated: asBoolean(row.is_estimated),
    computedAt: asDate(row.computed_at),
  };
}
