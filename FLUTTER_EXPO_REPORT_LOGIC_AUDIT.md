# Flutter / Expo report logic audit — 13 September 2026

**The apps do not produce equivalent reports from equivalent inputs.** The most consequential differences are the reporting timezone, inclusion of deleted charges, membership selection/status filters, deduplication of Gold visitors, and membership write transactions. Expo contains several corrections to Flutter, but also some new defects.

This audit compares the **current working files**, including uncommitted changes, in `lib/` and `kratos-admin-expo/src/`. The August audit was used as an inventory only; its conclusions were checked against current code. No application code or production data was changed. The only additions are this report and local audit probes.

There are **36 numbered findings**, grouped by cause rather than counting every affected screen as a separate defect. Some are deterministic differences on an identical database snapshot; others require a particular sequence of actions, malformed data, a clock change, or a backend deployment. Those conditions are stated below. This is a comprehensive source audit, not a claim that every possible native runtime behavior has been exercised.

## Evidence and scope

- Reviewed the active dashboard, members/list/detail/history/revenue, check-in list/statistics/Gold, revenue/list/CSV/analytics/comparison, date picker components, membership/plan forms, repositories/models, synchronization providers, and relevant SQL migrations. Inspected Flutter-only report surfaces and the unused legacy analytics service for coverage.
- Compared the replicated schemas programmatically: **all 11 table names and their declared column types match**.
- Ran actual Expo repository functions using an in-memory SQLite adapter and the existing TypeScript compiler. Flutter SQL was extracted from source where practical; remaining Flutter comparisons use the exact source predicates/formulas. All **16 recorded fixture checks** completed successfully, including one schema parity check.
- Ran pure Dart probes of the actual date/number operations in Europe/Bucharest. Confirmed DST boundary drift, offset-free local serialization, price truncation, comma parsing, and date display differences.
- Ran the existing Expo Jest suite: **9 suites, 21 tests passed**.
- No live Supabase data, deployed RPC definitions, PowerSync sync rules, installed app binaries, or native picker interactions were inspected. Migration-dependent findings describe what the checked-in SQL does **if deployed**. Local source alone cannot prove both installed apps use the same backend or dataset.

Reproduction files: [Node/SQLite harness](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/audits/2026-09-13-report-parity/verify.cjs), [fixture output](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/audits/2026-09-13-report-parity/fixture-results.json), [Dart probes](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/audits/2026-09-13-report-parity/dart-probes.dart), [Dart output](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/audits/2026-09-13-report-parity/dart-results.json).

## A. Date selection, date boundaries, and clock behavior

### 1. Most Flutter date filters use UTC-shaped boundaries; Expo uses local calendar days — high impact

Flutter constructs a local `DateTime`, serializes it without an offset, then compares it using SQLite `datetime(...)`. A timezone-bearing stored timestamp is normalized to UTC, while the offset-free boundary retains the local clock digits. Expo instead uses `date(column, 'localtime')` and date-only `YYYY-MM-DD` parameters.

**Example, selecting September 13 in Bucharest:**

| Stored timestamp | Local time | Flutter selected day | Expo selected day |
|---|---|---|---|
| `2026-09-12T22:30:00Z` | September 13, 01:30 | Excluded | Included |
| `2026-09-13T22:30:00Z` | September 14, 01:30 | Included | Excluded |

With respective charges of 100 and 200 RON, the same September 13 selection gives **Flutter 200 RON / Expo 100 RON**. This was reproduced with the actual Expo repository and Flutter aggregate SQL. Both apps can display the transaction timestamp locally even though Flutter filters it into the wrong local date.

Affected paths:

| Report/filter | Flutter implementation | Expo implementation |
|---|---|---|
| Dashboard check-ins today / revenue since month start | [dashboard:31](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/dashboard/dashboard_screen.dart:31) | [dashboard repository:17](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/dashboard-repository.ts:17) |
| Revenue list, summary, CSV | [revenue:296](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_screen.dart:296) | [revenue repository:52](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/revenue-repository.ts:52) |
| Today / yesterday / last-week comparison | [revenue:144](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_screen.dart:144) | [today comparison:177](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/revenue-repository.ts:177) |
| Revenue analytics | [analytics:110](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_analytics_screen.dart:110) | [analytics repository:230](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/revenue-repository.ts:230) |
| Period comparison | [comparison:135](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/period_comparison_screen.dart:135) | [period stats:326](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/revenue-repository.ts:326) |
| Member registration / check-in date filters | [members:299](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/members_screen.dart:299) | [member filters:163](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/members-repository.ts:163) |
| Check-in statistics | [check-in stats:162](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/check_ins/check_in_stats_screen.dart:162) | [stats repository:125](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/check-ins-repository.ts:125) |
| Gold/Silver check-ins | [Gold:63](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/analytics/gold_checkins_screen.dart:63) | [Gold repository:181](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/check-ins-repository.ts:181) |

Gold's Flutter implementation already uses date-only parameters, but applies `date(ci.created_at)` without `localtime`; it therefore still differs from Expo.

Expo's rule follows the **device timezone**, not a fixed Europe/Bucharest timezone or `gyms.timezone`. A device set to another timezone can consequently disagree with the Bucharest-based membership-access RPC. Timestamp storage format also matters: if a local wall time was stored without its true offset, Expo's conversion would treat it as UTC. The fixture uses normal timezone-bearing timestamps. SQLite's underlying conversion behavior is documented in [Date and Time Functions](https://www.sqlite.org/lang_datefunc.html).

### 2. Revenue chart buckets are UTC in Flutter and local in Expo — high impact

Flutter groups by `date(r.paid_at)` or the Monday derived from UTC `strftime('%w', r.paid_at)`. Expo adds `localtime` to both daily and weekly grouping.

