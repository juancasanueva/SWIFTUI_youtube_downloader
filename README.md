# YouTube Downloader

A small macOS menu bar app that downloads YouTube videos with [yt-dlp](https://github.com/yt-dlp/yt-dlp).

## Features

- Lives in the menu bar, with no Dock icon.
- Click the icon, or press the global shortcut `⌥⇧D` (Option + Shift + D), to open a panel that points at the icon.
- **Parallel downloads:** up to three videos download at once, each with its own progress bar, speed and time remaining. Extras wait in a queue and start as slots free up.
- **Playlists:** paste a playlist URL and its videos go through the same slots.
- **Transcripts:** subtitles are saved as `.vtt` files next to each video, including auto-generated ones. Turn this off or change the languages in Settings. If a language fails, the others and the video are kept.
- **History:** the last 200 downloads are kept, so you can play them again, show them in Finder, open their transcript, or retry failures.
- Downloads keep running after you close the panel. The menu bar icon fills in while the app is busy.
- Saves H.264/AAC `.mp4` files, which play in QuickTime.
- Choose the download folder in Settings, from the panel's gear button or by right-clicking the icon. The default is `~/Downloads`.
- Right-click the icon to quit.

Accepted video URLs are `youtube.com/watch?v=…`, `youtu.be/…`, `/shorts/…`, `/live/…` and `/embed/…`. Accepted playlist URLs are `youtube.com/playlist?list=…`. A video URL that also names a playlist downloads only that video. Channel URLs are rejected.

Transcript languages must be exact codes, such as `en,es`. A wildcard like `en.*` also matches every track auto-translated from English. For each language the app asks for both the `en-orig` and `en` tracks, because YouTube often answers HTTP 429 for the plain auto-caption track while `en-orig` works. A language can therefore produce two files, and some videos report a 429 for `en` while still saving `en-orig`.

History is stored in `~/Library/Application Support/com.juancasanueva.youtubedownload/history.json`.

## Requirements

- macOS 15.6 or later
- Xcode 27 to build
- yt-dlp, ffmpeg and a JavaScript runtime (Deno) for yt-dlp:

  ```sh
  brew install yt-dlp ffmpeg deno
  ```

The app looks for `yt-dlp` in `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin` and `~/.local/bin`.

## Build and run

Open `youtubedownload.xcodeproj` in Xcode and run the `youtubedownload` scheme, or build from the command line:

```sh
xcodebuild build -scheme youtubedownload -destination 'platform=macOS'
```

Run the unit tests with:

```sh
xcodebuild test -scheme youtubedownload -destination 'platform=macOS' -only-testing:youtubedownloadTests
```

## App Sandbox

The App Sandbox is turned off because the app runs yt-dlp as a child process, and that process needs to reach Homebrew tools and write to any folder you pick. This also means the app can't be distributed through the Mac App Store as it stands.

## Project structure

```
youtubedownload/
├── App/        App wiring, the menu bar item and the global shortcut
├── Download/   URL validation, the yt-dlp integration, the queue, history and the panel
└── Settings/   Download folder and transcript preferences, and the settings view
```

## Responsible use

Only download content you have the right to download, and follow YouTube's Terms of Service and your local laws.

## License

[MIT](LICENSE)
