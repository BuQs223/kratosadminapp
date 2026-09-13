# Kratos Gym Admin — Flutter vs React Native parity audit

Audit date: 2026-08-12  
Flutter source: repository root (`lib/`)  
React Native source: `kratos-admin-expo/`  

## Executive verdict

The React Native application does **not** match the Flutter application perfectly.

The port has strong structural coverage: the active core screens exist, the PowerSync schema is equivalent, the principal list/detail/analytics SQL is largely carried over, the native iOS development build succeeds, and the live admin authentication plus the new membership-access RPC work. However, there are several release-significant differences and defects:

1. The dashboard's “active” number has a different business definition in the two apps.
2. The Android custom date-range flow in Check-in Statistics cannot select an end date.
3. Gold check-in queries can be one calendar day early in Bucharest because the React Native port serializes local dates through UTC.
4. The shared membership-save flow is not transactional and can leave membership and revenue data inconsistent; changing plan/gym/payment without changing price does not update the ledger.
5. Deleted revenue is included in some totals but excluded from others.
6. The React Native “bottom sheet” is a fixed modal, not a functional equivalent of Flutter's draggable sheets.
7. The reachable Flutter Performance screen has not been ported.

This is therefore a high-coverage migration, not a pixel-perfect or behavior-perfect replacement.

## Severity model

- **P0** — destructive/security issue or app unusable. None found.
- **P1** — release blocker or materially wrong user/business result.
- **P2** — important parity, reliability, performance, or interaction defect.
- **P3** — polish, test coverage, dead-code, or minor consistency issue.

## Prioritized findings

### P1 — Dashboard access count has different semantics

Flutter counts an owner/family member when the membership is not canceled, is not frozen, and has non-negative `days_left`. It does not require a package plan, does not exclude day passes, and does not verify that the effective start date has arrived:

- `lib/screens/dashboard/dashboard_screen.dart:47-64`

React Native additionally:

- joins `membership_plans`;
- requires `plan_kind = 'package'`;
- excludes `day_pass`, `day-pass`, and `daily` membership types;
- requires `effective_start_date/start_date <= now`.

Source: `kratos-admin-expo/src/repositories/dashboard-repository.ts:29-54`.

The React Native label also changes from Flutter's “Abonamente Active” to “Persoane cu acces,” and opens a new analytics screen. This may be a deliberate correction, but it is not parity. The product needs one canonical definition and the Flutter number, React Native number, and backend RPC must use it.

Both definitions also ignore `is_active`. If that flag can be independently false, both may count an inactive membership as active.

### P1 — Android Check-in Statistics custom range cannot select an end date

Flutter uses one atomic `showDateRangePicker`, which returns start and end together:

- `lib/screens/check_ins/check_in_stats_screen.dart:117-153`

React Native starts editing `start`; on Android, the system picker callback closes the editor immediately. The control that opens the picker always reopens `start`, while the “Următorul” action that advances to `end` exists only on iOS:

- `kratos-admin-expo/src/app/check-in-stats.tsx:35-49`
- `kratos-admin-expo/src/app/check-in-stats.tsx:62-69`

Result: an Android admin can change the start while the end remains from the previous preset, but cannot deliberately choose the end. This needs an Android-specific two-step flow or a proper range picker.

### P1 — Gold check-ins can query the previous calendar day

React Native converts a local date with:

```ts
value.toISOString().slice(0, 10)
```

Source: `kratos-admin-expo/src/repositories/check-ins-repository.ts:169-188`.

In Europe/Bucharest, local midnight on 1 August serializes to 31 July UTC. The resulting SQLite `date(ci.created_at)` filter is therefore one day earlier. Flutter formats the selected local date directly as `yyyy-MM-dd`:

- `lib/screens/analytics/gold_checkins_screen.dart:63-85`

Date-only business values must not pass through UTC. Build `YYYY-MM-DD` from local components, and add tests in both UTC+2 and UTC+3.

### P1 — Membership and revenue writes are non-transactional and can diverge

Both apps perform separate direct Supabase requests:

1. insert/update `memberships`;
2. fetch the current user;
3. read `revenue_ledger`;
4. update or insert a ledger row.

