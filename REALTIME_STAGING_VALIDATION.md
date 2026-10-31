# Realtime + current tablet UI integration

PR #4 targets staging. Do not release to main before the device checks below pass.

## Builds

CI builds the staging web app and a debug APK, using config/staging.json. Download
`shiney-gestro-staging-apk` from the successful CI run. Its Android ID has a `.staging`
suffix, so it can coexist with production. Confirm the orange STAGING banner before pairing.

Local web check:

```
cd apps/tablet
flutter create --platforms=android,web --org com.shineygroup --project-name foodtro_staff . --no-overwrite
flutter pub get
flutter analyze --no-fatal-infos
flutter build web --dart-define-from-file=config/staging.json
```

The source preserves FlutLab's production default for existing builds. Always pass
config/staging.json when testing; installing a debug build alone does not select staging.

## Two-device acceptance (not yet verified on physical devices)

Use disposable test sessions and items in staging. Do not create live financial transactions.

1. Pair Service and Kitchen (then Bar) to the same staging restaurant. Send an order;
   check Kitchen/Bar and Mission Control update promptly, without a manual reload.
2. Disconnect Kitchen Wi-Fi, send an order on Service, reconnect. Check the missed
   order appears after the channel rejoins. Disable Realtime in a test harness and
   check the 60-second refresh also recovers it.
3. Change/delete a test menu item and test option; check Service and POS reload.
4. Send a staging POS takeaway with both food and drinks; check each station receives
   its own lines. Mark ready and verify Service, Done orders and Active tables agree.
5. Use a second staging restaurant. Its orders must not appear on either first-restaurant
   tablet. Switch roles/re-pair and verify old listeners/timers stop.
6. At landscape tablet width >=1000 logical pixels, check four full-width columns in
   Active tables and Done orders; check the station header remains reachable with no orders.

## Migration reconciliation

All 127 recorded staging migration versions were recovered/represented in Git (audit
2026-10-31). Preserve existing history; do not use `migration repair --status reverted`
just to make a deploy pass. The currency/rate migration had no recorded statements and
is explicitly reconstructed. The obsolete temporary file-handoff migration is a no-op
in fresh installs; its old embedded secret and RPCs must not be replayed.

After recovering four additional production feature migrations, production has 56 historical version IDs absent from the staging-derived canonical
history, often for the same named features. Do not apply the staging history to production
or blindly mark those versions applied. Compare recorded SQL and current schema, prepare
an audited version mapping/schema diff, back up migration history, and reconcile before
any production database deploy. This PR does not change production migration history.

## Capacity audit

On 2026-10-31 production database size was 57 MB and its organization plan was Free.
Supabase's published default Free Realtime limit is 200 concurrent connections:
https://supabase.com/docs/guides/realtime/limits
This is not a 100-restaurant capacity certification. Load test actual devices, queries,
message volume and polling before rollout; no paid plan changes were made.
