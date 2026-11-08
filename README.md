# Canopy 2

A notch app for macOS, written in SwiftUI. It turns the MacBook notch into a small panel you open by hovering over it.

## Features (v0.1)

**Notch**
- Hover over the notch to expand it. It closes when the pointer leaves.
- Never takes focus away from the app you're using.
- On Macs and displays without a notch, it draws one at the top of the screen. This can be turned off in Settings.

**Now Playing**
- Shows the song, artist, artwork and progress from **Music** or **Spotify**.
- Previous, play/pause and next buttons.
- While a song plays, the closed notch shows the artwork and moving bars next to the camera.

**Shelf**
- Drag files onto the notch to park them on the shelf. Drag them back out to any app or folder.
- Double-click a file to open it. Right-click for Show in Finder, Copy Path or Remove.
- The shelf keeps a link to the original file, not a copy. Moving or deleting the original removes it from the shelf.

**Settings** (from the menu bar icon)
- Launch at login
- Show the notch on displays without one
- Show the playing song while the notch is closed

## Install (no Xcode needed)

1. Download the latest `Canopy2-*.zip` from [Releases](https://github.com/seif-356/Canopy-2/releases), or from the **Actions** tab's build artifacts, and double-click it.
2. Drag **Canopy2.app** into **Applications**.
3. Open it. macOS blocks it with "Apple could not verify…" because the app isn't notarized. Click **Done**.
4. Open **System Settings › Privacy & Security**, scroll down, click **Open Anyway** next to Canopy2, and confirm.

The first time it reads Music or Spotify, macOS asks whether Canopy 2 may control that app. Click **OK**. To change this later, go to **System Settings › Privacy & Security › Automation**.

Requires macOS 14 or later. Runs on Apple silicon and Intel.

## Build from source

Open `Canopy2.xcodeproj` in Xcode 16 or later and press **Run**.

## Release

Every push builds the app on GitHub Actions. To publish a release:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

## Limits

- **Only Music and Spotify.** Other players and browsers (YouTube, Safari, Chrome) aren't shown. The system-wide Now Playing API is private, and Apple restricted it in macOS 15.4.
- **No notifications from other apps.** macOS has no public way to read other apps' notifications.
- **No lock screen widgets.** Drawing on the lock screen needs private APIs.