A payment at **Monday September 14, 01:30 Bucharest** goes into the **September 7 week in Flutter**, and the **September 14 week in Expo**. The aggregate across a sufficiently broad period can agree while individual points differ. Confirmed by fixture.

Sources: [Flutter trend SQL:174](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_analytics_screen.dart:174), [Expo period expression:249](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/revenue-repository.ts:249).

### 3. “7 / 30 / 90 days” means a rolling timestamp window in Flutter and whole dates in Expo

Flutter revenue analytics starts at `now - N × 24 hours` and ends at `now`. Expo derives those dates but strips the times, so it includes the entire first and last date. At midday, the first morning can be included only by Expo; future-dated rows later today can also be included by Expo. The “7 days” Expo revenue range normally spans **eight calendar dates** because it subtracts seven and includes both endpoints. Check-in Statistics uses minus six for seven dates in both apps, so that report's preset is different even inside Expo.

Flutter year/all presets also end at the current timestamp, versus today's entire local date in Expo. This is independent of the timezone issue in #1.

Sources: [Flutter range:67](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_analytics_screen.dart:67), [Expo range:27](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/revenue-analytics.tsx:27), [Expo check-in presets:18](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/check-in-stats.tsx:18).

### 4. Flutter Check-in Statistics freezes its upper timestamp when the preset is chosen

Flutter stores `endExclusive = now + 1 second` in `_applyPreset`. Pull-to-refresh calls `_loadStats`, which reuses it. Later check-ins eventually fall outside that frozen boundary even after refresh. Expo stores today's date, so refreshing includes later arrivals on that date.

The fixture opens at 10:00, then adds a 17:00 local check-in: Flutter's stored predicate returns zero; Expo returns one. Because of #1, Flutter's effective clock cutoff is also timezone-shifted, so this need not become visible immediately after opening.

Sources: [Flutter preset:79](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/check_ins/check_in_stats_screen.dart:79), [Flutter refresh:156](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/check_ins/check_in_stats_screen.dart:156), [Expo range/query:29](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/check-in-stats.tsx:29).

### 5. Expo's memoized revenue ranges can remain on yesterday after midnight

Expo Revenue Today computes its date inside `useMemo([filters, period, search])`. Manual refresh does not change those dependencies. Its today-comparison query computes `new Date()` each time, so after midnight the **list can still show yesterday while “Today vs Yesterday” shows today**.

Expo revenue analytics similarly memoizes resolved preset dates only on range/custom-date changes. Flutter recomputes revenue list/analytics dates inside each load/export. This is an action-sequence difference, not an initial-load mismatch. Both Gold screens and both comparison screens retain explicitly selected ranges; that part is shared behavior.

Sources: [Expo revenue:29](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/(tabs)/revenue/index.tsx:29), [Expo analytics:30](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/revenue-analytics.tsx:30), [Flutter resolve/load:196](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_screen.dart:196), [Flutter analytics load:196](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_analytics_screen.dart:196).

### 6. Flutter's elapsed-duration arithmetic changes calendar boundaries at DST

Confirmed in Dart with `TZ=Europe/Bucharest`:

- October 25, 2026 midnight + 24 hours becomes **October 25 at 23:00**, not October 26 midnight. This affects the check-in custom end-exclusive boundary and dashboard/day comparison calculations.
- March 23, 2026 midnight + six days, 23:59:59 becomes **March 30 at 00:59:59**, not March 29 at 23:59:59. Flutter's current/last-week comparison can extend into Monday. The autumn equivalent ends Sunday an hour early.
- Subtracting elapsed days near midnight across a clock change can also choose an adjacent civil date. Expo check-in presets and day comparisons use `addCalendarDays`; Expo comparison weeks use calendar constructors.

Expo revenue analytics still subtracts milliseconds to find its first date, so its rolling-preset start is not fully protected from this last edge case.

Sources: [Flutter comparison week:62](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/period_comparison_screen.dart:62), [Flutter check-in end:140](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/check_ins/check_in_stats_screen.dart:140), [Expo calendar math:59](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/utils/calendar-date.ts:59), [Expo comparison:60](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/period-comparison.tsx:60).

### 7. Expo does not clamp or validate an existing date range against picker bounds

The Expo range dialog enables Apply when start/end exist and are ordered. It does **not** check either endpoint against `minimumDate`/`maximumDate`, unlike its single-date dialog. Period Comparison passes its existing range unchanged, while Flutter clamps its initial end to the last day of this month.

**Reproduction:** choose “This year,” then open Custom in September and immediately Apply. Expo can preserve December 31 despite a maximum of September 30; Flutter initially clamps to September 30. The two reports now differ after the same visible action sequence. This is confirmed source behavior; native tapping was not exercised.

Sources: [Expo range validation:88](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/components/calendar-dialog.tsx:88), [Expo comparison picker:285](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/period-comparison.tsx:285), [Flutter clamp:321](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/period_comparison_screen.dart:321).

### 8. Membership date picker maximums differ by almost a year

Flutter uses `lastDate: DateTime(2030)`, which is **January 1, 2030**. Expo allows through **December 31, 2030**. Thus Expo can create/select membership dates Flutter's picker cannot reproduce.

Both adjust the end to start + 30 days when a new start exceeds the old end. Both permit selecting an end before the start in the UI; Expo's save RPC then rejects the inverted range, whereas Flutter's form has no equivalent client check. Backend constraints determine whether Flutter's direct write is rejected.

Sources: [Flutter picker:203](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/widgets/membership_form_dialog.dart:203), [Expo picker:238](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/screens/members/membership-form-sheet.tsx:238), [RPC validation:52](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/supabase_migrations/20260813110000_atomic_membership_ledger_and_access_fixes.sql:52).

### 9. Some displayed dates are UTC in Flutter, local in Expo

Flutter member cards use `date.day/month/year` directly after `DateTime.parse`, without `.toLocal()`. Profile registration and last-visit timestamps with a UTC suffix therefore display a UTC date. Expo's `Date` local getters display the local date.