React Native: `kratos-admin-expo/src/repositories/members-repository.ts:443-506`  
Flutter: `lib/widgets/membership_form_dialog.dart:93-186`

Consequences:

- a failure after step 1 leaves a membership change without the corresponding financial change;
- retries have no transaction-level idempotency;
- `.maybeSingle()` assumes at most one ledger row per membership and fails if duplicates exist;
- if plan, gym, or payment method changes but price does not, the code returns without updating the ledger;
- even when price changes, the existing ledger update omits `plan_id`, so a plan change can leave the old plan on the financial record.

This is a shared backend/data-integrity problem, not an RN-only regression. Move the operation into one database RPC/transaction with a clear unique rule for the membership charge and an idempotency key.

### P1 — Revenue totals disagree on whether soft-deleted charges count

The dashboard monthly total includes all charge rows, including `is_deleted = 1`:

- `kratos-admin-expo/src/repositories/dashboard-repository.ts:55-60`
- `lib/screens/dashboard/dashboard_screen.dart:65-72`

Period-comparison totals also omit an `is_deleted` predicate:

- `kratos-admin-expo/src/repositories/revenue-repository.ts:327-369`
- `lib/screens/revenue/period_comparison_screen.dart:141-205`

Other analytics paths explicitly use `COALESCE(is_deleted, 0) = 0`, for example:

- `kratos-admin-expo/src/repositories/revenue-repository.ts:203-244`
- `lib/screens/revenue/revenue_analytics_screen.dart:118`

An entry deleted by an admin therefore still changes some headline totals while disappearing from other totals. Define whether deleted entries are audit-only or financially active and apply that definition to every aggregate.

### P1 — Member status filters can show canceled/frozen memberships as “active”

In both apps, `active`, `expiring`, and `expired` are based only on `days_left`; they do not exclude canceled memberships, frozen memberships, day passes, or a future start date:

- `kratos-admin-expo/src/repositories/members-repository.ts:109-125`
- `lib/screens/members/members_screen.dart:268-281`

A canceled long-running membership can appear in the Active result even though its card is rendered as canceled. The “latest membership” is also chosen by descending end date, so a future/canceled long membership can hide the currently usable membership. Reuse one canonical access-status expression everywhere.

### P2 — Bottom sheets are not behaviorally equivalent

Flutter filter/form sheets use `DraggableScrollableSheet`, including defined initial/min/max sizes. Examples:

- check-ins: `lib/screens/check_ins/check_ins_screen.dart:769`
- revenue filters: `lib/screens/revenue/revenue_screen.dart:1941`
- revenue analytics: `lib/screens/revenue/revenue_analytics_screen.dart:1076`
- period comparison: `lib/screens/revenue/period_comparison_screen.dart:1385`
- plans: `lib/screens/membership_plans/membership_plans_screen.dart:795`

The RN shared component is a transparent `Modal` with an entering/exiting translation:

- `kratos-admin-expo/src/components/bottom-sheet-modal.tsx:25-60`

It has no pan gesture, no swipe-to-dismiss, no snap points/detents, no min/max behavior, and no focus-restoration mechanism. The visible handles in consumers are decorative. Sheet heights vary from roughly 70% to 90%, while the member filter is effectively full-screen. Android gets no `KeyboardAvoidingView` behavior, so form controls/action buttons are at risk of being covered by the keyboard.

This is one of the clearest interaction-parity gaps. Use a tested native bottom-sheet implementation or explicitly redesign these as full-screen modal routes and validate keyboard, nested scroll, dismissal, and accessibility on both platforms.

### P2 — Date-range interactions are generally no longer atomic

Flutter commonly uses `showDateRangePicker`. RN screens generally expose two independent single-date pickers and mutate draft state as each date changes. Besides the definite Android Check-in Statistics defect, this means a user can leave a half-edited range, and range correction behavior differs by screen.

Relevant RN implementations:

- `kratos-admin-expo/src/screens/revenue/revenue-filter-sheet.tsx:17-27`
- `kratos-admin-expo/src/app/revenue-analytics.tsx:196`
- `kratos-admin-expo/src/app/check-in-stats.tsx:35-69`
- `kratos-admin-expo/src/app/gold-checkins.tsx`
- `kratos-admin-expo/src/app/period-comparison.tsx`

