# CineFlow Studio

CineFlow Studio is a Flutter desktop/mobile media suite with a Universal Downloader, Series & Drama Watcher, Lead Generator & Media Scraper, and Task Scheduler. The UI keeps the Dark Figma Studio theme (cyan/emerald on `#090D16`).

## Features

- **Linux and Windows support** (Flutter desktop). No 24/7 worker/service.
- **Universal Downloader**: direct file downloads with Dio `.part` resume, `yt-dlp` media extraction when available, handler pipeline (HLS/DASH manifest, media extractor, FTP, HTTP range), pre-allocated chunked direct-offset writing, dynamic work-stealing, crash-safe `.cfstate.json`, and mid-download Edit Source/Proxy hot-swap.
- **Categories**: downloads are stored under `Downloads/CineFlow-Studio/<Category>/`:
  - Web Series, Drama Shows, Hollywood Movies, Indian Movies, Stage Shows, MP3 Songs, MP4 Songs, Cartoons, Poems
- **RAM Guard modes**: Low 25%, Standard 45%, Maximum allowed 65%. These are targets, **not guaranteed memory limits**. At 65% the app raises an alert and reduces/pauses new download starts/concurrency; it never restarts system RAM.
- **Telegram Bot (optional, manual start/stop)**: reads `TELEGRAM_BOT_TOKEN` and `TELEGRAM_AUTHORIZED_USER_IDS` from `.env` only. GUI is never blocked. Commands: `/status`, `/pause`, `/resume`, `/download <URL>`, `/help`. Only authorized IDs are processed; missing token and unauthorized users are handled securely.
- **Localization**: US English, UK English, German, Spanish, French, Arabic, Roman Urdu. Missing translation keys fall back to English. Arabic uses RTL layout direction.
- **Security/Legal**: No DRM, CAPTCHA, paywall, login bypass, or rate/access restriction bypass.

## Setup

### Linux
1. Install Flutter SDK and Linux desktop dependencies.
2. Install optional tools for media downloads:
   - `yt-dlp` for supported video/audio platforms
   - `ffmpeg` for merge/remux/HLS-DASH segment remux
3. From project root:
   ```bash
   flutter pub get
   flutter run -d linux
   ```

### Windows
1. Install Flutter SDK and Windows desktop build tools (Visual Studio C++ workload).
2. Install optional tools and add to PATH: `yt-dlp`, `ffmpeg`.
3. From project root:
   ```powershell
   flutter pub get
   flutter run -d windows
   ```

## Telegram Bot Setup

1. Copy `.env.example` to `.env`.
2. Set values:
   ```env
   TELEGRAM_BOT_TOKEN=your_bot_token_from_botfather
   TELEGRAM_AUTHORIZED_USER_IDS=123456789,987654321
   ```
3. `.env` is gitignored and must never be committed.
4. Start app and open Telegram Bot panel; click Connect. Bot is manual start/stop only.
5. Authorized commands (only when bot connected and download manager ready):
   - `/status` - RAM, active/queued/paused/failed/completed counts
   - `/pause` - pause active downloads
   - `/resume` - resume paused/queued downloads
   - `/download <URL>` - add URL to downloader queue
   - `/help` - command help

Unauthorized users receive a secure refusal. Missing token/IDs produce safe status errors.

## RAM Limitation

RAM mode targets are operational heuristics, not hard guarantees:
- Low: 25% target
- Standard: 45% target
- Maximum allowed: 65%

When RAM reaches 65%, CineFlow reduces concurrency and pauses new starts and shows an alert. It does **not** restart, clear, or manipulate system RAM.

## Testing

```bash
flutter pub get
flutter analyze lib test
flutter test
```

Included tests cover platform paths, category folder creation, RAM thresholds, Telegram authorization, missing `.env`, translation fallback/RTL, handler routing, chunk range/state, and hot-swap source updates.
