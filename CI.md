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