Every range picker needs a platform matrix covering selection order, cancel, same-day range, inverted range, minimum/maximum date, daylight-saving boundaries, and reopening an existing draft.

### P2 — Reachable Flutter Performance tooling is missing

Flutter opens the Performance screen by long-pressing the dashboard title:

- `lib/screens/dashboard/dashboard_screen.dart:125-129`
- `lib/screens/performance/performance_screen.dart`

There is no RN route or equivalent service/UI. The Flutter Products screen also has no RN port, but no active navigation reference was found for Products, so that omission currently has lower user impact. Conversely, RN adds an Admin Tools screen and visible navigation for Gyms/Plans, which are present but not readily routed in Flutter.

Feature matrix:

| Area | Flutter | React Native | Verdict |
|---|---:|---:|---|
| Login/auth | Yes | Yes | Close; RN storage differs |
| Dashboard | Yes | Yes | Query and navigation differences |
| Members/list/filters | Yes | Yes | Mostly ported; status semantics differ |
| Member detail/history/revenue | Yes | Yes | Strong coverage |
| Membership create/edit/delete | Yes | Yes | Shared transaction defects |
| Check-ins/list/filter | Yes | Yes | Strong static coverage |
| Check-in statistics | Yes | Yes | Android custom range broken |
| Gold analytics | Yes | Yes | RN calendar-day defect |
| Revenue/list/export | Yes | Yes | Extra RN amount filter; deletion semantics inconsistent |
| Revenue analytics | Yes | Yes | Query structure substantially aligned |
| Period comparison | Yes | Yes | Query structure aligned; modal behavior differs |
| Gyms | Present | Present via Admin Tools | RN makes it discoverable |
| Membership plans | Present | Present via Admin Tools | RN makes it discoverable |
| Performance | Reachable by hidden gesture | Missing | Parity gap |
| Products | Present but apparently unreachable | Missing | Low current navigation impact |
| Membership access trend | Missing | New | RN enhancement, not parity |

### P2 — PowerSync change handling invalidates every React Query query

The RN bridge calls unscoped `invalidateQueries()` after any PowerSync database change and after `lastSyncedAt` changes:

- `kratos-admin-expo/src/providers/app-providers.tsx:15-53`

This also invalidates network-backed Supabase/RPC queries that are unrelated to the changed table. A sync batch can trigger broad refetching, loading churn, bandwidth use, and battery cost. The 150 ms debounce reduces bursts but does not add query scoping. Map PowerSync tables to query keys, or use live SQLite observers for local queries and explicit mutation invalidation for remote ones.

### P2 — New analytics migration depends on session timezone for event dates

The membership-access migration correctly derives `v_today` in Europe/Bucharest, but historical event comparisons cast timestamps with session-dependent `::date`, including:

- `membership_events.at::date` at `supabase_migrations/20260808090000_add_membership_access_analytics.sql:111,120,132,141,154,167`
- `memberships.frozen_at::date` at line 159
- `memberships.canceled_at::date` at line 169
- `family_memberships.created_at::date` at lines 193 and 250

This is correct only while the calling/database session timezone remains Europe/Bucharest. In a UTC session, an event between Bucharest midnight and UTC midnight is assigned to the previous reporting date. Make each cast explicit, e.g. `(me.at AT TIME ZONE 'Europe/Bucharest')::date`. Existing SQL tests use midday timestamps and do not exercise this boundary.

Historical reconstruction also reads current `memberships` and `family_memberships`; the audit table is not used by `membership_access_people_at`. Persisted closed snapshots protect normal future history, but a missing/recomputed historical day can be distorted by records deleted after deployment.

### P2 — Sequential hard delete can leave partial data

Both ports delete revenue rows, then check-ins, then the membership with separate requests:

- `kratos-admin-expo/src/repositories/members-repository.ts:402-409`
- `lib/screens/members/member_detail_screen.dart:436-476`

A failure midway leaves a partially deleted membership history. `membership_events` and `family_memberships` are not explicitly handled, so success also depends on database FK cascade/restrict configuration. Replace with one authorized transaction/RPC and test all dependent tables.

