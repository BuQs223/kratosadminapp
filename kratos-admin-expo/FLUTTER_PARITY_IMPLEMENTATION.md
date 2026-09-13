# Flutter data/report parity implementation

Implemented against the clean `65c476d` baseline, using the active Flutter code as the reference. Flutter, database migrations and production data were not modified. The earlier `FLUTTER_EXPO_REPORT_LOGIC_AUDIT.md` describes the pre-change behavior.

The Expo changes cover the shared Dashboard, Members, member details/history/revenue, Check-ins, Check-in Statistics, Gold/Silver report, Revenue list/CSV/analytics, Period Comparison, and membership/plan editing paths.

| Area | Behavior now aligned to Flutter |
| --- | --- |
| Revenue selection | Default/all includes deleted charges; active/deleted filters are distinct. Dashboard and period comparison include deleted charges; analytics and today comparison exclude them. Existing source, payment, plan and unique-member definitions are preserved. |
| Date queries | Local offset-free DateTime bounds, inclusive/exclusive endpoints per report, UTC SQLite chart/Gold buckets, rolling analytics timestamps, captured check-in cutoffs, and elapsed-duration DST behavior. Revenue Today and rolling analytics recompute their windows on reload. |
| Pickers | Membership maximum January 1, 2030; start-date end adjustment by 30 elapsed days; custom comparison end clamping; range-bound validation; cancel keeps the previous applied check-in preset. |
| Date display/models | Dart-style date-only/local/UTC parsing and serialization, including microseconds; UTC profile/member dates; local revenue/event timestamps; elapsed expiry fallback; invalid dates/numbers reject or skip rows where Flutter does. Weekly chart labels retain their dates west of UTC. |
| Members | Latest end-date membership selection; active means more than seven days; expiring means zero through seven; inactive means no membership; canceled filter remains Flutter's no-op. Frozen, registration and check-in predicates retain Flutter semantics. |
| Gold/Silver | UTC-date successful visits; combined K1/K2 Gold figure sums the two per-gym distinct-member counts. |
| Membership writes | Flutter's sequential direct writes, server-assigned membership IDs, ledger updates only on price changes, matching ledger-row lookup/update fields, retry and partial-failure behavior, and deletion order. |
| Plan/amount forms | Dart full-input decimal parsing, membership/revenue rounding, plan-cent truncation, original plan names/tier values, duration validation, date payloads, and direct server gym choices loaded when opening the plan form. |
| Display/CSV | Matching chart smoothing/padding and comparison-bar proportions; no fabricated one-cent donut total; raw-row CSV export, BOM/escaping/final newline; selected-profile snapshots on member navigation. |
| Reloads | Explicit report reloads instead of replication-triggered invalidation; no first-sync gate; no automatic query retries; first-page list refresh; tab-switch filter reset; prior successful report retained on failed loads. |

Intentional compatibility includes Flutter's existing inconsistencies: a deleted charge can count in one report and not another; canceled/frozen memberships can pass certain member filters; one Gold visitor can count in both gyms; and membership/ledger writes are not atomic. Same-price plan/payment/gym edits leave the ledger unchanged. These were retained to meet the requested Flutter behavior, not redefined as new business rules.

Validation:

- 157 parity cases passed. The SQLite harness runs the real Expo repositories against synthetic in-memory data and compares Flutter SQL templates/results. A Dart executable checks date/number operations in Europe/Bucharest, UTC and America/Los_Angeles, including DST gaps/folds and year boundaries.
- 37 Jest tests passed across 15 suites, including write ordering/failures/retries, parsing, CSV, page-one refresh, preserved report snapshots and tab return behavior.
- TypeScript and ESLint passed; iOS and Android production JavaScript/Hermes bundles exported successfully.
- No live write was performed to test these changes.

Run `npm run test:parity` from `kratos-admin-expo` with Node 22+ and Dart on PATH. Set `DART` to a Dart SDK executable when necessary; `-- --full` prints both sides of every comparison. Results are recorded in `audits/2026-09-13-report-parity/parity-results.json`. The older `verify.cjs` is a historical pre-fix mismatch harness, not the parity regression command.

These checks establish deterministic logic parity for the covered inputs. They do not establish identical native-screen behavior under every interaction or identical live PowerSync snapshots. Different replication progress, backend triggers/permissions, clocks and asynchronous completion order can still affect what two running devices display. Expo retains request-key isolation rather than reproducing Flutter's stale-response races; error notices and native picker presentation remain platform-specific. Flutter-only Performance/Products reports and Expo-only membership-access analytics were not ported or redefined.
