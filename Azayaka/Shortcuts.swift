//
//  Shortcuts.swift
//  Azayaka
//
//  Created by Martin Persson on 2024-08-11.
//

import AppKit
import AVFoundation
import KeyboardShortcuts
import ScreenCaptureKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        KeyboardShortcuts.onKeyDown(for: .recordSystemAudio) { [self] in
            Task { await toggleRecording(type: "audio") }
        }
        KeyboardShortcuts.onKeyDown(for: .recordCurrentDisplay) { [self] in
            Task { await toggleRecording(type: "display") }
        }
        KeyboardShortcuts.onKeyDown(for: .recordCurrentWindow) { [self] in
            Task { await toggleRecording(type: "window") }
        }
        KeyboardShortcuts.onKeyDown(for: .toggleMicrophone) { [self] in
            appDelegate.toggleMicrophoneState()
        }
    }

    func toggleRecording(type: String) async {
        appDelegate.allowShortcuts(false)
        guard CountdownManager.shared.timer == nil else { // cancel a countdown if in progress
            CountdownManager.shared.finishCountdown(startRecording: false)
            appDelegate.allowShortcuts(true)
            return
        }
        if appDelegate.stream == nil {
            let menuItem = NSMenuItem() // this will be our sender, which includes details about which content it is we want to record
            menuItem.identifier = NSUserInterfaceItemIdentifier(type)
            if type == "display" {
                if let currentDisplayID = appDelegate.getScreenWithMouse()?.displayID { // use display with mouse on it
                    menuItem.title = currentDisplayID.description
                } else { // fall back to first available display
                    menuItem.title = (appDelegate.availableContent!.displays.first?.displayID.description)!
                }
            } else if type == "window" {
                if let windowID = await appDelegate.getFocusedWindowID() {
                    menuItem.title = windowID.description
                } else {
                    // todo: relay lack of windows to user
                    appDelegate.allowShortcuts(true)
                    return
                }
            }
            appDelegate.prepRecord(menuItem)
        } else {
            appDelegate.stopRecording()
        }
    }
}

extension AppDelegate {
    func allowShortcuts(_ allow: Bool) {
        if allow {
            KeyboardShortcuts.enable(.recordCurrentDisplay, .recordCurrentWindow, .recordSystemAudio, .toggleMicrophone)
        } else {
            KeyboardShortcuts.disable(.recordCurrentDisplay, .recordCurrentWindow, .recordSystemAudio, .toggleMicrophone)
        }
    }

    func toggleMicrophoneState() {
        let newValue = !ud.bool(forKey: Preferences.kRecordMic)
        ud.set(newValue, forKey: Preferences.kRecordMic)
        if newValue && (ud.string(forKey: Preferences.kSelectedMicrophone) ?? "").isEmpty {
            if let defaultMic = AVCaptureDevice.default(for: .audio) {
                ud.set(defaultMic.uniqueID, forKey: Preferences.kSelectedMicrophone)
            }
        }
        if !newValue {
            ud.set("", forKey: Preferences.kSelectedMicrophone)
        }
        updateIcon()
    }

    // a ScreenCaptureKit implementation does not work correctly, is it the order of the returned windows perhaps?
    // optionOnScreenOnly mentions "Windows are returned in order from front to back", which might be the magic here.
    func getFocusedWindowID() async -> CGWindowID? {
        guard let frontAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        guard frontAppPID != ProcessInfo.processInfo.processIdentifier else { return nil }
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: AnyObject]] else { return nil }

        guard await updateAvailableContent(buildMenu: false) else { return nil } // to make sure we've got the latest content for getValidWindows

        for windowInfo in windowList {
            if let windowPID = windowInfo["kCGWindowOwnerPID"] as? pid_t,
               let windowID = windowInfo["kCGWindowNumber"] as? CGWindowID,
               windowPID == frontAppPID,
               getValidWindows(frontOnly: false).contains(where: { $0.windowID == windowID }) { // make sure this window is available
                return windowID
            }
        }

        return nil
    }

    func getValidWindows(frontOnly: Bool) -> [SCWindow] {
        let frontAppId = frontOnly ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
        // in sonoma, there is a new new purple thing overlaying the traffic lights, I don't really want this to show up.
        // its title is simply "Window", but its bundle id is the same as the parent, so this seems like a strange bodge..
        return availableContent!.windows.filter {
            guard let app = $0.owningApplication,
                let title = $0.title, !title.isEmpty else {
                return false
            }
            return !excludedWindows.contains(app.bundleIdentifier)
                && !title.contains("Item-0")
                && title != "Window"
                && (!frontOnly
                    || frontAppId == nil // include all if none is frontmost
                    || (frontAppId == app.processID))
        }
    }
}