For `2026-09-12T22:30:00Z`, Flutter's member card shows **12/09**, Expo shows **13/09** in Bucharest. The “Member since” detail card has the same distinction. Revenue timestamps and event timestamps already convert locally in Flutter and generally agree with Expo.

Remaining Expo date-only fields in member-list expiry, membership-event old/new dates, and membership-trend period dates still go through `new Date('YYYY-MM-DD')` and local getters. On a device west of UTC they can display the **previous date**, while Flutter's date-only parser and Expo's newer membership detail model preserve the intended day. This is a conditional inconsistency within Expo's partial CalendarDate migration.

Sources: [Flutter short date:464](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/members_screen.dart:464), [Flutter detail date:496](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/member_detail_screen.dart:496), [Expo member card:23](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/screens/members/member-card.tsx:23), [Expo event parser:32](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/models/membership-event.ts:32), [Expo trend parser:25](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/models/membership-trend.ts:25).

### 10. Membership model expiry fallback uses elapsed instants versus inclusive calendar days

When `days_left` is absent, Flutter considers an end date of today expired after midnight and computes remaining days by truncating elapsed time. Expo keeps the membership unexpired throughout the end date and uses calendar-day differences. At noon on September 13 with end date September 13, the fallback says **expired in Flutter / not expired in Expo**.

The active member-detail SQL in both apps normally supplies a non-null computed `days_left`, so this is primarily a model/fallback difference rather than the normal report query. Do not confuse it with the confirmed member-filter changes below.

Sources: [Flutter expiry model:195](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/models/membership.dart:195), [Expo expiry model:114](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/models/membership.ts:114).

## B. Revenue and visitor aggregates

### 11. Default revenue list/summary/CSV includes deleted charges only in Flutter — high impact

Both internal defaults say `deletedStatus = 'all'`. Flutter adds no deletion predicate for that value. Expo treats every value except `'deleted'` as `COALESCE(is_deleted,0)=0`; its UI calls this “Normal.” Expo therefore no longer has a visible combined live-and-deleted view.

One 100 RON live charge plus one 50 RON deleted charge gives **Flutter 150 RON / Expo 100 RON**, with transaction counts 2 / 1. The same difference affects the CSV because both export through their report query. Explicit deleted-only results still have matching deletion semantics.

Sources: [Flutter filter:296](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_screen.dart:296), [Expo filter:52](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/revenue-repository.ts:52), [Expo default/UI:16](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/screens/revenue/revenue-filter-sheet.tsx:16).

### 12. Dashboard and period-comparison totals include deleted charges only in Flutter — high impact

Flutter dashboard and period comparison have no deletion exclusion. Expo now explicitly excludes deleted charges in both. This affects total, cash/card splits, transaction averages/counts, unique members, plan rankings, new-membership counts, extensions, upgrades, and day-pass counts in the comparison.

This is independent of #11: these reports have their own SQL and no deleted-status selector. Both apps' Revenue Analytics and Today Comparison already exclude deleted charges; their remaining differences come from other findings.

Sources: [Flutter dashboard:65](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/dashboard/dashboard_screen.dart:65), [Flutter period predicate:140](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/period_comparison_screen.dart:140), [Expo dashboard:46](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/dashboard-repository.ts:46), [Expo period predicate:335](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/revenue-repository.ts:335).

### 13. Combined Gold visitors at K1 + K2 are deduplicated only in Expo — high impact

Flutter adds the two gyms' unique-member counts. Expo issues another `COUNT(DISTINCT ci.user_id)` across both gyms. One Gold member visiting both gyms yields **2 “unique members” in Flutter / 1 in Expo**; the check-in count stays 2. Confirmed by fixture.

The separate “Total Gold” and “Total Silver” cards across all gyms still sum per-gym distinct counts in **both** apps. Expo's corrected combined K1/K2 card can consequently disagree with its all-gyms total even when no one visited another gym.

Sources: [Flutter combined card:258](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/analytics/gold_checkins_screen.dart:258), [Expo combined query:203](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/check-ins-repository.ts:203), [Expo total cards:24](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/gold-checkins.tsx:24).

### 14. Chart rendering can communicate different values even when aggregates agree

- **Expo zero-total donut displays a fabricated 0.01 RON total:** `sum(...) || 1` is used both as the division denominator and the displayed total. A nonempty result consisting of zero-value charges triggers it. Flutter displays the actual zero-valued section amounts; its zero-sum pie rendering still needs native validation.
- Flutter's revenue trend uses a curved line and a Y maximum of `maxRevenue × 1.1`. Expo connects points with straight segments and uses `max(actual, 1)`. This changes visual peaks/interpolation, though tooltip input values remain the aggregates.
- Flutter labels each gym slice with its amount. Expo initially shows an all-gym center total and shows a specific gym's value only after selection.
- Period comparison bar widths use rounded/clamped thousandths in Flutter versus continuous proportions with a minimum in Expo; displayed percentage formulas otherwise match.
- Expo truncates some long labels and repeats chart selection by row index. When ordering changes after refetch, the same selected index can describe another row. This is a presentation/state difference, not a different SUM.

Sources: [Flutter trend:657](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_analytics_screen.dart:657), [Flutter gym pie:818](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_analytics_screen.dart:818), [Expo trend:47](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/revenue-analytics.tsx:47), [Expo donut:135](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/revenue-analytics.tsx:135), [Flutter bars:1203](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/period_comparison_screen.dart:1203), [Expo bars:239](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/period-comparison.tsx:239).

## C. Which members are selected and shown

### 15. Expo prioritizes a usable membership; Flutter chooses the latest end date — high impact

Flutter ranks each owner's memberships by end date, then creation date. Expo first ranks memberships that are active, started, unexpired by calendar date, uncanceled, and unfrozen; only then does it compare end/creation dates.

