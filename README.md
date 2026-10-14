# Kicker – Kick for iOS 6

Unofficial, universal (iPhone + iPad) [Kick](https://kick.com) client for **jailbroken iOS 6.x** devices (armv7,
e.g. iPad 2), with a second build for **64-bit devices with iOS 14–17** (iPhone X and newer: rootless jailbreaks
and TrollStore) that keeps the same look. Live streams with the chat, past broadcasts with the chat replay, clips,
categories, search and favourites, drawn in the glossy iOS 6 look – dark like Kick by default, light if you like –
in English and Czech. No account needed: everything the app shows is public.

Why it is special: Kick's servers only speak today's TLS, which the iOS 6 networking stack cannot negotiate, and
Kick serves every picture as WebP, which iOS 6 cannot decode. The app ships its own TLS stack (Mbed TLS), a tiny
HTTP client, a WebSocket client for the chat and libwebp's decoder; the video goes to the system player through a
small HTTP server inside the app (127.0.0.1) that fetches the stream through that stack and cleans the playlists
of what the 2012 player does not know. No relay server: nothing leaves the device but the requests to Kick (and,
for the extra emotes, to 7TV).

## Features

- Live channels (most watched, by category, by language), categories, search for channels and categories
- Player with quality choice (automatic up to what the device decodes, source, 1080p … 160p, audio only), full
  screen, the chat next to or under the video, sound in the background, lock-screen controls
- Live chat (read only) with badges, Kick and 7TV emotes (animated ones too), name colours, replies,
  subscriptions, gifts and hosts, moderation (deleted messages, timeouts, bans), the last messages when it opens
- Channel pages: past broadcasts and clips (today, this week, this month, all time), the channel's social links;
  favourites kept on the device
- Web addresses in the chat, in titles and in channel descriptions can be tapped: kick.com opens in Kicker, YouTube,
  Twitch and TikTok in the sister apps Tubie, Twitcher and TikTak when installed, the rest in Safari (or Surfari)
- Past broadcasts with seeking, resume where you left off, and the chat replay in time with the video
- Light and dark theme, English and Czech

Tested on an iPad 2 (iPad2,2) with iOS 6.1.3. The iPhone layout is implemented but has not been tried on a real
iPhone yet; the 64-bit build has not been tried on a device yet either.

## Installing on the device

The easy way: add the repository `http://repo.samcejko.eu/` in Cydia (Sources → Edit → Add), Sileo, Zebra or Installer
and install Kicker from there; updates then come through the package manager. The app is free; if it is useful to you, you can support the development
at [ko-fi.com/samcejko](https://ko-fi.com/samcejko). By hand:

1. Cydia: **AppSync Unified** (repo `https://cydia.akemi.ai/`) and **IPA Installer Console** (BigBoss), plus
   OpenSSH for the helper scripts.
2. Download the `.ipa` or `.deb` of the latest [release](https://github.com/samcejko/kick-ios6/releases) (both
   carry the same build; the checksums are in the release notes).
3. Copy the `.ipa` to the device and run `ipainstaller -f Kicker-<version>.ipa`, or use iFunBox / 3uTools. The
   `.deb` works too (`dpkg -i`, then `su mobile -c uicache`) and installs into `/Applications`; do not keep both
   installed at once.

On iOS 14–17 (64-bit): with a rootless jailbreak add the same repository in Sileo or Zebra, or install the
`iphoneos-arm64` `.deb` with `dpkg -i` (it goes into `/var/jb/Applications`); without a jailbreak open
`Kicker-<version>-arm64.ipa` in [TrollStore](https://github.com/opa334/TrollStore). The same app, the same iOS 6 look.

`tools/gh-release.ps1 -RunDir packages\run-<id> -Sha <commit>` publishes a release from a downloaded CI run.

## Building (GitHub Actions)

No Mac needed. Every push runs `.github/workflows/build.yml` on Ubuntu with Theos, Mbed TLS and libwebp, twice from
the same sources:

- `ios6-armv7`: the iOS 9.3 SDK, deployment target 6.0 → `Kicker-<version>.ipa` and the `iphoneos-arm` `.deb`;
- `ios14-arm64`: `make package THEOS_PACKAGE_SCHEME=rootless`, the iOS 16.5 SDK, deployment target 14.0 →
  `Kicker-<version>-arm64.ipa` (TrollStore) and the `iphoneos-arm64` `.deb` (rootless, `/var/jb`).

The differences live in `src/Util/KCModern.m` (safe areas, the iOS 6 look of the bars on iOS 7 and newer,
full-screen modals) and in `tools/modern_bundle.py` (the arm64 bundle's Info.plist and launch screen). Each build
leaves its link map (`Kicker-link-<arch>.map`, an artifact) for reading crash reports.

Local helpers (Windows PowerShell, no git required; settings in `tools/local.json`):

```powershell
.\tools\gh-push.ps1 -Message "change"                   # push via REST API
.\tools\gh-build.ps1 -Download -Install                 # wait, fetch both builds, install on the iPad
.\tools\gh-build.ps1 -Download -InstallIPhone           # ... or the arm64 .deb on the iPhone (tools/iphone.ps1)
. .\tools\ipad.ps1; Get-IPadCrashLogs; Get-IPadSyslog   # debugging
```

URL scheme (other apps, or `uiopen` over SSH): `kicker:watch/<channel>` opens a stream,
`kicker:channel/<channel>` a channel page, `kicker:open?url=https://kick.com/<channel>` a channel by its web
address, `kicker:search?q=<text>` a search.

Debugging over SSH: with a file named `debug` in the app's Documents folder (`Enable-KickerDebug` in
`tools/ipad.ps1`), `uiopen kicker:snapshot` draws the app's windows and `kicker:screen` grabs the real screen
(video included) into the app's `tmp/screen.png` (`Get-IPadScreen`), `kicker:press?n=0` presses a button of the
alert or sheet on screen, `kicker:press?title=<text>` a button, segment, switch row or list row with that text,
`kicker:tab?n=1` switches tabs, `kicker:back` pops the navigation stack, `kicker:stats` logs the memory in use and
`kicker:link?url=<percent-encoded address>` does what a tap on that address in a text does (`&share=1`: what holding
it does). `/var/log/syslog` carries the app's log lines (`[Kicker]`, `Get-KickerLog`).

## Project layout

- `src/Net` – Mbed TLS socket with resolver fallback, HTTP/1.1 client and connection pool, WebSocket client,
  image loader (with the WebP decoding), the local media proxy for the player
- `src/Kick` – Kick's web API (browsing, channels, videos, clips, chat history), playback (playlists, device
  capabilities), the live chat over Pusher, message parsing, emotes (Kick and 7TV), favourites
- `src/UI` – theme (drawn artwork), the tabs, grids and lists, channel and category pages, the player, the chat
- `vendor` – Mbed TLS config and platform glue (Mbed TLS and libwebp are fetched at build time)
- `tools` – icon and asset generator, PowerShell helpers

## Privacy

Requests go straight from the device to Kick; there is no server in between, no account and no analytics. The
extra emotes come from 7TV (it learns the channel you watch; switch them off in Settings > Chat). Favourites and
settings stay in the app's sandbox.

## License

[MIT](LICENSE), copyright (c) 2026 samcejko. Mbed TLS (Apache-2.0), libwebp (BSD-3-Clause) and the Mozilla CA
bundle from curl.se (MPL-2.0) are downloaded at build time and included in the released packages under their own
licenses, see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md).

This is an independent hobby project, not affiliated with, endorsed by or connected to Kick or Apple. Kick is a
trademark of its owner; the name is used here only to say which service the app works with.
