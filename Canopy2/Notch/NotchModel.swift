import Combine
import SwiftUI

enum NotchTab: Hashable {
    case nowPlaying
    case shelf
}

/// State the notch views render. The controller owns it and drives open/close.
@MainActor
final class NotchModel: ObservableObject {
    @Published var geometry: NotchGeometry?
    @Published var isOpen = false
    @Published var tab: NotchTab = .nowPlaying
    @Published var isDropTargeted = false
    /// True while music plays and the closed notch shows artwork + bars beside the camera.
    @Published private(set) var showsActivity = false

    let nowPlaying: NowPlayingService
    let shelf: ShelfStore

    private var isPlaying = false
    private var cancellables: Set<AnyCancellable> = []

    init(nowPlaying: NowPlayingService, shelf: ShelfStore) {
        self.nowPlaying = nowPlaying
        self.shelf = shelf

        nowPlaying.$track
            .map { $0?.isPlaying ?? false }
            .removeDuplicates()
            .sink { [weak self] playing in
                MainActor.assumeIsolated {
                    self?.isPlaying = playing
                    self?.updateActivity()
                }
            }
            .store(in: &cancellables)
    }

    func updateActivity() {
        let shows = isPlaying && Prefs.isMusicActivityEnabled
        guard shows != showsActivity else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showsActivity = shows
        }
    }

    /// Size of the black shape while closed, including its curved "ears".
    var closedSize: CGSize {
        guard let geometry else { return .zero }
        let activityWidth = showsActivity ? (geometry.notchSize.height + 12) * 2 : 0
        return CGSize(
            width: geometry.notchSize.width + NotchMetrics.closedTopRadius * 2 + activityWidth,
            height: geometry.notchSize.height
        )
    }
}