Given a usable membership and a later-ending future, frozen, inactive, or canceled membership, the apps can show a different plan, expiry, status, and days remaining. Gym and plan filters also operate on that different selected membership, changing the member IDs and total count. This was reproduced with a usable membership plus a future membership.

This changed ranking applies to the **members list**. The member-detail membership list retains the old ordering in both apps, so Expo list/detail can themselves prioritize different records.

Sources: [Flutter rank:327](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/members_screen.dart:327), [Expo rank:62](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/members-repository.ts:62), [Expo detail ordering:298](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/members-repository.ts:298).

### 16. Expo “Active” includes memberships expiring in 0–7 days; Flutter excludes them

Flutter Active is `days_left > 7`; Expo Active uses its usable-membership predicate and has no lower threshold of eight days. A usable membership with three days left is absent from Flutter Active but present in Expo Active. Expo's card still says “Expiră în curând.” Confirmed by fixture.

Sources: [Flutter active:268](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/members_screen.dart:268), [Expo active:134](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/members-repository.ts:134).

### 17. Expo Active/Expiring checks usability; Flutter checks days remaining only

Expo additionally requires `is_active=1`, effective start no later than today, end date no earlier than today, no cancellation, and no freeze. Flutter's Active/Expiring filters ignore all those fields.

Consequences include frozen or canceled memberships appearing in Flutter Active; future memberships appearing in Flutter Expiring if their stored days match; and differing treatment when stored `days_left` disagrees with `end_date`. Expo Active plus Frozen is necessarily empty; Flutter can return rows for that combination.

Neither version's member-list filter explicitly excludes day-pass plan kinds. That restriction belongs to the separate Expo membership-access RPC, not this list.

Sources: [Flutter status predicates:267](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/members_screen.dart:267), [Expo usable predicate:106](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/members-repository.ts:106).

### 18. “Without membership” includes inactive memberships in Expo

Flutter's `inactive` means `m.id IS NULL`. Expo uses `m.id IS NULL OR is_active=0`. Thus the identically labeled “Fără abonament” choice can include someone who does have a membership in Expo, with a card even saying Active/Expiring because the label formatter does not consult `is_active`.

Sources: [Flutter inactive:277](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/members_screen.dart:277), [Expo inactive:143](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/members-repository.ts:143), [Expo UI label:107](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/screens/members/members-filter-sheet.tsx:107).

### 19. Expo's unparenthesized inactive OR bypasses other filters — confirmed defect, high impact

The condition in #18 is concatenated into an AND-separated WHERE clause without parentheses. SQL effectively evaluates:

```sql
(search AND gym AND plan AND m.id IS NULL)
OR (COALESCE(m.is_active, 0) = 0 AND remaining_filters)
```

Inactive records can bypass the preceding search/gym/plan conditions; membership-less rows also satisfy the second branch because NULL becomes zero. Conversely, the first branch can bypass later date/freeze conditions. Both the count and fetched rows use this expression.

Fixture: search Alice, select a particular gym, choose Without membership. Flutter returns none. Expo returns **Bob with an inactive membership at the wrong gym and Alice without any membership**. This is not an intentional status-definition change; the OR needs grouping.

Source: [Expo clause construction:143](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/members-repository.ts:143), [final AND join:176](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/members-repository.ts:176).

### 20. Flutter's Canceled filter is a no-op; Expo checks any canceled owner membership

Flutter exposes “Anulat,” but its query switch has no `canceled` case. Other filters still apply, but canceled status adds no restriction. Expo uses an EXISTS over all owner memberships.

Expo therefore correctly narrows the population compared with Flutter, but can still display a currently active membership in a canceled-filter result if the person has an older canceled one. Gym/plan filters concern the selected membership, not necessarily the canceled membership. Family membership cancellation is not included by the EXISTS unless the person is the owner.

Sources: [Flutter switch:267](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/members_screen.dart:267), [Flutter canceled chip:1580](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/members_screen.dart:1580), [Expo canceled EXISTS:146](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/members-repository.ts:146).

### 21. Opening a member from a revenue row loads different profile data

Flutter constructs the revenue row's client Profile from only ID/name, then passes that Profile into Member Detail. Detail stores it and reloads only memberships/check-ins. Missing registration time defaults to **now**, with absent email/phone/role flags. Even a profile opened from Members stays a passed snapshot on detail refresh.

Expo navigates by member ID and reloads the complete local profile. The same member opened from Revenue can therefore show different “Member since” and profile information. Expo will instead error if the profile row is unavailable, while Flutter can still show its minimal passed profile.

Sources: [Flutter revenue mapping:220](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_screen.dart:220), [Flutter detail init/load:31](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/member_detail_screen.dart:31), [Flutter profile defaults:83](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/models/profile.dart:83), [Expo detail query:63](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/screens/members/member-detail-screen.tsx:63).

## D. The same edits can create different future report data

These are write-path comparisons, not merely differences in reading an identical snapshot. Actual server constraints/triggers must be inspected before asserting production outcomes.

### 22. Membership saves are transactional only through Expo's new RPC

Flutter independently saves the membership and then writes revenue. A failure in the second request can leave changed access with unchanged/missing financial data. Expo calls `admin_save_membership`; the checked-in SQL executes both operations in one transaction and validates required fields, dates, price, payment method, and referenced records.

If this RPC is absent from the deployed backend, Expo saves fail even though Flutter's direct requests may work. Its presence in the repository does not prove deployment.

Sources: [Flutter save:93](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/widgets/membership_form_dialog.dart:93), [Expo save:455](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/members-repository.ts:455), [RPC:11](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/supabase_migrations/20260813110000_atomic_membership_ledger_and_access_fixes.sql:11).

### 23. Same-price edits leave Flutter's financial classification unchanged

