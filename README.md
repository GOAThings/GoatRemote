# GoatRemote

A remote for Android TV, Google TV and Apple TV, on the iPhone and on Android phones, in the style of Apple's TV
remote. All the TVs at home show up in one list, so switching between them is one tap.

## Features

- **Finds the TVs** on your home network (Android TV, Google TV and Apple TV) and pairs with the code shown on
  the TV: Android TV with the same protocol as the Google TV app, Apple TV with the one Apple's remote uses (a
  4-digit PIN). It works with any app on the TV, not only ours.
- **Touch surface**: swipe to move, tap to select, hold for a long press, or turn on arrows on the edges.
- **Buttons**: play/pause, back, home, power, mute, rewind and fast forward; under More, volume, channels, search,
  guide, info, subtitles, audio track, last channel, input, settings, stop, previous, next and the numbers.
- **Volume**: the phone's volume buttons change the TV's volume while the app is open. With GoatLauncher on the
  TV, the volume goes through it (see below). An Apple TV can only change the volume over HDMI-CEC with a
  soundbar or receiver; when it can't, the app says so.
- **Keyboard**: opens on its own when the TV shows a text field, with what's already typed there; Enter on the
  phone is Enter on the TV (also on Apple TV).
- **Apps**: with [GoatLauncher](https://github.com/GOAThings/GoatLauncher) on the TV, all its apps show
  up with their banners; without it, the apps you've opened on that TV. On Apple TV, the TV's own app list, with
  App Store icons.
- **Several TVs**, and on the iPhone, Siri and Shortcuts ("press a TV button").
- English and Portuguese.

### GoatLauncher and the SHIELD

On the SHIELD (Android 11), a volume key from a phone remote can restart the box while an accessibility service
watches the remote's buttons, which GoatLauncher does when remote buttons are set to open apps. It's a bug in
Android itself (the Google TV app triggers it too). With GoatLauncher 0.8.7 or newer on the TV, GoatRemote changes
the volume through GoatLauncher instead, the same way the physical remote does.

## Install

GitHub Actions builds both apps on every change (Actions → latest run → Artifacts):

- **Android**: `GoatRemote.apk` (Android 8 or newer).
- **iPhone**: `GoatRemote.ipa`, unsigned: sign it with your own certificate and sideload it (iOS 17 or newer).

## Build

- `ios/`: the iPhone app (SwiftUI, project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)).
  `ios/RemoteCore` is the protocols in plain Swift (also builds and is tested on Linux).
- `android/`: the Android phone app (Kotlin, Jetpack Compose). Open it in Android Studio, or:

  ```bash
  cd android && ./gradlew assembleRelease
  ```

  Release builds are signed with a key that is not part of this repository (without it, with the debug key).
- `tools/AtvTool.java`: the Android TV protocol from both sides, as a fake TV for the tests or a client for a real
  TV.

GitHub Actions runs the protocol tests and both apps against the fake TV (iPhone simulator, Android emulator).

## License

GoatRemote is free software under the [GNU General Public License v3.0](LICENSE).

The license covers the code only. The names "GOAT" and "GoatRemote" and their logos are not licensed: forks must
use their own name and artwork.
