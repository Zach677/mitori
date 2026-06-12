import Foundation

@MainActor
final class AutoRefreshScheduler {
    private let tickInterval: TimeInterval
    private let onTick: () async -> Void
    private var timer: Timer?

    // The timer only wakes the app; whether a refresh actually runs is
    // decided per account by the model, so a short tick stays cheap.
    init(tickInterval: TimeInterval = 60, onTick: @escaping () async -> Void) {
        self.tickInterval = tickInterval
        self.onTick = onTick
    }

    func start() {
        guard timer == nil else { return }

        let timer = Timer(timeInterval: tickInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                await self?.onTick()
            }
        }
        timer.tolerance = tickInterval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