### P2 — Every legacy RPC referenced by the clients is absent live

The shared legacy analytics service calls these nine RPCs:

- `get_business_metrics`
- `get_revenue_trends`
- `get_membership_trends`
- `get_gym_occupancy`
- `get_top_performing_gyms`
- `get_member_retention`
- `get_checkin_patterns`
- `get_membership_plan_performance`
- `get_payment_method_analytics`

The Flutter Performance service additionally references:

- `get_table_metrics`
- `get_slowest_queries`
- `get_database_size_metrics`
- `get_connection_metrics`
- `get_index_usage_stats`
- `get_cache_hit_ratios`
- `get_performance_trends`

The Flutter Products service references:

- `get_admin_product_employees`
- `get_admin_product_dashboard_kpis`
- `get_admin_products_overview`
- `get_admin_top_selling_products`
- `get_admin_employee_product_sales`
- `get_admin_employee_product_sale_transactions`
- `get_admin_product_stock_movements`

Live read-only calls authenticated as the supplied admin returned PostgREST `PGRST202` / function-not-found for **all 23 legacy RPCs**. The nine-RPC RN analytics implementation is currently unused, so it is dead/latent RN code. Flutter's Performance screen is reachable and catches failures by returning zero/empty results, which can make a backend defect look like valid empty data. The Products screen appears unreachable, but its backend contract is also not deployed in the configured project.

The new RN RPC `get_admin_membership_access_trend` is deployed, authorized for the admin account, and returned data for `7d`, `30d`, `12w`, and `12m` ranges.

### P2 — Date serialization contracts differ between ports

RN writes membership dates using UTC ISO strings:

- `kratos-admin-expo/src/repositories/members-repository.ts:449-450`

Flutter sends Dart local `toIso8601String()` values:

- `lib/widgets/membership_form_dialog.dart:111-112`

If these fields are date-only business values, both should send an explicit `YYYY-MM-DD`; if they are instants, both should send UTC and render in an explicit business timezone. The current mismatch makes behavior dependent on the PostgreSQL column type and session timezone.

### P2 — Login controls have duplicate/unlabeled accessibility elements

The RN outlined field gives the input `accessibilityLabel={label}`, while the visible label text remains independently exposed:

- `kratos-admin-expo/src/components/outlined-text-field.tsx:50-94`

The native iOS accessibility hierarchy contained duplicate “Email” and “Parolă” nodes. Automated interaction repeatedly selected the decorative label instead of the input. The password eye button also has a button role but no descriptive accessibility label. This is a real screen-reader/testability defect even though it is not an authentication defect.

### P3 — Flutter's canceled filter is wired in the UI but absent from SQL

Flutter offers the “Anulat” option, but its switch has no `canceled` branch:

- `lib/screens/members/members_screen.dart:268-281`

RN adds the missing `m.canceled_at IS NOT NULL` predicate:

- `kratos-admin-expo/src/repositories/members-repository.ts:122-124`

RN is more correct here, but it intentionally differs from Flutter.

### P3 — RN adds a revenue amount filter not present in Flutter

RN adds “Sub 5 RON” (`under_five`), while Flutter has only all/zero/non-zero. This is an enhancement, not exact parity. The `< 500` predicate also includes zero and negative values; clarify whether the intended range is strictly 0–5 RON.

### P3 — Malformed check-in rows can silently shorten RN pagination

The RN check-in parser skips malformed rows, but `hasMore` is based on parsed item count. If the database returns a full page containing one malformed row, the visible page is short and pagination can stop even though more database rows exist. Flutter instead fails the load on a malformed mapped row. Neither behavior is ideal; log/observe data corruption and base pagination on the raw row count.

### P3 — Custom SecureStore session writes are not atomic

RN chunks the serialized Supabase session into SecureStore entries, then writes metadata. This avoids per-item storage limits, but an interruption during overwrite can leave mixed old/new chunks. Add versioned keys plus commit/rollback metadata, or use a storage adapter with an atomic replacement contract.

## Architecture and backend comparison

### Read path

Both applications primarily follow this flow:

```text
UI -> screen state / React Query -> repository SQL -> local PowerSync SQLite
                                               ^
                                               |
                              PowerSync service <- Supabase/Postgres sync
```