Flutter updates existing revenue only when the price changed. Changing gym, payment method, or plan at the same price therefore leaves the ledger classified under the old values. Even when price changes, Flutter's UPDATE does not include `plan_id`.

Expo's RPC always updates the selected base charge's amount, gym, plan, and payment method. Example: switch a 200 RON membership from Cash/K1 to Card/K2 at the same price. Expo moves 200 RON between those report breakdowns; Flutter does not. Existing `paid_at` remains unchanged, so Expo can revise historical breakdowns.

Sources: [Flutter price gate:152](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/widgets/membership_form_dialog.dart:152), [RPC ledger update:134](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/supabase_migrations/20260813110000_atomic_membership_ledger_and_access_fixes.sql:134).

### 24. The two save paths select and validate different ledger records

Flutter's `maybeSingle()` searches **every ledger row for the membership**, with no source, entry-kind, or deletion predicate. If multiple rows exist, it can fail after saving the membership. If exactly one non-base row exists, it can modify that row's amount/payment/gym. If no row exists and the price did not change, it does nothing.

Expo counts live base charges only: `entry_kind='charge'` and source membership/membership_sale. It updates the single live base charge, inserts one when no base exists, and rejects multiple live base charges or deleted-only base charges before updating the membership. It leaves unrelated extension/refund rows alone. An existing base is normalized to source `membership`, currency `RON`, and an idempotency key, which Flutter does not do.

Consequently refunds/extensions, deleted-only charges, missing base charges, and duplicate records can produce different saved data or different success/failure results.

Sources: [Flutter ledger lookup:155](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/widgets/membership_form_dialog.dart:155), [RPC reconciliation:83](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/supabase_migrations/20260813110000_atomic_membership_ledger_and_access_fixes.sql:83), [RPC update/insert:124](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/supabase_migrations/20260813110000_atomic_membership_ledger_and_access_fixes.sql:124).

### 25. Retrying a failed new-membership form has different duplication behavior

Flutter inserts with a server-generated ID each attempt. After membership insertion succeeds and ledger insertion fails, retrying the open form can create a second membership. Expo allocates a stable membership ID in form state and sends it to the RPC; the ledger has a membership-sale idempotency key.

This protects retries within the same open Expo form. Closing and opening a new form allocates another ID, so it is not global deduplication of equivalent sales.

Sources: [Flutter insert:121](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/widgets/membership_form_dialog.dart:121), [Expo stable form ID:61](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/screens/members/membership-form-sheet.tsx:61), [RPC idempotency:142](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/supabase_migrations/20260813110000_atomic_membership_ledger_and_access_fixes.sql:142).

### 26. Membership deletion has different atomicity and dependent-row handling

Flutter deletes revenue, then check-ins, then membership in separate requests. Expo's RPC deletes revenue, check-ins, family memberships, membership events, and the membership atomically. Flutter does not explicitly delete family/events; live FK cascades or constraints determine that outcome.

A late Flutter failure can already have removed report revenue/check-ins while the membership survives. The equivalent Expo transaction rolls back. Both intentionally delete historical revenue/check-ins when the operation completes; this is distinct from soft-deleting a revenue entry.

Sources: [Flutter delete:460](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/member_detail_screen.dart:460), [Expo delete call:413](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/members-repository.ts:413), [delete RPC:170](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/supabase_migrations/20260813110000_atomic_membership_ledger_and_access_fixes.sql:170).

### 27. Typed amounts are parsed differently — high impact for Romanian decimal input

| Input / form | Flutter | Expo |
|---|---|---|
| Membership price `100,50` | `double.tryParse` fails and falls back to **0**, while nonempty validation passes | Replaces comma and saves **100.50** |
| Membership price `100abc` | Falls back to **0** | `parseFloat` accepts numeric prefix **100** |
| Membership negative price | Form does not reject it; server may | Rejected client-side and by the RPC |
| Edit revenue `100,50` | Rejected as invalid | Accepted as **100.50** |
| Edit revenue `100abc` | Rejected | Numeric prefix accepted as **100** |
| Plan price left empty | Rejected | `Number('')` becomes **0** and passes current price validation |

Both revenue-edit dialogs require a strictly positive amount, so neither can edit a transaction to exactly zero via that dialog. Membership forms allow zero. Dart comma/prefix behavior was reproduced; JavaScript calls are explicit in source.

Sources: [Flutter membership price:422](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/widgets/membership_form_dialog.dart:422), [Expo membership validation:74](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/screens/members/membership-form-sheet.tsx:74), [Flutter revenue edit:2419](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_screen.dart:2419), [Expo revenue edit:16](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/screens/revenue/edit-revenue-entry-dialog.tsx:16), [Expo plan submit:117](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/membership-plans.tsx:117).

### 28. Plan prices truncate cents in Flutter and round in Expo

Flutter plan save uses `(price * 100).toInt()`. Expo uses `Math.round(price * 100)`. Confirmed Dart result: **19.99 → 1998 cents** in Flutter versus **1999 cents** with rounding. Inputs with extra decimal places also differ predictably.

This changes the stored plan price. Its later effect on sale revenue depends on the selling workflow; the admin membership forms themselves do not automatically copy the chosen plan price into the membership price.

Sources: [Flutter plan save:722](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/membership_plans/membership_plans_screen.dart:722), [Expo plan submit:125](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/membership-plans.tsx:125).

### 29. Plan form normalization and validation can alter report categories

Expo trims plan names; Flutter saves the entered name unchanged. Expo lowercases recognized tiers and maps every tier other than gold/bronze to silver. Flutter preserves the raw tier in state; an unsupported tier can conflict with its dropdown options. Editing a legacy basic/unknown tier in Expo can silently save it as silver, changing historical Gold/Silver joins that use the current plan tier.

Expo also rejects negative prices/durations and noninteger durations. Flutter validates price parseability but not negativity, and parses durations without equivalent positive-value validation. Empty duration fields error in Flutter but become zero in Expo. Actual persisted invalid values still depend on backend constraints.

