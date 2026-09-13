# Membership freeze

The client profile's former add-membership button now opens **Înghețare abonament**. Editing existing memberships remains available through each card's edit button.

## Employee app behavior carried over

Reference: `kratosemployeeapp/lib/data/repositories/user_profile_repository.dart` (`freezeMembership`, `unfreezeMembership`, `scheduleMembershipFreeze`, `cancelScheduledFreeze`), its `user_profile_page.dart` controls, and its PowerSync upload mappings.

- Only memberships owned by the displayed client can be managed. Family dependants use the owner's profile.
- Active, unfrozen, uncanceled memberships can be frozen manually or for 5 days. A 14-day freeze requires `duration_months == 3`; plan duration is the fallback only when membership duration is null.
- Freeze preserves `max(days_left ?? 0, 0)`, sets the freeze type, actor and timestamp, and leaves the current expiry date unchanged. Automatic freeze timestamps use elapsed 24-hour days.
- Resume restores `max(days_left_when_frozen ?? 0, 0)`, sets expiry to local midnight today plus that number of elapsed days, and clears every freeze field. Zero means the last valid day. Dart's elapsed-duration behavior across DST is preserved.
- Each immediate freeze/resume records a `paused`/`resumed` membership event with actor, plan, notes, preserved days and old/new dates.
- Scheduled freezes allow 5 or 14 days, start strictly after today, and start no later than the membership's expiry date. Only one pending schedule is allowed per membership. A pending schedule must be canceled before freezing immediately or scheduling another freeze.
- Cancellation marks the existing schedule `canceled` with actor, timestamp and notes. Scheduling/canceling does not change membership dates or create a pause/resume event immediately.
- Employee timestamps retain the existing local `YYYY-MM-DD HH:mm:ss` format; schedule and expiry dates use `YYYY-MM-DD`.

## Storage and synchronization

The new workflow saves through PowerSync, like the employee app. Membership changes and their history entries share one local SQLite transaction so an event-write failure rolls back the membership change. The connector accepts only freeze-related membership patches, event inserts and freeze schedule inserts/patches. Stable IDs and upserts make retrying an interrupted upload repeatable; explicit nulls clear server freeze metadata on resume. Other admin write paths continue using their existing Supabase mutations.

The profile displays local changes immediately and reports synchronization errors with a retry action. A local save is queued for upload; it is not a guarantee of server acceptance. The remote upload follows the employee app's separate Supabase requests rather than a server-side transaction.

Automatic start/resume relies on the **existing backend automation used by the employee app**. This change adds the employee app's `membership_freeze_schedules` table to the local schema; that table must also be included in this user's PowerSync downloads. No server schema, RLS policy, sync rule or scheduled job is deployed by this change. Automatic server execution and production permissions were not exercised against real memberships.

No new native dependencies were added. Reload the development app to initialize the updated local schema.

## Verification

- Real SQLite tests cover manual/5-day/14-day freeze, zero and negative balances, resume metadata clearing, scheduling bounds, cancellation, duplicate prevention, ownership and rollback/retry.
- Upload tests cover boolean conversion, explicit nulls, stable IDs on retry, rejected unsupported writes and schedule creation/cancellation.
- UI tests cover mode eligibility, failed-save draft preservation, retry, resume and empty profiles.
- The shared Flutter admin report parity harness continues checking its 157 cases. The additional employee-only schedule table is explicitly excluded from the shared-table inventory comparison.