Flutter initializes PowerSync before `runApp` and manually refreshes screen state. RN initializes through providers, uses React Query with 30-second staleness and two retries, and bridges PowerSync changes to query invalidation.

The local database filename is the same (`kratos-powersync.db`) and the endpoint resolves to `https://sync.kratosgym.ro` by default. Both connector implementations use the active Supabase JWT/user and deliberately reject PowerSync uploads because current mutations go directly to Supabase.

Sources:

- Flutter: `lib/main.dart:10-29`, `lib/services/powersync_service.dart:8-64`
- RN: `kratos-admin-expo/src/lib/powersync/system.ts:7-45`, connector/client files under `src/lib/powersync/`

### PowerSync schema

The manually compared table/column definitions are equivalent for the ported domain. The schema covers:

- `profiles`
- `memberships`
- `membership_plans`
- `membership_events`
- `check_ins`
- `gyms`
- `family_memberships`
- `revenue_ledger`
- `admin_analytics_summary`
- the related analytics/support tables declared by both schemas

Column names and SQLite type categories align, including newer fields such as `effective_start_date`, `membership_type`, `plan_kind`, tier fields, cancellation/freeze fields, and revenue soft-delete metadata. No RN-vs-Flutter PowerSync schema omission was found in the compared definitions.

### Query parity by domain

| Domain | Read source | Comparison |
|---|---|---|
| Dashboard profiles/check-ins/revenue/WAU/MAU | PowerSync SQLite | SQL structure close; active access semantics differ; deleted revenue issue shared |
| Members pagination/search/latest membership | PowerSync SQLite | Closely ported; RN fixes Flutter canceled filter; shared status-definition issues |
| Member detail and membership history | PowerSync SQLite | Strong field/query coverage |
| Member revenue history | PowerSync SQLite | Ported in both current worktrees |
| Check-in list and filters | PowerSync SQLite | Substantially aligned |
| Check-in statistics | PowerSync SQLite | Aggregate SQL aligned; RN Android picker breaks custom input |
| Gold check-ins | PowerSync SQLite | Aggregate shape aligned; RN local-date serialization is wrong |
| Revenue list/stats/export | PowerSync SQLite | Strong coverage; RN adds amount filter; deleted status requires canonical policy |
| Revenue analytics | PowerSync SQLite | Daily/weekly trend and grouping logic substantially aligned |
| Period comparison | PowerSync SQLite | Core aggregation substantially aligned; modal/date interactions differ |
| Gyms/plans administration | Direct Supabase | Both perform direct reads/writes; RN adds discoverable routing |
| Membership access trend | Supabase RPC | RN-only new feature |

### Mutation inventory

Direct Supabase mutations in the active RN port include:

- `profiles`: update member name;
- `memberships`: create, update, hard delete;
- `revenue_ledger`: create/update membership charge, soft delete, restore, edit;
- `membership_plans`: create, update, activate/deactivate;
- auth: sign in/out and session refresh.

These correspond closely to the Flutter mutation paths. Neither app currently relies on PowerSync upload queues, so offline mutation support is not present. After a direct write, the local screen can remain stale until Supabase replication reaches PowerSync. RN eventually re-invalidates after a local database change; Flutter more often depends on manual refresh/re-entry.

## UI parity assessment

### What is close

- Dark Material-inspired palette, purple primary color, cards, chips, list rows, FABs, and major labels closely follow Flutter.
- The login screen renders correctly in a native iOS build and is recognizably equivalent in hierarchy.
- Members, member detail, check-ins, revenue, analytics, and comparison screens preserve the Flutter information architecture and most controls.
- Loading, empty, pull-to-refresh, and error states exist on the primary RN screens.

### What prevents “pixel perfect” status

- Flutter uses Material 3 widgets; RN manually approximates them.
- RN uses Expo Router native tabs/SF Symbols on iOS, while Flutter uses Material `NavigationBar` and Material icons.
- RN tabs preserve native navigation stacks/state differently from Flutter's indexed body switching.
- Sheets and date pickers have materially different mechanics, not just styling.
- Typography metrics, system picker appearance, status/navigation bars, keyboard behavior, and accessibility focus are platform-native and not normalized by a screenshot/golden test suite.

