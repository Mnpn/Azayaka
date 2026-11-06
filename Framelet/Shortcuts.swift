//
//  Shortcuts.swift
//  Framelet
//
//  Created by Martin Persson on 2024-08-11.
//

import AppKit
import KeyboardShortcuts
import ScreenCaptureKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        KeyboardShortcuts.onKeyDown(for: .recordCurrentWindow) { [self] in
            Task { await toggleRecording() }
        }
    }

    func toggleRecording() async {
        guard let appDelegate else { return }
        guard !appDelegate.isStopping, !appDelegate.isStarting else { return }
        appDelegate.allowShortcuts(false)
        guard CountdownManager.shared.timer == nil else {
            CountdownManager.shared.finishCountdown(startRecording: false)
            appDelegate.allowShortcuts(true)
            return
        }
        if appDelegate.stream == nil {
            guard let windowID = await appDelegate.getFocusedWindowID() else {
                appDelegate.allowShortcuts(true)
                return
            }
            let menuItem = NSMenuItem()
            menuItem.identifier = NSUserInterfaceItemIdentifier("window")
            menuItem.title = windowID.description
            appDelegate.prepRecord(menuItem)
        } else {
            appDelegate.stopRecording()
        }
    }
}

extension AppDelegate {
    func allowShortcuts(_ allow: Bool) {
        if allow {
            KeyboardShortcuts.enable(.recordCurrentWindow)
        } else {
            KeyboardShortcuts.disable(.recordCurrentWindow)
        }
    }

    // Menu-bar apps may temporarily become active while their menu is open.
    func focusedApplicationPID() -> pid_t? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return lastExternalAppPID
        }
        return front.processIdentifier
    }

    func getFocusedWindowID() async -> CGWindowID? {
        guard let frontAppPID = focusedApplicationPID() else { return nil }
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: AnyObject]] else { return nil }
        guard await updateAvailableContent(buildMenu: false), focusedApplicationPID() == frontAppPID else { return nil }
        let validIDs = Set(getValidWindows(for: frontAppPID).map(\.windowID))
        for info in windowList {
            if let pid = info["kCGWindowOwnerPID"] as? pid_t,
               let id = info["kCGWindowNumber"] as? CGWindowID,
               pid == frontAppPID, validIDs.contains(id) {
                return id
            }
        }
        return nil
    }

    func getValidWindows(for pid: pid_t) -> [SCWindow] {
        guard let content = availableContent else { return [] }
        return content.windows.filter {
            guard let app = $0.owningApplication,
                  let title = $0.title, !title.isEmpty else { return false }
            return app.processID == pid && !excludedWindows.contains(app.bundleIdentifier)
                && !title.contains("Item-0") && title != "Window"
        }
    }
}
