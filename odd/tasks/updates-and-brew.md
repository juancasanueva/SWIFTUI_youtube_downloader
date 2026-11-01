Objective: Sparkle "Check for Updates" and a Homebrew cask for YouTubeDownloader, ported from the release pipeline of the author's Attic app.
Branch: feat/updates-and-brew. Delivery: exception-ok (mostly ported files; push, PR, tag and tap push stay the user's decisions). Test runner: `xcodebuild test`.

## Specs

- S1. "I want to add Check for updates and brew installation like we did in Attic here /Users/juancasanueva/programming/swiftUI/disk"
- S2. In-app updates through Sparkle 2.9.6: a Check for Updates command, an automatic-check preference that stays off until the user turns it on, and when the app last checked, as in Attic.
- S3. Notarized release built by a tag push through GitHub Actions: archive, export, notarize, staple, verify, smoke, GitHub Release, appcast on GitHub Pages, as in Attic.
- S4. Homebrew cask in the existing tap juancasanueva/homebrew-tap, with its bump and CI entries.
- S5. Product name "YouTubeDownloader" (user's choice), cask token `youtube-downloader`. The bundle identifier stays com.juancasanueva.youtubedownload so settings carry over.
- S6. Assumption: the cask depends on the `yt-dlp` and `ffmpeg` formulae, because the app needs both and Homebrew's yt-dlp doesn't bring ffmpeg.

## Tasks

- T1 [S2, S5] inline: classic project format with the Sparkle package, Info.plist keys, product name. Status: pending.
- T2 [S2] inline: update core, Sparkle adapter, context menu command, Settings row. Status: pending.
- T3 [S3] inline: release scripts, workflow, RELEASING.md, pipeline tests. Status: pending.
- T4 [S4, S6] inline: tap cask and workflow entries in a separate clone of the tap, not pushed. Status: pending.
- T5 [S1-S6] delegated: independent verifier (Risk items 2 and 5). Status: pending.

## Log

- L1 (2026-11-01, user): "I want to add Check for updates and brew installation like we did in Attic here /Users/juancasanueva/programming/swiftUI/disk"
- L2 (2026-11-01, user): chose the product name YouTubeDownloader.
- L3: Route evidence: every task inline, no Writer trigger reason; the units are a single port.
- L4: Decision: replace project.xcproj with the classic project.pbxproj, as Attic did. Its log records that the xcproj format reads package references without error yet doesn't link them, and needs Xcode 27 on CI.