There are no Flutter-vs-RN screenshot goldens or interaction-contract tests, so there is currently no mechanism that could prove pixel-perfect parity.

## Runtime and verification evidence

All checks were read-only against application/backend data; no production mutations were performed.

| Check | Result |
|---|---|
| RN TypeScript typecheck | Passed |
| RN Expo lint | Passed |
| RN Jest | Passed: 7 suites, 15 tests |
| RN iOS Expo export | Passed |
| RN Android Expo export | Passed |
| RN native iOS development build | Passed: 0 errors, 19 warnings |
| RN native iOS launch | Passed on iPhone 17 Pro simulator |
| Supabase admin login | Passed with supplied account; profile is authorized as admin |
| New membership-access RPC | Passed live for 7d/30d/12w/12m |
| All 23 legacy analytics/performance/products RPCs | Absent live (`PGRST202`) |
| Expo Doctor | 18/20; two network-only checks could not reach remote services |
| Flutter analyze | Completed with 217 info/deprecation/style findings and no compile error |
| Flutter test | Fails: default stale counter test expects text `0`; no meaningful app test suite |

The RN app requires a development build because PowerSync/SQLite are native dependencies; Expo Go is not a valid test environment. Simulator login automation did not reach the dashboard because duplicate accessibility labels caused text to be entered into the wrong field. Independent live Supabase authentication with the same credentials succeeded, so this was not classified as an auth/backend failure.

## Test-coverage gaps

The 15 RN tests cover selected repository/model/filter behavior, not full parity. Missing high-value tests include:

- a query fixture suite that runs equivalent Flutter/RN SQL over the same seeded SQLite database;
- dashboard canonical-metric tests covering future, canceled, frozen, day-pass, family, and inactive records;
- membership-save transactional and retry/idempotency tests;
- soft-deleted revenue aggregate tests across every screen;
- timezone tests for Europe/Bucharest winter/summer and DST transition dates;
- Android and iOS date-picker interaction tests;
- bottom-sheet keyboard/drag/dismiss/nested-scroll tests;
- accessibility assertions for labels, roles, focus, and modal isolation;
- visual screenshot goldens at representative phone sizes and font scales;
- offline startup, expired-token refresh, reconnect, and delayed PowerSync replication tests.

## Recommended release plan

### Before calling the port functionally equivalent

1. Define one canonical membership-access/status SQL contract and use it in dashboard, member filters/cards, the analytics RPC, and tests.
2. Fix Android custom date ranges and the Gold local-date conversion.
3. Replace membership save/delete sequences with authorized transactional RPCs and repair any existing ledger rows whose plan/gym/payment differs from the membership.
4. Apply one soft-delete policy to every revenue query.
5. Decide whether Performance is a required feature and either port it or formally remove it from Flutter/product scope.

### Before calling the port interaction-equivalent

6. Replace or redesign the modal-sheet component, with explicit iOS/Android acceptance tests.
7. Standardize date/range picker flows and keyboard behavior.
8. Correct login and modal accessibility semantics.
9. Add cross-platform screenshot and interaction golden tests.

### Before production rollout

10. Scope PowerSync-to-React-Query invalidation.
11. Make Bucharest timezone conversion explicit inside the analytics SQL and add midnight-boundary SQL tests.
12. Add error telemetry instead of silently converting absent RPCs/parser errors into valid empty states.
13. Run a seeded side-by-side acceptance suite on both iOS and Android using identical backend snapshots.

## Acceptance criteria for “perfect match”

The apps should only be described as matching when:

- every reachable Flutter screen has an explicit RN counterpart or an approved removal decision;
- equivalent filters produce identical IDs and totals from the same database snapshot;
- all mutations have identical validated postconditions, including revenue/audit side effects;
- iOS and Android sheet/date/keyboard flows pass interaction tests;
- timezone fixtures produce identical calendar-day results;
- screenshots pass agreed visual tolerances at multiple sizes/font scales;
- accessibility trees expose one correctly labeled control per interactive element;
- offline/reconnect/token-expiry behavior is verified;
- the backend RPC inventory is either deployed and tested or removed from both clients.
