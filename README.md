# GoatRemote

A remote for Android TV, Google TV and Apple TV, on the iPhone and on Android phones, in the style of Apple's TV
remote. All the TVs at home show up in one list, so switching between them is one tap.

- Finds the TVs on your home network and pairs with the code shown on the TV: Android TV with the same protocol as
  the Google TV app, Apple TV with the one Apple's remote uses (a 4-digit PIN). It works with any app on the TV,
  not only ours.
- Touch surface (swipe, tap, hold), or arrows on the edges; play/pause, back, home, power, volume and mute.
- The phone's volume buttons change the TV's volume while the app is open (on Apple TV, only when it controls the
  volume over HDMI-CEC).
- The keyboard opens on its own when the TV shows a text field.
- With [GoatLauncher](https://github.com/GOAThings/GoatLauncher-Releases) on the TV, all its apps show up with
  their banners; without it, the apps you've opened on that TV. On Apple TV, the TV's own app list.
- More keys (channels, guide, info, subtitles, audio, numbers…), several TVs, and on the iPhone Siri and Shortcuts.

## Build

- `ios/`: the iPhone app (SwiftUI, project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)).
  `ios/RemoteCore` is the protocol in plain Swift (also builds and is tested on Linux).
- `tools/AtvTool.java`: the protocol from both sides, as a fake TV for the simulator tests or a client for a real TV.
- `android/`: the Android phone app (Kotlin, Jetpack Compose). Open it in Android Studio, or `./gradlew assembleRelease`.

GitHub Actions builds an unsigned `GoatRemote.ipa` (sign it with your own certificate to install it) and
`GoatRemote.apk`, and runs both apps against the fake TV (iPhone simulator, Android emulator).

## License

GPL-3.0 ([LICENSE](LICENSE)). The names "GOAT" and "GoatRemote" and their logos are not licensed: forks must use
their own name and artwork.
