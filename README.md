# GoatRemote

A remote for Android TV and Google TV on the iPhone, in the style of Apple's TV remote. Apple TV support is
being worked on.

- Finds the TVs on your home network and pairs with the code shown on the TV (the same protocol as the Google TV
  app, so it works with any app on the TV, not only ours).
- Touch surface (swipe, tap, hold), or arrows on the edges; play/pause, back, home, power, volume and mute.
- The iPhone's volume buttons change the TV's volume while the app is open.
- The keyboard opens on its own when the TV shows a text field.
- With [GoatLauncher](https://github.com/GOAThings/GoatLauncher-Releases) on the TV, all its apps show up with
  their banners; without it, the apps you've opened on that TV.
- More keys (channels, guide, info, subtitles, audio, numbers…), several TVs, Siri and Shortcuts.

## Build

- `ios/`: the iPhone app (SwiftUI, project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)).
  `ios/RemoteCore` is the protocol in plain Swift (also builds and is tested on Linux).
- `tools/AtvTool.java`: the protocol from both sides, as a fake TV for the simulator tests or a client for a real TV.
- `android/`: the start of an Android phone version.

GitHub Actions builds an unsigned `GoatRemote.ipa` (artifact): sign it with your own certificate to install it.

## License

GPL-3.0 ([LICENSE](LICENSE)). The names "GOAT" and "GoatRemote" and their logos are not licensed: forks must use
their own name and artwork.
