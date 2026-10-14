# Changelog

## 0.2.0 – 2026-10-14

- A second build for 64-bit devices with iOS 14–17 (iPhone X and newer), from the same source tree: the `.deb` with
  `iphoneos-arm64` in its name for rootless jailbreaks (palera1n, Dopamine; it installs into `/var/jb`) and
  `Kicker-<version>-arm64.ipa` for TrollStore. Not tried on a device yet.
- On iOS 7 and newer the app draws the glossy iOS 6 bars, the black glass tab bar with the green selected tab,
  bordered bar buttons and rounded grouped tables itself, stays in light mode and opens the player full screen, so it
  looks the same as on the iPad 2. The player's controls, the chat and the grids keep clear of the notch and the home
  indicator.
- The 32-bit build gets the same look on devices with iOS 7–10.

## 0.1.1 – 2026-10-14

- Settings → About has a "Support the development" row that opens the author's Ko-fi page. The app stays free.
- Kicker is in the repository `http://repo.samcejko.eu/` now (Cydia, Sileo, Zebra, Installer): add it as a source to get updates.

## 0.1.0 – 2026-10-04

First version.

- Live channels (most watched, by category, by language), categories with their live channels and top clips,
  search for channels and categories
- Player through the in-app proxy: quality choice, full screen, sound in the background, lock-screen controls
- Live chat (read only) over Kick's WebSocket: badges, Kick and 7TV emotes, replies, subscriptions, gifts, hosts,
  moderation; the last messages show as it opens
- Past broadcasts with seeking, resume and the chat replay; clips
- Channel pages, favourites on the device
- WebP pictures decoded in the app (libwebp)
- Dark (default) and light theme, English and Czech
