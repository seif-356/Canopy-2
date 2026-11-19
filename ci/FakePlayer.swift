// Publishes a fake "now playing" song with artwork through MediaPlayer, the way
// a music app does, so the CI smoke test can screenshot Canopy 2 with media.
// Usage: fake-player [seconds] [title] [artist] [album] [duration]
import AppKit
import MediaPlayer

let arguments = Array(CommandLine.arguments.dropFirst())
let seconds = arguments.first.flatMap(Double.init) ?? 600
let title = arguments.count > 1 ? arguments[1] : "Smoke Test Song"
let artist = arguments.count > 2 ? arguments[2] : "Canopy CI"
let album = arguments.count > 3 ? arguments[3] : "Runner Sessions"
let duration = arguments.count > 4 ? Double(arguments[4]) ?? 214 : 214

let size = NSSize(width: 600, height: 600)
let art = NSImage(size: size, flipped: false) { rect in
    NSGradient(colors: [.systemPink, .systemOrange, .systemPurple])?.draw(in: rect, angle: 45)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 230, y: 380, width: 140, height: 140)).fill() // head
    NSBezierPath(roundedRect: NSRect(x: 190, y: 60, width: 220, height: 320), xRadius: 90, yRadius: 90).fill() // body
    return true
}

let center = MPNowPlayingInfoCenter.default()
center.nowPlayingInfo = [
    MPMediaItemPropertyTitle: title,
    MPMediaItemPropertyArtist: artist,
    MPMediaItemPropertyAlbumTitle: album,
    MPMediaItemPropertyPlaybackDuration: duration,
    MPNowPlayingInfoPropertyElapsedPlaybackTime: 63.0,
    MPNowPlayingInfoPropertyPlaybackRate: 1.0,
    MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
    MPMediaItemPropertyArtwork: MPMediaItemArtwork(boundsSize: size) { _ in art },
]
center.playbackState = .playing

let commands = MPRemoteCommandCenter.shared()
for command in [commands.playCommand, commands.pauseCommand, commands.togglePlayPauseCommand,
                commands.nextTrackCommand, commands.previousTrackCommand] {
    command.addTarget { _ in .success }
}

// Keep re-publishing so it stays the "now playing" app (e.g. after the adapter's
// self-test briefly publishes its own song).
var elapsed = 63.0
let timer = Timer(timeInterval: 2, repeats: true) { _ in
    elapsed += 2
    // Loop the middle of the song so later screenshots aren't stuck at the end.
    if elapsed > duration - 12 { elapsed = 45 }
    var info = center.nowPlayingInfo ?? [:]
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
    center.nowPlayingInfo = info
    center.playbackState = .playing
}
RunLoop.main.add(timer, forMode: .default)

print("fake player: \(title) — \(artist)")
fflush(stdout)
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
