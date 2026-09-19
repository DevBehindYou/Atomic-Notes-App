# App session checkpoint - September 19, 2026

This repository has **uncommitted** changes that have **never been analyzed,
formatted, tested or built with Flutter**. The user requires GitHub Actions
builds: there is no local Flutter SDK and not enough disk space to install one.
Nothing was committed, pushed or deployed. Resume only on a new user request.

Latest hosted verification is historical: commit
`a921ec1ff3eba82494dd2705c93c3858a970a505`, run `34875284967` (42 tests, clean
analysis, debug APK with placeholder credentials). It does not cover this tree.

## Uncommitted changes

- API client, `Note` model, `cred.example.dart`: public build settings, server
  versions and cursors, persistent request IDs, partial-result handling.
- `notes_repository.dart`:
  - all Hive writes go through one serialized queue (`_persist`), fixing the
    race where an older acknowledgment could overwrite a newer edit; writes for
    another account or a removed note are dropped;
  - a sync sends up to five batches of 20 and returns false with a count if
    changes remain;
  - a version conflict keeps the local edit as a "(conflict copy)" note, resets
    the pull cursor and re-pulls so the other version arrives;
  - the pull cursor is stored in Hive per account and reset after vault unlock;
  - repaired a byte that was not valid UTF-8 (cp1252 em dash) that could break
    the build.
- Sign-in and sync failures are now written to logcat (`adb logcat -s flutter`) with error codes only, and
  the sign-in screen has friendlier messages for the Server's sign-in error codes. Uncommitted, not compiled.
- New `test/note_test.dart` (wire format only). The repository logic itself has
  no automated test (singleton `ApiClient` + Hive).
- New `.github/workflows/release-android.yml` (manual signed release; never run)
  and a matching section in `CI.md`.

## Signed release status (September 19)

Release key and GitHub secrets/variables exist (values only on the owner's disk and in GitHub). The first
run built the signed APKs but its verification step failed on a `grep` of `apksigner` output; the
workflow is fixed locally (uncommitted) and must be pushed and re-run. See the workspace handoff.

## Before release

Push and read the **Flutter verification** run (analysis, `dart format` issues,
tests, debug APK); fix what it reports; save the resolved `pubspec.lock`. Then
create the release key, set the GitHub secrets/variables described in `CI.md`,
run **Signed Android release**, and register the printed certificate SHA-1 in a
Google **Android** OAuth client for package `com.notes.atomic`. Never distribute
the placeholder/debug build as production. Real sign-in and sync are verified
only by the phone checks in `Project-Docs/10-deployment-guide.md`, section 10.

API base: `https://atomic-notes-server-gde2e.vercel.app/api`. The App's Google
server client ID must be the Server's **Web** client ID. Never embed a Google
client secret, token encryption key or admin key in the App. Atlas and Google
Cloud are not configured yet. Full context: `Project-Docs/09-agent-handoff.md`.