Both plan saves reset yearly price/student discount to zero, currency to RON, and plan kind to package; those are shared behaviors, not Expo-only changes.

Sources: [Flutter plan state/save:672](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/membership_plans/membership_plans_screen.dart:672), [Flutter validators:902](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/membership_plans/membership_plans_screen.dart:902), [Expo validation:117](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/membership-plans.tsx:117), [Expo tier normalization:146](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/membership-plans.tsx:146).

### 30. Membership date payloads preserve time differently

Flutter's initial new-form dates are `now` and `now + 30 days` with clock time. Existing dates preserve their parsed time/UTC flag. Selecting a picker date replaces that with local midnight, and save uses `toIso8601String()`.

Expo's form always holds date-only strings and the RPC accepts PostgreSQL `date` arguments. If membership columns/triggers consume timestamps, “open and save” versus “tap the same calendar date and save” can therefore have different temporal effects in Flutter but not Expo. If storage is purely date-only, much of this difference is normalized away. The deployment's column types and triggers determine the exact effect.

Sources: [Flutter date state:31](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/widgets/membership_form_dialog.dart:31), [Flutter save payload:107](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/widgets/membership_form_dialog.dart:107), [Expo date state:62](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/screens/members/membership-form-sheet.tsx:62), [RPC date parameters:16](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/supabase_migrations/20260813110000_atomic_membership_ledger_and_access_fixes.sql:16).

## E. Loading, synchronization, errors, and pagination

### 31. The apps expose different snapshots during startup, refresh, and navigation

Flutter initializes/connects PowerSync but does not wait for completed sync before opening reports; Splash waits two seconds. Most report screens fetch once or on explicit reload and do not subscribe to database changes. Expo adds an initial sync gate, cached-data continuation, and table-driven query invalidation after sync changes.

Thus identical filters against the same backend do not guarantee identical **local snapshots**. Flutter can show an incomplete first download or remain stale after replication. Expo generally catches subsequent table changes, but cached-data continuation can still expose stale results. Neither direct Supabase mutation is itself a guarantee that the following local query already contains the change.

Flutter's home replaces the current tab widget, resetting filters/loading state when switching screen types. Expo uses persistent native tab routes and cached queries. Returning to a tab can therefore retain old filter/date/page state in Expo but reset it in Flutter. Expo queries have a 30-second default stale time and two retries; Flutter loads make one attempt.

Sources: [Flutter PowerSync:49](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/services/powersync_service.dart:49), [Flutter Splash:18](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/splash_screen.dart:18), [Flutter home:55](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/home/home_screen.dart:55), [Expo providers:11](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/providers/app-providers.tsx:11), [Expo sync gate:127](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/providers/sync-status-provider.tsx:127), [Expo tabs:15](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/(tabs)/_layout.tsx:15).

### 32. Expo's scoped invalidation misses several dependencies

The newer table-to-query mapping is incomplete:

- Membership/plan changes do not invalidate Gold check-ins, although Gold classification joins both tables.
- Profile/plan/gym changes do not invalidate all revenue queries that join names/plans/gyms.
- Check-in changes do not invalidate Members, even though it displays last visit and supports a check-in-date filter.
- Gym/plan changes do not invalidate the `revenue-lookups` key used by revenue filters/editor.
- `membership-access-trend` is absent from the mapping, so the RPC report does not automatically follow membership changes.

Expo can therefore refresh one panel while leaving a related one cached. Flutter lacks the broad auto-refresh mechanism entirely, so results depend on which screen was explicitly refreshed or reopened. Treat this as a cache-dependency defect, not an aggregate-formula difference.

Source: [Expo queryGroups:18](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/providers/app-providers.tsx:18).

### 33. Flutter can apply responses from old filters to the current screen

Flutter loaders start asynchronous queries and commit results when they finish, without a request generation/filter identity check. Rapid filter/search changes can allow an older response to replace the current report; Members appends rows after reset and can mix results if requests overlap. Revenue pagination similarly appends an in-flight page without checking that its original filters are still current.

Expo separates query caches by applied filter keys, which prevents that particular old-key response from becoming the current result. This is a source-confirmed race opportunity, not a timing race reproduced on-device. Both still lack a transactional snapshot across all component queries; replication between separate SELECTs can temporarily make counts and rows disagree.

Sources: [Flutter member loader:134](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/members_screen.dart:134), [Flutter member append:216](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/members/members_screen.dart:216), [Flutter revenue result:471](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_screen.dart:471), [Expo query key:48](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/(tabs)/members/index.tsx:48).

### 34. Malformed data changes both visible records and check-in pagination

Flutter's strict date parsers throw on invalid dates. Check-in rows are skipped individually; some other loaders fail the whole result mapping and retain old data or empty state. Expo's shared `asDate` substitutes **now** for invalid nonempty dates, numeric conversion often substitutes zero, and nullable dates become null. Thus a corrupt row can appear to be a visit/payment today in Expo while being skipped/rejected in Flutter. Missing check-in timestamps are still rejected by both.

Flutter advances check-in pagination and decides `hasMore` from **parsed** row count. A malformed row can prematurely end the list. Expo changed `hasMore` to raw row count, but its screen still calculates the next offset from **parsed** items. The fix is incomplete: with 19 valid rows followed by 21 missing timestamps, Expo reaches an all-malformed full page and keeps asking for offset 19; Flutter stops at the first page. Reproduced by the harness.

An empty joined profile/gym name is another difference: Flutter keeps the relation if the name is non-null; Expo's truthiness check drops it. This can remove a member link or gym label for an empty-string name.

Sources: [Flutter check-in parse/pagination:129](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/check_ins/check_ins_screen.dart:129), [Expo check-in parse/hasMore:69](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/check-ins-repository.ts:69), [Expo next offset:32](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/(tabs)/check-ins/index.tsx:32), [Expo parser defaults:28](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/utils/parsing.ts:28), [Flutter revenue model:61](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/models/revenue_ledger.dart:61).

