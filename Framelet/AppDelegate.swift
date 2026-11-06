//
//  AppDelegate.swift
//  Framelet
//
//  Created by Martin Persson on 2022-12-25.
//

import AVFoundation
import AVFAudio
import Cocoa
import KeyboardShortcuts
import ScreenCaptureKit
import UserNotifications
import SwiftUI

@main
struct Framelet: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            Preferences()
                .fixedSize()
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, SCStreamDelegate, SCStreamOutput {
    private var shortcutState: AppState?
    let captureQueue = DispatchQueue(label: "app.framelet.capture")
    var isStopping = false
    var isStarting = false
    var stopAfterStart = false
    let diskSpaceReserveBytes: Int64 = 1_000_000_000
    var diskSpaceTimer: Timer?
    var diskCheckInFlight = false
    var diskStopReason: String?
    var stream: SCStream!
    var filePath: String!
    var audioFile: AVAudioFile?
    var audioSettings: [String : Any]!
    var availableContent: SCShareableContent?
    var lastExternalAppPID: pid_t?
    var updateTimer: Timer?
    var recordMic = false

    var screen: SCDisplay?
    var window: SCWindow?
    var streamType: StreamType?

    let excludedWindows = ["com.apple.dock", "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.systemuiserver", "com.apple.WindowManager", "app.framelet.recorder", "com.gaosun.eul", "com.pointum.hazeover", "net.matthewpalmer.Vanilla", "com.dwarvesv.minimalbar", "com.bjango.istatmenus.status"]

    var statusItem: NSStatusItem!
    var menu = NSMenu()
    let info = NSMenuItem(title: "One moment, waiting on update".local, action: nil, keyEquivalent: "")
    let noneAvailable = NSMenuItem(title: "None available".local, action: nil, keyEquivalent: "")
    let preferences = NSWindow()
    let ud = UserDefaults.standard

    var useSystemRecorder = false
    // new recorder
    var recordingOutput: Any? // wow this is mega jank, this will hold an SCRecordingOutput but it's only a thing on sequoia
    // legacy recorder
    var vW: AVAssetWriter!
    var vwInput, awInput, micInput: AVAssetWriterInput!
    let audioEngine = AVAudioEngine()
    var startTime: Date?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        shortcutState = AppState(appDelegate: self)
        lazy var userDesktop = (NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true) as [String]).first!

        // the `com.apple.screencapture` domain has the user set path for where they want to store screenshots or videos
        let saveDirectory = (UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") ?? userDesktop) as NSString

        ud.register( // default defaults (used if not set)
            defaults: [
                Preferences.kFrameRate: 1,
                Preferences.kHighResolution: true,
                Preferences.kVideoQuality: 1.0,
                Preferences.kVideoFormat: VideoFormat.mp4.rawValue,
                Preferences.kEncoder: Encoder.h264.rawValue,
                Preferences.kEnableHDR: false,
                Preferences.kShowMouse: true,

                Preferences.kAudioFormat: AudioFormat.aac.rawValue,
                Preferences.kAudioQuality: AudioQuality.high.rawValue,
                Preferences.kRecordMic: true,

                Preferences.kFileName: "Recording at %t".local,
                Preferences.kSaveDirectory: saveDirectory,

                Preferences.kUpdateCheck: false,
                Preferences.kCountdownSecs: 0,
                Preferences.kSystemRecorder: false
            ]
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.streamType != nil else { return }
            if self.isStarting { self.stopAfterStart = true }
            else { self.stopRecording() }
        }
        // Reset unsupported selections from previous versions.
        if ![1, 5, 15, 30].contains(ud.integer(forKey: Preferences.kFrameRate)) {
            ud.set(1, forKey: Preferences.kFrameRate)
        }
        // A Finder custom icon avoids macOS adding a gray backing to legacy icons.
        // Reapply when running from a writable app bundle; the bundled icon remains the fallback.
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            let applied = NSWorkspace.shared.setIcon(icon, forFile: Bundle.main.bundlePath, options: [])
            if !applied { print("Framelet: could not apply custom Finder icon to \(Bundle.main.bundlePath)") }
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalAppPID = front.processIdentifier
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.lastExternalAppPID = app.processIdentifier
        }
        // create a menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        statusItem.menu = menu
        menu.minimumWidth = 250
        Task { await updateAvailableContent(buildMenu: true) }

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error { print("Notification authorisation denied: \(error.localizedDescription)") }
        }

        NotificationCenter.default.addObserver( // update the content & menu when a display device has changed
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApplication.shared,
            queue: OperationQueue.main
        ) { [self] notification -> Void in
            Task { await updateAvailableContent(buildMenu: true) }
        }

    }

    func updateAvailableContent(buildMenu: Bool) async -> Bool { // returns status of getting content from SCK
        do {
            availableContent = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            let infoMenu = NSMenu()
            let infoItem = NSMenuItem()
            switch error {
                case SCStreamError.userDeclined:
                    infoItem.title = "Framelet requires screen recording permissions.".local
                    requestPermissions()
                default:
                    print("Failed to fetch available content: ".local, error.localizedDescription)
                infoItem.attributedTitle = NSAttributedString(string: String(format: "Failed to fetch available content:\n%@".local, error.localizedDescription))
            }
            infoMenu.addItem(infoItem)
            infoMenu.addItem(NSMenuItem.separator())
            infoMenu.addItem(NSMenuItem(title: "Preferences…".local, action: #selector(openPreferences), keyEquivalent: ","))
            infoMenu.addItem(NSMenuItem(title: "Quit Framelet".local, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = infoMenu
            return false
        }
        assert(self.availableContent?.displays.isEmpty != nil, "There needs to be at least one display connected".local)
        DispatchQueue.main.async {
            if buildMenu {
                self.createMenu()
            }
            self.refreshWindows()
            // ask to just refresh the windows list instead of rebuilding it all
        }
        return true
    }

    func requestPermissions() {
        allowShortcuts(false)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Framelet needs permissions!".local
            alert.informativeText = "Framelet needs screen recording permissions.".local
            alert.addButton(withTitle: "Open Settings".local)
            alert.addButton(withTitle: "Okay".local)
            alert.addButton(withTitle: "No thanks, quit".local)
            alert.alertStyle = .informational
            switch(alert.runModal()) {
                case .alertFirstButtonReturn:
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                case .alertThirdButtonReturn: NSApp.terminate(self)
                default: return
            }
            self.allowShortcuts(true)
        }
    }

    func copyToClipboard(_ content: [any NSPasteboardWriting]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(content)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if stream != nil {
            stopRecording()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

extension String {
    var local: String { return NSLocalizedString(self, comment: "") }
}
