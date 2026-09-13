/** Dart double.tryParse consumes the entire input and does not accept decimal commas. */
export function parseFlutterDouble(input: string): number | null {
  const text = input.trim();
  if (!/^[+-]?(?:(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?|Infinity|NaN)$/.test(text)) return null;
  return Number(text);
}
export function flutterRound(value: number): number {
  if (!Number.isFinite(value)) throw new Error('Cannot round a non-finite number');
  return value < 0 ? -Math.round(-value) : Math.round(value);
}
export function parseFlutterInt(input: string): number | null {
  const text = input.trim();
  return /^[+-]?\d+$/.test(text) ? Number(text) : null;
}