### 35. Failed loads can be presented differently, including zero versus old totals

Flutter usually shows a transient Snackbar, resets loading, and leaves the previous fields/rows intact. After a filter change fails, old totals can remain under new filter controls. Some initial failures look empty.

Expo analytics/comparison/check-in stats generally keep a visible error and default to zero/empty if the new query key has no data. However, the Revenue tab never renders `revenueQuery.error`: a first-load failure can look like **zero revenue and no transactions**. Member detail/history screens also differ in whether a background-refetch error is visible when previous data exists.

This is a conditional failure-state difference. Zero or stale totals should not be treated as successful report evidence.

Sources: [Flutter revenue catch:488](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_screen.dart:488), [Flutter analytics catch:252](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/revenue/revenue_analytics_screen.dart:252), [Expo revenue render:42](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/(tabs)/revenue/index.tsx:42), [Expo analytics fallback:33](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/revenue-analytics.tsx:33).

## F. Reports without a matching counterpart

### 36. Report coverage and metric definitions differ beyond the shared screens

**Expo-only membership-access analytics:** available through Admin Tools, backed by `get_admin_membership_access_trend`, with 7-day, 30-day, 12-week, and 12-month ranges. It is a remote RPC, unlike the local SQLite shared reports. It counts package-based usable access, includes family users, excludes day-pass types, and filters by selling gym. Weekly/monthly active people are an end-of-period snapshot; new activations are summed across days. These are not the same metric as revenue's new-membership charge count, check-in visitors, or the dashboard's looser active count. Historical rows can be estimated or stored snapshots.

The newer SQL adds current `is_active` requirements and explicit Bucharest conversions to historical event comparisons. Earlier migration definitions are superseded if the newer migration is deployed. Existing nonestimated snapshots are retained; mutable current membership/family data still influences reconstructed dates. No Flutter screen provides an equivalent report.

**Flutter-only Performance Monitor:** reachable by long-pressing the dashboard title. It includes business metrics, table metrics, slow queries, database size, connections, cache hit ratios, and real-time monitoring via RPCs. Expo has no matching screen/service for the performance report.

**Flutter-only Products:** code includes stock, sales/payment KPIs, top products, employee sales/transactions, and stock-movement reports with gym/employee/product/reason/date/low-stock filters. No active navigation reference to `ProductsScreen` was found, so it is a code-coverage gap rather than a proven normal-user route. Expo has no equivalent implementation.

**Unused generic analytics helpers:** both codebases contain legacy revenue/membership/payment/check-in RPC helpers. Expo has no callers for its `analyticsService`. Date parameters are UTC ISO instants in Expo but potentially offset-free local strings in Flutter; the actual result difference depends on those RPC argument types and session timezone. This is not the code used by the shared Revenue Analytics screen.

Sources: [Expo Admin Tools:9](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/admin-tools.tsx:9), [access repository:9](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/repositories/membership-analytics-repository.ts:9), [latest access predicates:224](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/supabase_migrations/20260813110000_atomic_membership_ledger_and_access_fixes.sql:224), [period aggregation:647](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/supabase_migrations/20260808090000_add_membership_access_analytics.sql:647), [Flutter Performance:39](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/performance/performance_screen.dart:39), [Flutter Products:32](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/screens/products/products_screen.dart:32), [legacy Flutter analytics:123](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/lib/services/analytics_service.dart:123), [legacy Expo analytics:31](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/services/analytics-service.ts:31).

## Date picker interaction comparison

The old “Android cannot select the end date” finding no longer applies. Expo now uses a shared calendar range dialog on both platforms, with draft start/end and Apply/Cancel. Flutter uses Material's range picker. Neither current implementation applies a half-complete range as the actual report filter.

