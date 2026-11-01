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

- T1 [S2, S5] inline: classic project format with the Sparkle package, Info.plist keys, product name. Status: done, b2d4494.
- T2 [S2] inline: update core, Sparkle adapter, context menu command, Settings row. Status: done, 9960bee.
- T3 [S3] inline: release scripts, workflow, RELEASING.md, pipeline tests. Status: done, 7b22b40.
- T4 [S4, S6] inline: tap cask and workflow entries in a separate clone of the tap, not pushed. Status: done locally, tap branch feat/add-youtube-downloader (c436578) in ~/programming/swiftUI/homebrew-tap-youtube-downloader; sha256 placeholder until the first release.
- T5 [S1-S6] delegated: independent verifier (Risk items 2 and 5). Status: pending.

## Log

- L1 (2026-11-01, user): "I want to add Check for updates and brew installation like we did in Attic here /Users/juancasanueva/programming/swiftUI/disk"
- L2 (2026-11-01, user): chose the product name YouTubeDownloader.
- L3: Route evidence: every task inline, no Writer trigger reason; the units are a single port.
- L4: Decision: replace project.xcproj with the classic project.pbxproj, as Attic did. Its log records that the xcproj format reads package references without error yet doesn't link them, and needs Xcode 27 on CI.
- L5: Evidence: `xcodebuild test` 215 test cases pass; shellcheck and actionlint clean; unsigned Release build (arm64, 0.0.1 (7)) stayed up through the pipeline's smoke phase with real Sparkle started and automatic checks off; Settings section seen in a window capture. Not run: signing, notarization, the workflow itself, Xcode 26.6 compile (only Xcode 27.2 is installed locally), Sparkle against a real feed, the cask install.
- L6: Differences from Attic: Sparkle is skipped in the unit-test host, as in Matchday; Check for Updates lives in the right-click menu and brings the app forward first; Attic's icon and About-panel checks are dropped because this app has neither yet, so releases ship a generic icon; the cask depends on yt-dlp and ffmpeg.
