# CLAUDE.md

Sablier: an Android-only Flutter app that rations distracting apps (Instagram, TikTok…) to a few minutes per hour,
like the paid AppBlock "hourly limit": enough to answer messages, not to doomscroll. The UI is in French.

## Toolchain

Same as LLLearner: Flutter 3.47.7 (`~/SDKs/flutter-3.47.7`; the older `~/SDKs/flutter` can't resolve the project),
Android SDK in `%LOCALAPPDATA%/Android/Sdk` (AVD `Medium_Phone_API_36.0`), Android Studio's JDK:

```sh
export PATH=~/SDKs/flutter-3.47.7/bin:$LOCALAPPDATA/Android/Sdk/platform-tools:$PATH \
  ANDROID_HOME=$LOCALAPPDATA/Android/Sdk JAVA_HOME="$LOCALAPPDATA/Programs/Android Studio/jbr"
flutter analyze && flutter test                    # Dart: model, formatting, channel parsing
(cd android && ./gradlew :app:testDebugUnitTest)   # Kotlin: the window arithmetic (HourglassTest)
dart format -l 120 lib test                         # 120-col lines
flutter build apk --debug --target-platform android-x64      # emulator
flutter build apk --release --target-platform android-arm64  # → build/app/outputs/flutter-apk/app-release.apk
```

Grant the three permissions without the UI (the debug package is `com.eylexander.sablier.debug`):

```sh
adb shell appops set com.eylexander.sablier GET_USAGE_STATS allow
adb shell appops set com.eylexander.sablier SYSTEM_ALERT_WINDOW allow
adb shell cmd notification allow_listener com.eylexander.sablier/com.eylexander.sablier.Hush
adb shell appops set com.eylexander.sablier ACCESS_RESTRICTED_SETTINGS allow   # if the toggle is greyed out
```

## Releasing (same scheme as LLLearner, Re-TCAT and Audio Cutter)

- Package `com.eylexander.sablier`, distributed through the user's F-Droid repo (`../fdroid`), listing in
  `../fdroid/metadata/com.eylexander.sablier/{fr-FR,en-US}/`. Push a `v*` tag: `.github/workflows/release.yml` calls
  the shared `Eylexander/fdroid/.github/workflows/flutter-apk.yml` (versionCode = run number, so keep the file's name).
- Release key: `.secrets/` (git-ignored), the shared key, SHA-256 `db171ead…`. CI gets it from the
  `RELEASE_KEYSTORE_BASE64` / `RELEASE_KEYSTORE_PASS` secrets. Never regenerate or lose it.
- Debug builds are `com.eylexander.sablier.debug` ("Sablier (dev)").
- Launcher icon: adaptive vector only (`res/drawable/ic_launcher_*.xml`, an hourglass on sand `#9C5B16`), same paths
  in `tool/icon.svg` for the store PNG.

## Architecture

The enforcement is native (it must run without the Flutter UI); Flutter is only the settings and the pause screen.

- **Rules** (`lib/guard.dart` `Rule`, `Hourglass.kt` `Rule`): name, apps, `budget` minutes per `window` minutes,
  `on`. A rule's apps share one budget. The window **slides**: a minute used at 14:10 is free again at 15:10, so
  there's no boundary to game (5 min at 13:58 then 5 more at 14:00). Stored as JSON in the `sablier`
  SharedPreferences (key `rules`), written only by Flutter through the channel, read by both sides. Keep the two
  `Rule` classes' fields in sync.
- **Counting** (`Hourglass.kt`): from Android's usage events (`ACTIVITY_RESUMED` / `ACTIVITY_PAUSED`,
  `SCREEN_NON_INTERACTIVE`), never by timing on our side, so keyboard popups, the notification shade and screen-off
  are handled by the system. `Hourglass` holds the pure arithmetic (`used`, `freeAt`, `sessions`), covered by
  `HourglassTest`.
- **Pause**: once the budget is spent, `Rules.status` stores `until.<id>` = the first moment a whole minute is back
  (`freeAt`), so the app doesn't come back a few seconds at a time. While paused, the UI won't edit, delete or switch
  off the rule (self-control: loosening a rule must wait for the pause to end).
- **Guard** (`Guard.kt`, a plain class that Hush runs): every second while the screen is on, reads the usage events
  since the last poll (`Hourglass.front`, a few seconds of overlap) to follow the front app. **No accessibility
  service**: with one on, Instagram scrolls noticeably slower (v1.0–1.2 had one; users uninstalled over it). On each
  change of front app (or screen off and on) it checks the rules, then again when the time left runs out (a toast one
  minute before). A spent rule whose app is on screen opens `MainActivity` with the `paused` extra; the
  `SYSTEM_ALERT_WINDOW` permission ("display over other apps") is what lets it start an activity from the background
  (checked on API 36). Pressing Home first would trigger the 5 s app-switch delay, so it doesn't. When the rule is
  already paused (`until.<id>` stored), it covers the app at once. About 0.1 % CPU.
- **Hush** (`Hush.kt`, a NotificationListenerService): the system keeps it bound, so it hosts Guard. While a rule is
  paused, snoozes its apps' notifications until `until`, when Android posts them again. Tapping one would open the
  app straight into the message (Instagram marks it read) before Guard can cover it. Looks only at the package, never
  the content.
- **Channel** `sablier/guard` (`MainActivity.kt`): `rules`, `setRules`, `status` (used, left, until, sessions per
  rule), `apps` (launchable apps; needs the MAIN/LAUNCHER `<queries>`), `icon` (96 px PNG), `access`, `openUsage`,
  `openOverlay`, `openNotifications`, `openAppInfo`, `open` (a pause screen suggestion's dialer, music app or
timer), `takePaused` (cold start), `home`; and `paused` from Kotlin
  (`onNewIntent`). The activity is `singleTask` so the pause screen reuses the running engine.
- **UI**: `main.dart` (home: permission card, rule cards, refresh every 5 s while visible), `rule.dart` (editor),
  `pause.dart` (countdown; back and "Fermer" go to the launcher, not back to the app), `widgets.dart` (`Timeline`:
  the window as a strip, time used drawn as sand that slides out on the left). Material 3 from the wallpaper
  (`dynamic_color`), sand seed otherwise; never hardcode colors.
- The first launch creates "Réseaux sociaux" (5 min per hour) with the installed apps of `social` in `guard.dart`.

## Limits

- Turning notification access off, or uninstalling, ends all limits. No device-admin lock on purpose.
- Split screen / picture-in-picture: the usage events of the second app close the first one's session; usage may be
  undercounted there.
