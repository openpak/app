# Deploy: app

## Toolchain

Nothing here is system-installed; all of it lives under `~/development` and
`~/Android` and can be deleted without touching the machine.

| | |
|---|---|
| Flutter | `~/development/flutter` (3.47.2 stable) |
| Android SDK | `~/Android/Sdk` (platform 36, build-tools 36.0.0) |
| JDK | `~/development/jdk-21.0.12.1+1` — **required** |

The JDK line is not a preference. The system JDK here is 26, and the Android
Gradle plugin's `jlink` step fails on it (`Failed to transform
core-for-system-modules.jar`). Flutter is configured to use the 21 above via
`flutter config --jdk-dir`, so a plain `flutter build` works; a bare Gradle
invocation needs `JAVA_HOME` set to it.

```sh
export ANDROID_HOME=~/Android/Sdk
export PATH="$HOME/development/flutter/bin:$PATH"
```

## Running it

```sh
flutter pub get
flutter test
flutter run                     # against https://openpak.org
flutter run --dart-define=OPENPAK_BASE_URL=http://10.0.2.2:20010   # local stack
```

`10.0.2.2` is how the Android emulator reaches the host machine.

To put it on a phone:

```sh
flutter build apk --release --split-per-abi   # ~17 MB for arm64
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Release builds are signed with a stable keystore, so a new APK installs over
the previous one.

## The logo comes from the website

`assets/icon.svg` is a byte-for-byte copy of `website/web/static/icon.svg`, and
the Android launcher icons are rasterised from that same file. Nothing is
redrawn — a hand-made copy of a logo diverges the moment the real one changes,
and nothing notices. A test compares the two whenever the website repo is
checked out next door, and fails when they differ.

After the logo changes upstream:

```sh
cp ../website/web/static/icon.svg assets/icon.svg
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  rsvg-convert -w ${d##*:} -h ${d##*:} assets/icon.svg \
    -o android/app/src/main/res/mipmap-${d%%:*}/ic_launcher.png
done
```
