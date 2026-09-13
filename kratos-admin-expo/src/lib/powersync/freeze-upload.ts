import type { CrudEntry } from '@powersync/react-native';

/** Only the new freeze workflow writes locally; existing admin mutations stay online. */
const columns: Record<string, readonly string[]> = {
  memberships: ['is_frozen', 'frozen_at', 'frozen_by_user_id', 'days_left_when_frozen', 'freeze_type', 'auto_unfreeze_at', 'updated_at', 'end_date', 'days_left'],
  membership_events: ['membership_id', 'event_type', 'at', 'by_user', 'notes', 'delta_days', 'old_start_date', 'old_end_date', 'new_end_date', 'plan_id'],
  membership_freeze_schedules: ['membership_id', 'duration_days', 'freeze_type', 'scheduled_start_date', 'status', 'created_by_user_id', 'canceled_by_user_id', 'canceled_at', 'notes', 'created_at', 'updated_at'],
};

export function freezeUploadPayload(op: Pick<CrudEntry, 'table' | 'op' | 'opData'>): Record<string, unknown> {
  const allowed = columns[op.table];
  const supported = (op.table === 'memberships' && op.op === 'PATCH')
    || (op.table === 'membership_events' && op.op === 'PUT')
    || (op.table === 'membership_freeze_schedules' && (op.op === 'PUT' || op.op === 'PATCH'));
  if (!supported || !op.opData || Object.keys(op.opData).some((key) => !allowed.includes(key))) {
    throw new Error(`Unsupported local write: ${op.table} ${op.op}`);
  }
  const payload: Record<string, unknown> = { ...op.opData };
  // Explicit nulls clear freeze metadata on resume and must survive uploading.
  if ('is_frozen' in payload) payload.is_frozen = payload.is_frozen === 1 || payload.is_frozen === true;
  return payload;
}