| Flow | Flutter | Expo | Data relevance |
|---|---|---|---|
| Revenue / Analytics / member-date filters | 2020-01-01 through today | Same bounds | Boundary interpretation still differs (#1); inner picker applies a draft, outer filter applies the report |
| Check-in stats / Gold | 2024-01-01 through today | Same bounds | Android end-date issue is fixed |
| Period comparison | 2020 through end of current month; clamps existing end | Same declared bounds, no range clamp | Immediate Apply can preserve disallowed future end (#7) |
| Membership form | 2020-01-01 through 2030-01-01 | Through 2030-12-31 | Extra selectable dates (#8) |
| Open empty custom range | Flutter framework chooses initial calendar page | Expo explicitly defaults to minimum date, often January 2020 | More navigation; selecting a wrong year is an interaction risk, not a SUM difference |
| Range restart | Framework-managed | First tap after a complete range starts a new range; earlier second tap resets start | Requires a completed second selection before Apply |
| Cancel | Discards picker selection | Discards picker selection | Expo Check-in Stats sets the preset label to Custom before opening; Cancel can leave that label with the previous range |
| Locale / week start | App provides no explicit picker locale; framework default applies | Romanian month/day names and Monday first | Presentation difference; report SQL week buckets start Monday in both |
| Month/year selection | Framework controls | Custom month/year chooser | Native interactions not exercised |

Source for Expo draft, bounds, locale and empty initialization: [calendar-dialog.tsx:19](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/components/calendar-dialog.tsx:19). Preset-label cancel behavior: [check-in-stats.tsx:40](/Users/alex/Desktop/kratos_apps/kratos-gym-admin/kratos-admin-expo/src/app/check-in-stats.tsx:40).

## Matching logic and shared inconsistencies

These distinctions matter because not every surprising number is a Flutter/Expo difference:

| Area | Current matching behavior / shared limitation |
|---|---|
| Dashboard active count | Current SQL is now equivalent: distinct owner/family users, uncanceled, unfrozen, nonnegative days left. Neither checks `is_active`, package/day-pass kind, or future start. The old audit's dashboard-definition mismatch is fixed. |
| Dashboard total members | Both count all profiles, including staff/admin profiles. |
| Dashboard WAU/MAU/yesterday DAU | Both read `admin_analytics_summary` row `current`; freshness depends on the backend summary. |
| Dashboard monthly revenue | Both have a lower month boundary and **no upper boundary**, so future-dated charges after month start can count. Deletion and timezone differ as described above. |
| Main revenue filters | Same gym/payment/plan/search fields; same escaped LIKE handling. Payment filter is exact-case, but cash/card aggregates lowercase values in both. |
| Zero/positive amounts | Both have zero and `>0` filters. “non_zero” actually excludes negatives. Expo no longer uniquely provides this feature. |
| Refunds | Main revenue, analytics, dashboard and period comparison sum charges only. Member revenue history includes all entry kinds, excludes deleted rows from total, and subtracts refund amounts in both. They are gross versus signed-history views. |
| Member revenue history | Same owner/family membership association and direct client-ID lookup. Both list deleted transactions and include them in displayed transaction count while excluding their amounts from the net total. |
| “Unique members” in period comparison | Both count distinct `memberships.user_id` through `membership_id`, not distinct `client_user_id`; walk-ins/unlinked charges may add revenue without adding a member. Family users are not separately counted here. |
| New memberships / day passes / upgrades | Same source-based cases and same two hard-coded day-pass plan IDs. These count ledger rows, not distinct new customers or access activations. |
| Period plan ranking | Both use an inner plan join and exclude product-source rows, whereas overall totals can include product/no-plan charges. Rankings need not sum to the overall total. |
| Analytics gym chart | Both deliberately ignore the selected gym for the by-gym chart while filtering plan/trend/header totals. The gym donut total can exceed the filtered header without a cross-app bug. |
| Missing dates in trends | Both group existing rows only, without filling zero-activity dates/weeks. Equal point spacing can conceal calendar gaps. |
| Check-in statistics | Both count all statuses; busiest hours use local hours; both take top five hours/gyms. Gold/Silver reports require `status='success'` and recognized current plan tier, so totals differ from general check-ins. |
| Gold historical classification | Both join current membership/plan tier, not a tier captured at check-in time. Plan changes or deleted memberships can change old results. |
| Members and family access | Both members-list queries select owner memberships only. Detail/dashboard include family memberships. A family member can look membership-less in the list but have access in detail/dashboard. |
| Member detail | Same owner/family membership SQL and 50 newest check-ins; the header's active badge still ignores `is_active` and future start in both. |
| Search/pagination | Both member searches debounce 500 ms; revenue search requires submit/button. Both use page size 20 and OFFSET pagination without an ID tiebreaker, which can shift rows when data changes. |
| CSV | Same 11 columns, UTF-8 BOM, local display dates, 2 decimal amounts, 1,000,000-row cap, and report filters. Expo also escapes payment method; Flutter writes it raw, only relevant for malformed values containing CSV delimiters. Filtering, not layout, is the normal cause of differing exports. |
| Percent change | Both use `(current-previous)/previous`, with 100% for positive current when previous is zero and 0 otherwise. Neither normalizes totals by number of days. |
| Date/currency formatting | Many legacy labels are English-month/en-US-like; new Expo calendar labels are Romanian. Dashboard rounds revenue to whole RON in both, while detailed reports keep cents. No currency conversion is performed by either aggregate. |
| Connectivity | Shared reports use separate local SQLite caches; plan/gym admin forms use Supabase. The schemas match, but sync rules, auth identity, configuration, replication progress, and deployed binaries were not verified. |

## Corrections to the older audit

Do not carry these earlier findings forward unchanged:

- Dashboard active-membership SQL and its label now match Flutter again.
- Expo uses a proper shared range picker; the earlier Android start-only path is gone.
- Gold date-only values no longer use `toISOString().slice(0,10)`; the remaining disagreement is Flutter UTC versus Expo local reporting.
- Expo membership saves/deletes now use atomic RPCs. Flutter still uses independent requests.
- Expo now excludes deleted charges consistently across its principal live-revenue reports; Flutter still differs.
- Expo member usability/ranking filters changed, and the new inactive OR defect needs its own fix.
- Expo now uses the Gorhom bottom-sheet implementation, so the earlier “fixed modal/no gestures” description is stale.
- Invalidation is now scoped by tables, but its dependency coverage is incomplete (#32).
- The later SQL migration explicitly converts relevant historical timestamps to Europe/Bucharest. The old migration's bare casts are not the effective implementation if both migrations were deployed.

## Suggested order for achieving comparable reports

1. Define a single report contract: business timezone, inclusive calendar dates versus rolling instants, charge/refund policy, deleted-row policy, and which metric “Active” denotes. Apply it to both clients rather than assuming Flutter's current output is the reference truth.
2. Fix Expo's inactive OR grouping, zero-total donut, stale memoized report dates, missing cache dependencies, and parsed-row pagination offset.
3. Make Flutter use the agreed date/deletion/member predicates and the same transactional membership RPCs, after confirming the deployed RPCs/constraints.
4. Align amount parsing and integer-cent conversion, and prevent silent normalization of unsupported plan tiers.
5. Run both apps against one frozen test dataset covering midnight, month/year/DST boundaries, overlap/family/future/frozen/canceled/inactive memberships, deleted/refund/zero charges, repeated edits, and failures. Compare IDs and integer-cent aggregates before comparing formatting or charts.

Run the audit probes from the repository root:

```sh
node audits/2026-09-13-report-parity/verify.cjs
TZ=Europe/Bucharest dart audits/2026-09-13-report-parity/dart-probes.dart
```

The probes intentionally assert the current differences. They should be converted into equality/contract tests when fixes are implemented.
