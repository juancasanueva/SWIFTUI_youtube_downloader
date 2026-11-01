# YouTube Downloader

A small macOS menu bar app that downloads YouTube videos with [yt-dlp](https://github.com/yt-dlp/yt-dlp).

## Features

- Lives in the menu bar, with no Dock icon.
- Click the icon, or press the global shortcut `⌥⇧D` (Option + Shift + D), to open a panel that points at the icon.
- Paste a video URL, press Return, and follow the progress. You can cancel at any time.
- Downloads keep running after you close the panel. The menu bar icon fills in while one is active.
- Saves H.264/AAC `.mp4` files, which play in QuickTime.
- Choose the download folder in Settings, from the panel's gear button or by right-clicking the icon. The default is `~/Downloads`.
- Right-click the icon to quit.

Accepted URLs are single videos: `youtube.com/watch?v=…`, `youtu.be/…`, `/shorts/…`, `/live/…` and `/embed/…`. Only the video is downloaded when the URL also names a playlist. Playlist and channel URLs are rejected.

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
├── Download/   URL validation, the yt-dlp integration, download state and the panel
└── Settings/   Download folder preference and the settings view
```

## Responsible use

Only download content you have the right to download, and follow YouTube's Terms of Service and your local laws.

## License

[MIT](LICENSE)
