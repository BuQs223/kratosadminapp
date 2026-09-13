import { parseFlutterDate } from '@/utils/flutter-date';
import { flutterNumber, type JsonRecord } from '@/utils/parsing';

const header = 'Data,Membru,Sumă (RON),Metodă Plată,Sală,Plan Abonament,Note,Înregistrat de,Status,Șters la,Șters de';
function escape(value: unknown): string {
  const text = value == null ? '' : String(value);
  return /[,"\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}
function dateLabel(value: unknown): string {
  if (value == null) return '';
  const date = parseFlutterDate(String(value));
  const pad = (number: number) => String(number).padStart(2, '0');
  return `${pad(date.getDate())}/${pad(date.getMonth() + 1)}/${date.getFullYear()} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
export function revenueCsv(rows: JsonRecord[]): string {
  const lines = rows.map((row) => {
    const deleted = typeof row.is_deleted === 'number' ? row.is_deleted !== 0 : row.is_deleted === true || row.is_deleted === '1' || String(row.is_deleted).toLowerCase() === 'true';
    return [dateLabel(row.paid_at), escape(row.profile_full_name ?? 'Necunoscut'), (flutterNumber(row.amount_cents) / 100).toFixed(2), String(row.payment_method ?? ''), escape(row.gym_name), escape(row.plan_name), escape(row.notes), escape(row.recorded_by_full_name), deleted ? 'Șters' : 'Activ', escape(dateLabel(row.deleted_at)), escape(row.deleted_by_full_name)].join(',');
  });
  // StringBuffer.writeln in Flutter includes the final newline as well as the BOM.
  return `\uFEFF${[header, ...lines].join('\n')}\n`;
}
