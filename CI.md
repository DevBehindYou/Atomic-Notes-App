# GitHub workflows

## Flutter verification

Push `.github/workflows/flutter-ci.yml` in this repository, then open
**Actions → Flutter verification → Run workflow** (pushes to main and pull
requests also run it). No local Flutter SDK or Pages configuration is needed.

The hosted workflow resolves packages, treats all analyzer findings as fatal,
runs the existing tests, and builds a debug APK. The APK uses placeholder
API/OAuth configuration and is not a production release. APK upload remains
required; diagnostic upload failure is reported without masking build errors.
Artifacts expire after one day. If quota is full, clear obsolete artifacts
in GitHub before rerunning. No workflow deletes existing artifacts.

## Signed Android release

**Signed Android release** (`.github/workflows/release-android.yml`) is manual
only. It analyzes, tests, builds `--release --split-per-abi` APKs, checks that
none is signed with the Android debug key, and uploads them as a 14-day
workflow artifact. It publishes nothing: download the artifact and attach the
files to a GitHub Release yourself. It stops with an error, and never falls
back to the debug key, if any signing secret is missing.

One-time setup (do this on your own machine; never paste these values into a
chat or commit them):

1. Create a release key. Keep the file and both passwords somewhere safe:
   losing them means you can never update an installed app.
   ```bash
   keytool -genkeypair -v -keystore atomic-release.jks -alias atomic -keyalg RSA -keysize 2048 -validity 10000
   ```
2. Base64-encode it and add the four **secrets** under *Settings → Secrets and
   variables → Actions → Secrets*: `ANDROID_KEYSTORE_BASE64`,
   `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
   ```bash
   base64 -w0 atomic-release.jks
   ```
3. Add two **variables** (public values) under the *Variables* tab:
   `API_BASE_URL` (`https://atomic-notes-server-gde2e.vercel.app/api`) and
   `GOOGLE_SERVER_CLIENT_ID` (the Server's **Web** OAuth client ID).
4. Run **Actions → Signed Android release → Run workflow**. The job summary
   prints each APK's certificate **SHA-1**. Register that SHA-1 in the Google
   Cloud **Android** OAuth client for package `com.notes.atomic`, otherwise
   Google sign-in fails on the release build.

Nothing here has been run yet. The first run is the first proof that it works.

## Showcase site

**Deploy showcase site (GitHub Pages)** uploads only `docs/`. It does not
compile Flutter. Before running it, set **Settings → Pages → Build and
deployment → Source → GitHub Actions** in this repository. A missing Pages
site or inaccessible Pages configuration produces HTTP 404. If the setting
is unavailable, check repository visibility and plan eligibility.

See [GitHub's Pages setup instructions](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).
Automatic enablement requires additional token permissions; this workflow
uses the default token and expects the owner to configure Pages first.

Server and Community typechecks now run in their own repositories. Require
successful runs for all three project commits before integration testing.
