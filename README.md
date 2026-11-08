# Canopy 2

A notch app for macOS, written in SwiftUI. It turns the MacBook notch into a live panel: media, lyrics, notifications, volume and brightness, a file shelf, and a desktop widget.

Not affiliated with Canopy (getcanopy.pro).

## Features

**Notch**
- Hover over the notch to open it. It closes when the pointer leaves, and never takes focus from your app.
- Opens for 3 seconds at launch (and when you open the app again) so you can see it's running.
- On displays without a notch, it draws one at the top of the screen.

**Media**
- Shows the song, artist, artwork and progress, with previous, play/pause and next. Drag the progress bar to seek.
- While music plays, the closed notch shows the artwork and moving bars, tinted with the artwork's colors.
- A banner drops down from the notch when the song changes.
- Source: Music and Spotify through AppleScript. Every app (browsers, Podcasts, VLC) is supported through MediaRemote when the MediaRemote helper is bundled (see Limits).

**Lyrics**
- Time-synced lyrics from [LRCLIB](https://lrclib.net), a free and open lyrics database.
- The current line appears under the song. The Lyrics tab scrolls with the music, and clicking a line jumps there.
- Optional: show the current line under the closed notch.

**Notifications**
- Shows other apps' notifications as banners from the notch. Click one to open the app.
- Needs **Full Disk Access**, because it reads the Notification Center database. Off by default.

**Volume and brightness**
- Volume changes show in the notch.
- Optional: replace the macOS volume and brightness pop-ups entirely. Needs **Accessibility** permission.

**Shelf**
- Drag files onto the notch to park them there, then drag them back out.
- Right-click a file to open it, show it in Finder, AirDrop it, copy its path or remove it.

**Widget**
- A frosted-glass widget on the desktop, with four layouts: Clock + Now Playing, Now Playing, Lyrics, and Minimal Clock. It uses Liquid Glass on macOS 26 when built with Xcode 26.
- Experimental: a Now Playing card on the lock screen. Off by default.

**Settings**: gear icon in the open notch, or the menu bar icon.

## Install (no Xcode needed)

1. Download the latest `Canopy2-*.zip` from [Releases](https://github.com/seif-356/Canopy-2/releases), or from a build's artifacts on the **Actions** tab, and unzip it.
2. Drag **Canopy2.app** into **Applications**.
3. In Terminal, run this once. It stops macOS from blocking an app that isn't notarized:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Canopy2.app
   ```
4. Open it.

**Permissions**, each asked for only when you turn on the feature that needs it:
- **Automation** for Music and Spotify, asked automatically.
- **Full Disk Access** for notification banners.
- **Accessibility** to replace the volume and brightness pop-ups.

Because the app is signed ad hoc, macOS treats each new build as a new app. After updating, remove the old Canopy2 entry in Full Disk Access and Accessibility, then add the new one.

Requires macOS 14 or later. Runs on Apple silicon and Intel.

## Build from source

Open `Canopy2.xcodeproj` in Xcode 16 or later and press **Run**. Every push to GitHub also builds the app on GitHub Actions. To publish a release:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

## Limits

- **Apps other than Music and Spotify** need Apple's private MediaRemote framework. Since macOS 15.4, Apple only lets its own programs use it. The workaround is the open-source helper [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter), which isn't bundled yet. Without it, Canopy 2 uses Music and Spotify only.
- **Notification banners** read a private macOS database whose format can change in any update. If it does, Settings › Notifications says so.
- **Brightness keys** use a private framework, and newer keyboards may not send them to apps.
- **The lock screen card** uses private SkyLight calls. That's why it's experimental and off by default.
