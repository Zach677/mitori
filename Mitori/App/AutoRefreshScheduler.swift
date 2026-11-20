//
//  AutoRefreshScheduler.swift
//  Mitori
//
//  Created by @Zach677 on 2026/06/12.
//

import AppKit
import Foundation

@MainActor
final class AutoRefreshScheduler {
    private static let deferredRetryInterval: TimeInterval = 60

    private let now: () -> Date
    private let nextFireDate: @MainActor () -> Date?
    private let onTick: @MainActor @Sendable () async -> Void
    private var timer: Timer?
    private var activeTickTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var isRunning = false

    /// Schedules a single one-shot timer for the earliest due account and wakes on system unlock/wake.
    init(
        now: @escaping () -> Date = Date.init,
        nextFireDate: @escaping @MainActor () -> Date?,
        onTick: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.now = now
        self.nextFireDate = nextFireDate
        self.onTick = onTick
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        installSystemObservers()
        reschedule()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        activeTickTask?.cancel()
        activeTickTask = nil
        removeSystemObservers()
    }

    func reschedule() {
        guard isRunning else { return }
        timer?.invalidate()
        timer = nil

        guard activeTickTask == nil else { return }
        guard let fireDate = nextFireDate() else { return }
        scheduleTimer(delay: max(0, fireDate.timeIntervalSince(now())))
    }

    func triggerTick() {
        guard activeTickTask == nil else { return }
        timer?.invalidate()
        timer = nil

        let onTick = onTick
        activeTickTask = Task { @MainActor [weak self] in
            await onTick()
            guard let self else { return }
            activeTickTask = nil
            rescheduleAfterTick()
        }
    }

    private func rescheduleAfterTick() {
        guard isRunning else { return }
        guard let fireDate = nextFireDate() else { return }
        let rawDelay = fireDate.timeIntervalSince(now())
        // If an account is still due immediately after a tick (e.g. screen is locked),
        // avoid spinning and rely on unlock notifications plus a 60s fallback.
        let delay = rawDelay <= 0 ? Self.deferredRetryInterval : rawDelay
        scheduleTimer(delay: delay)
    }

    private func scheduleTimer(delay: TimeInterval) {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.triggerTick()
            }
        }
        timer.tolerance = min(max(delay * 0.1, 1), 30)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func installSystemObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        workspaceObservers = wakeNames.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSystemWake()
                }
            }
        }

        let unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWake()
            }
        }
        distributedObservers = [unlockObserver]
    }

    private func removeSystemObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        let distributedCenter = DistributedNotificationCenter.default()
        for observer in distributedObservers {
            distributedCenter.removeObserver(observer)
        }
        distributedObservers.removeAll()
    }

    private func handleSystemWake() {
        guard isRunning else { return }
        if let fireDate = nextFireDate(), fireDate <= now() {
            triggerTick()
        } else {
            reschedule()
        }
    }
}
