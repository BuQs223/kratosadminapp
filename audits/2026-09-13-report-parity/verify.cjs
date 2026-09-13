// Read-only audit harness. Runs real Expo repositories against in-memory SQLite;
// extracts Flutter SQL where possible. Never connects to Supabase or PowerSync.
// Run with Node >=22 and the existing Expo node_modules: node audits/2026-09-13-report-parity/verify.cjs
process.env.TZ = 'Europe/Bucharest';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { DatabaseSync } = require('node:sqlite');
const root = path.resolve(__dirname, '../..');
const ts = require(path.join(root, 'kratos-admin-expo/node_modules/typescript'));
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const db = new DatabaseSync(':memory:');
const tables = {};
for (const match of read('lib/models/powersync_schema.dart').matchAll(/Table\(\s*'([^']+)',\s*\[([\s\S]*?)\]/g)) {
  tables[match[1]] = Object.fromEntries([...match[2].matchAll(/Column\.(text|integer|real)\('([^']+)'\)/g)].map(m => [m[2], m[1]]));
  db.exec(`CREATE TABLE ${match[1]} (id TEXT PRIMARY KEY, ${Object.entries(tables[match[1]]).map(([name, type]) => `${name} ${type}`).join(', ')})`);
}
const adapter = {
  get: async (sql, params = []) => db.prepare(sql).get(...params),
  getOptional: async (sql, params = []) => db.prepare(sql).get(...params) ?? null,
  getAll: async (sql, params = []) => db.prepare(sql).all(...params),
};
const cache = {};
function load(id) {
  if (id === '@/lib/powersync/system') return { powerSync: adapter, connectPowerSyncIfAuthenticated: async () => {} };
  if (id === '@/lib/supabase/client') return { getSupabase: () => { throw new Error('Network access prohibited in audit'); } };
  if (cache[id]) return cache[id].exports;
  const file = `kratos-admin-expo/src/${id.slice(2)}.ts`;
  const code = ts.transpileModule(read(file), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const module = { exports: {} };
  cache[id] = module;
  new Function('require', 'module', 'exports', code)(load, module, module.exports);
  return module.exports;
}
const revenue = load('@/repositories/revenue-repository');
const members = load('@/repositories/members-repository');
const checkins = load('@/repositories/check-ins-repository');
const dashboard = load('@/repositories/dashboard-repository');
const calendar = load('@/utils/calendar-date');
const results = [];
function record(name, flutter, expo) { results.push({ name, flutter, expo }); }
function reset() { for (const table of Object.keys(tables)) db.exec(`DELETE FROM ${table}`); }
function insert(table, row) {
  const keys = Object.keys(row);
  db.prepare(`INSERT INTO ${table} (${keys.join(',')}) VALUES (${keys.map(() => '?').join(',')})`).run(...Object.values(row));
}
function charge(id, paid_at, amount_cents, extra = {}) {
  insert('revenue_ledger', { id, paid_at, created_at: paid_at, amount_cents, entry_kind: 'charge', is_deleted: 0, currency: 'RON', source: 'membership', payment_method: 'cash', ...extra });
}
function person(id, name = id) { insert('profiles', { id, full_name: name, created_at: '2026-01-01T12:00:00Z' }); }
function membership(id, user_id, extra = {}) {
  insert('memberships', { id, user_id, start_date: '2020-01-01', end_date: '2090-12-31', created_at: '2026-01-01', is_active: 1, is_frozen: 0, days_left: 100, ...extra });
}
const flutterMemberSource = read('lib/screens/members/members_screen.dart');
const flutterCte = flutterMemberSource.match(/String _membersBaseCte\(\)[\s\S]*?return '''([\s\S]*?)'''/)[1];
function flutterMembers(where = '', params = []) {
  return db.prepare(`${flutterCte} SELECT p.id, p.membership_id FROM member_rows p LEFT JOIN memberships m ON m.id = p.membership_id ${where}`).all(...params);
}
const flutterRevenue = read('lib/screens/revenue/revenue_screen.dart');
const flutterStatsTemplate = flutterRevenue.match(/String _revenueStatsSql[\s\S]*?return '''([\s\S]*?)'''/)[1];
function flutterTotal(where, params = []) {
  return db.prepare(flutterStatsTemplate.replace('$whereClause', where)).get(...params).total_revenue;
}
async function main() {
  // The complete replicated column inventory also matches.
  const expoSchema = read('kratos-admin-expo/src/lib/powersync/schema.ts');
  const expoTables = Object.fromEntries([...expoSchema.matchAll(/(\w+): new Table\(\s*\{([^}]+)\}/g)].map(m => [m[1], Object.fromEntries([...m[2].matchAll(/(\w+): column\.(text|integer|real)/g)].map(c => [c[1], c[2]]))]));
  assert.deepEqual(expoTables, tables);
  record('Replicated schema parity', Object.keys(tables).length, Object.keys(expoTables).length);

  reset();
  charge('local-sept-13', '2026-09-12T22:30:00Z', 10000);
  charge('local-sept-14', '2026-09-13T22:30:00Z', 20000);
  const fDate = flutterTotal("WHERE r.entry_kind = 'charge' AND datetime(r.paid_at) >= datetime(?) AND datetime(r.paid_at) <= datetime(?)", ['2026-09-13T00:00:00.000', '2026-09-13T23:59:59.999']);
  const eDate = (await revenue.getRevenuePage({ filters: { dateStart: '2026-09-13', dateEnd: '2026-09-13' } })).totalRevenueCents;
  assert.equal(fDate, 20000); assert.equal(eDate, 10000);
  record('Same September 13 date filter, cents', fDate, eDate);

  reset(); charge('live', '2026-09-13T12:00:00Z', 10000); charge('deleted', '2026-09-13T12:00:00Z', 5000, { is_deleted: 1 });
  const fAll = flutterTotal("WHERE r.entry_kind = 'charge'");
  const eAll = (await revenue.getRevenuePage({ filters: { deletedStatus: 'all' } })).totalRevenueCents;
  assert.equal(fAll, 15000); assert.equal(eAll, 10000);
  record('Default/all revenue includes deleted, cents', fAll, eAll);
  const ePeriod = await revenue.getRevenuePeriodStats({ start: '2026-09-01', end: '2026-09-30' });
  const eDashboard = await dashboard.getDashboardStats(new Date('2026-09-13T15:00:00+03:00'));
  assert.equal(ePeriod.totalRevenueCents, 10000); assert.equal(eDashboard.monthlyRevenue, 100);
  record('Deleted charge in period comparison/dashboard, cents', fAll, ePeriod.totalRevenueCents);

  reset(); charge('monday-local', '2026-09-13T22:30:00Z', 10000);
  const fWeek = db.prepare("SELECT date(paid_at, '-' || ((CAST(strftime('%w', paid_at) AS INTEGER) + 6) % 7) || ' days') AS period FROM revenue_ledger").get().period;
  const eWeek = (await revenue.getRevenueAnalytics({ startDate: '2026-09-01', endDate: '2026-09-30', trendInterval: 'week' })).trend[0].period;
  assert.equal(fWeek, '2026-09-07'); assert.equal(eWeek, '2026-09-14');
  record('Monday 01:30 local weekly bucket', fWeek, eWeek);

  reset(); person('u'); membership('soon', 'u', { days_left: 3 });
  const fActive = flutterMembers('WHERE m.id IS NOT NULL AND m.days_left > 7').length;
  const eActive = (await members.getMembersPage({ filters: { membershipStatus: 'active' } })).totalCount;
  assert.equal(fActive, 0); assert.equal(eActive, 1);
  record('Active filter: usable membership with 3 days left', fActive, eActive);
  db.exec('UPDATE memberships SET is_frozen=1, days_left=100');
  assert.equal((await members.getMembersPage({ filters: { membershipStatus: 'active' } })).totalCount, 0);
  record('Active filter: frozen membership with 100 days left', flutterMembers('WHERE m.id IS NOT NULL AND m.days_left > 7').length, 0);

  reset(); person('u'); membership('usable', 'u'); membership('future', 'u', { start_date: '2091-01-01', end_date: '2091-12-31' });
  const fChosen = flutterMembers()[0].membership_id;
  const eChosen = (await members.getMembersPage({})).items[0].membershipExpiry.getUTCFullYear();
  assert.equal(fChosen, 'future'); assert.equal(eChosen, 2090);
  record('Chosen membership with usable + future records', fChosen, 'usable');

  reset(); person('alice', 'Alice'); person('bob', 'Bob'); membership('bob-inactive', 'bob', { is_active: 0, sold_at_gym_id: 'wrong-gym' });
  const leaked = await members.getMembersPage({ filters: { search: 'Alice', gymId: 'selected-gym', membershipStatus: 'inactive' } });
  assert.deepEqual(leaked.items.map(m => m.profile.id), ['bob', 'alice']);
  const fLeak = flutterMembers("WHERE LOWER(p.full_name) LIKE '%alice%' AND m.sold_at_gym_id = 'selected-gym' AND m.id IS NULL");
  assert.equal(fLeak.length, 0);
  record('Inactive + Alice + selected gym (OR precedence)', [], leaked.items.map(m => m.profile.id));

  reset(); person('active'); person('canceled'); membership('a', 'active'); membership('b', 'canceled', { canceled_at: '2026-09-01T12:00:00Z' });
  const eCanceled = await members.getMembersPage({ filters: { membershipStatus: 'canceled' } });
  assert.equal(eCanceled.totalCount, 1);
  record('Canceled filter', flutterMembers().length, eCanceled.totalCount);

  reset(); insert('gyms', { id: 'g1', name: 'Kratos 1' }); insert('gyms', { id: 'g2', name: 'Kratos 2' });
  insert('membership_plans', { id: 'gold', name: 'Gold', tier: 'gold' }); membership('gold-m', 'u', { plan_id: 'gold' });
  for (const gym of ['g1', 'g2']) insert('check_ins', { id: gym, user_id: 'u', gym_id: gym, membership_id: 'gold-m', status: 'success', created_at: '2026-09-13T12:00:00Z' });
  const tier = await checkins.getGymTierCheckInStats('2026-09-13', '2026-09-13');
  const fCombined = tier.gyms.reduce((sum, g) => sum + g.uniqueGoldMembers, 0);
  assert.equal(fCombined, 2); assert.equal(tier.kratosOneAndTwoUniqueGoldMembers, 1);
  record('Same Gold person visits K1 and K2', fCombined, tier.kratosOneAndTwoUniqueGoldMembers);

  reset();
  for (let i = 0; i < 19; i++) insert('check_ins', { id: String(i), created_at: `2026-09-13T12:${String(i).padStart(2, '0')}:00Z` });
  for (let i = 0; i < 21; i++) insert('check_ins', { id: `missing-date-${i}`, created_at: null });
  const warn = console.warn;
  console.warn = () => {}; // Expected fixture parse failures contain only synthetic IDs.
  const malformed = await checkins.getCheckIns({ limit: 20, offset: 0 });
  assert.equal(malformed.items.length, 19); assert.equal(malformed.hasMore, true);
  const uiNextOffset = malformed.items.length; // The Expo screen sums parsed row counts.
  const secondMalformed = await checkins.getCheckIns({ limit: 20, offset: uiNextOffset });
  console.warn = warn;
  assert.equal(secondMalformed.items.length, 0); assert.equal(secondMalformed.hasMore, true);
  record('Malformed check-in page: hasMore', false, malformed.hasMore);
  record('19 valid + 21 missing timestamps: repeated Expo offset after second page', 'Flutter stops on first page', malformed.items.length + secondMalformed.items.length);

  reset(); insert('check_ins', { id: 'arrived-after-open', created_at: '2026-09-13T14:00:00Z' });
  const fRefresh = db.prepare('SELECT COUNT(*) AS count FROM check_ins c WHERE datetime(c.created_at) >= datetime(?) AND datetime(c.created_at) < datetime(?)').get('2026-09-13T00:00:00', '2026-09-13T10:00:01').count;
  const eRefresh = (await checkins.getCheckInStats({ start: '2026-09-13', end: '2026-09-13' })).totalCheckIns;
  assert.equal(fRefresh, 0); assert.equal(eRefresh, 1);
  record('Stats refresh after opening at 10:00, later check-in at 17:00 local', fRefresh, eRefresh);

  const model = load('@/models/membership');
  const eExpiry = model.membershipIsExpired(model.parseMembership({ end_date: '2026-09-13', days_left: null }), new Date('2026-09-13T12:00:00+03:00'));
  assert.equal(eExpiry, false);
  record('Model expiry fallback at noon on end date (SQL normally supplies days_left)', true, eExpiry);
  assert.equal(calendar.addCalendarDays('2026-10-25', 1), '2026-10-26');
  record('Calendar add day across autumn DST', 'See dart-probes.dart: +24h remains October 25', calendar.addCalendarDays('2026-10-25', 1));
  console.log(JSON.stringify({ timezone: process.env.TZ, checks: results.length, results }, null, 2));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
