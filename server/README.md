# Patched scrcpy server

`0001-allows-content-mode-switch.patch` contains the two server changes from
[upstream PR #7055](https://github.com/Genymobile/scrcpy/pull/7055).
On Android 17 (SDK 37) and later, virtual displays with system decorations use
`ALLOWS_CONTENT_MODE_SWITCH` instead of `SHOULD_SHOW_SYSTEM_DECORATIONS` and
`OWN_CONTENT_ONLY`, allowing desktop eligibility. Other cases retain upstream behavior.

`.github/workflows/server.yml` downloads official scrcpy source, applies the patch,
and builds only the Java/dex server using Android platform 36 and the runner's
latest installed build-tools (installing platform 36 and build-tools 36.0.0 if needed).
It verifies `classes.dex`, creates a SHA-256 checksum, and uploads both files as
workflow artifacts. No upstream version string is changed: the default source is
5.0.1, matching the stock scrcpy 5.0.1 client.

To rebuild locally, extract official scrcpy v5.0.1 source and run from its root
(replace `/path/to/dex-script` and the SDK path):

```sh
patch --batch --forward --fuzz=0 -p1 < /path/to/dex-script/server/0001-allows-content-mode-switch.patch
cd server
ANDROID_HOME=/path/to/android-sdk ANDROID_PLATFORM=36 ANDROID_BUILD_TOOLS=36.0.0 \
  BUILD_DIR="$PWD/out" ./build_without_gradle.sh
```

Install Android platform 36 and build-tools 36.0.0 in that SDK first. The result is
`server/out/scrcpy-server` within the upstream source tree.

Push a tag such as `server-v5.0.1-dex1` to create/update a release in this repository
with assets named `scrcpy-server` and `scrcpy-server.sha256`. The upstream version
is derived from the tag; the `-dex1` suffix identifies the patch revision. Manual
runs accept `scrcpy_version` (default `5.0.1`) and upload artifacts without publishing
a release. Other versions require patch compatibility and a matching client.
The `dex` CLI downloads the release asset and selects it via `SCRCPY_SERVER_PATH`.
