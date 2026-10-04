# Kicker – Kick for iOS 6

Unofficial, universal (iPhone + iPad) [Kick](https://kick.com) client for **jailbroken iOS 6.x** devices (armv7,
e.g. iPad 2). Live streams with the chat, past broadcasts with the chat replay, clips, categories, search and
favourites, drawn in the glossy iOS 6 look – dark like Kick by default, light if you like – in English and Czech.
No account needed: everything the app shows is public.

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
- Channel pages: past broadcasts and clips (today, this week, this month, all time); favourites kept on the device
- Past broadcasts with seeking, resume where you left off, and the chat replay in time with the video
- Light and dark theme, English and Czech

Tested on an iPad 2 (iPad2,2) with iOS 6.1.3. The iPhone layout is implemented but has not been tried on a real
iPhone yet.

## Installing on the device

1. Cydia: **AppSync Unified** (repo `https://cydia.akemi.ai/`) and **IPA Installer Console** (BigBoss), plus
   OpenSSH for the helper scripts.
2. Download the `.ipa` or `.deb` of the latest [release](https://github.com/samcejko/kick-ios6/releases) (both
   carry the same build; the checksums are in the release notes).
3. Copy the `.ipa` to the device and run `ipainstaller -f Kicker-<version>.ipa`, or use iFunBox / 3uTools. The
   `.deb` works too (`dpkg -i`, then `su mobile -c uicache`) and installs into `/Applications`; do not keep both
   installed at once.

`tools/gh-release.ps1 -RunDir packages\run-<id> -Sha <commit>` publishes a release from a downloaded CI run.

## Building (GitHub Actions)

No Mac needed. Every push runs `.github/workflows/build.yml` on Ubuntu with Theos, the iOS 9.3 SDK (deployment
target 6.0), Mbed TLS and libwebp. Artifacts: `Kicker-<version>.ipa` and a `.deb`.

Local helpers (Windows PowerShell, no git required; settings in `tools/local.json`):

```powershell
.\tools\gh-push.ps1 -Message "change"                   # push via REST API
.\tools\gh-build.ps1 -Download -Install                 # wait, fetch, install over SSH
. .\tools\ipad.ps1; Get-IPadCrashLogs; Get-IPadSyslog   # debugging
```

URL scheme (other apps, or `uiopen` over SSH): `kicker:watch/<channel>` opens a stream,
`kicker:channel/<channel>` a channel page, `kicker:open?url=https://kick.com/<channel>` a channel by its web
address, `kicker:search?q=<text>` a search.

Debugging over SSH: with a file named `debug` in the app's Documents folder (`Enable-KickerDebug` in
`tools/ipad.ps1`), `uiopen kicker:snapshot` draws the app's windows and `kicker:screen` grabs the real screen
(video included) into the app's `tmp/screen.png` (`Get-IPadScreen`), `kicker:press?n=0` presses a button of the
alert or sheet on screen, `kicker:press?title=<text>` a button, segment, switch row or list row with that text,
`kicker:tab?n=1` switches tabs, `kicker:back` pops the navigation stack and `kicker:stats` logs the memory in use.
`/var/log/syslog` carries the app's log lines (`[Kicker]`, `Get-KickerLog`).

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
