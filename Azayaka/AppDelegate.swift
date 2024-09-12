//
//  AppDelegate.swift
//  Azayaka
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
struct Azayaka: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            Preferences()
                .fixedSize()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, SCStreamDelegate, SCStreamOutput {
    var stream: SCStream!
    var filePath: String!
    var audioFile: AVAudioFile?
    var audioSettings: [String : Any]!
    var availableContent: SCShareableContent?
    var updateTimer: Timer?
    var recordMic = false

    var screen: SCDisplay?
    var window: SCWindow?
    var streamType: StreamType?

    let excludedWindows = ["com.apple.dock", "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.systemuiserver", "com.apple.WindowManager", "dev.mnpn.Azayaka", "com.gaosun.eul", "com.pointum.hazeover", "net.matthewpalmer.Vanilla", "com.dwarvesv.minimalbar", "com.bjango.istatmenus.status"]

    var statusItem: NSStatusItem!
    var menu = NSMenu()
    let info = NSMenuItem(title: "One moment, waiting on update".local, action: nil, keyEquivalent: "")
    let noneAvailable = NSMenuItem(title: "None available".local, action: nil, keyEquivalent: "")
    let preferences = NSWindow()
    let ud = UserDefaults.standard
    let UpdateHandler = Updates()

    var useLegacyRecorder = false
    // new recorder
    var recordingOutput: Any? // wow this is mega jank, this will hold an SCRecordingOutput but it's only a thing on sequoia
    // legacy recorder
    var vW: AVAssetWriter!
    var vwInput, awInput, micInput: AVAssetWriterInput!
    let audioEngine = AVAudioEngine()
    var startTime: Date?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        lazy var userDesktop = (NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true) as [String]).first!

        // the `com.apple.screencapture` domain has the user set path for where they want to store screenshots or videos
        let saveDirectory = (UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") ?? userDesktop) as NSString

        ud.register( // default defaults (used if not set)
            defaults: [
                Preferences.kFrameRate: 60,
                Preferences.kHighResolution: true,
                Preferences.kVideoQuality: 1.0,
                Preferences.kVideoFormat: VideoFormat.mp4.rawValue,
                Preferences.kEncoder: Encoder.h264.rawValue,
                Preferences.kEnableHDR: utsname.isAppleSilicon,
                Preferences.kHideSelf: false,
                Preferences.kFrontApp: false,
                Preferences.kShowMouse: true,

                Preferences.kAudioFormat: AudioFormat.aac.rawValue,
                Preferences.kAudioQuality: AudioQuality.high.rawValue,
                Preferences.kRecordMic: false,

                Preferences.kFileName: "Recording at %t".local,
                Preferences.kSaveDirectory: saveDirectory,

                Preferences.kUpdateCheck: true,
                Preferences.kCountdownSecs: 0,
                Preferences.kUseKorai: ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 15 // sequoia
            ]
        )
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

        #if !DEBUG // no point in checking for updates if we're not on a release
        if ud.bool(forKey: Preferences.kUpdateCheck) {
            UpdateHandler.checkForUpdates()
        }
        #endif
    }

    func updateAvailableContent(buildMenu: Bool) async -> Bool { // returns status of getting content from SCK
        do {
            availableContent = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            let infoMenu = NSMenu()
            let infoItem = NSMenuItem()
            switch error {
                case SCStreamError.userDeclined:
                    infoItem.title = "Azayaka requires screen recording permissions.".local
                    requestPermissions()
                default:
                    print("Failed to fetch available content: ".local, error.localizedDescription)
                infoItem.attributedTitle = NSAttributedString(string: String(format: "Failed to fetch available content:\n%@".local, error.localizedDescription))
            }
            infoMenu.addItem(infoItem)
            infoMenu.addItem(NSMenuItem.separator())
            infoMenu.addItem(NSMenuItem(title: "Preferences…".local, action: #selector(openPreferences), keyEquivalent: ","))
            infoMenu.addItem(NSMenuItem(title: "Quit Azayaka".local, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = infoMenu
            return false
        }
        assert(self.availableContent?.displays.isEmpty != nil, "There needs to be at least one display connected".local)
        DispatchQueue.main.async {
            if buildMenu {
                self.createMenu()
            }
            self.refreshWindows(frontOnly: self.ud.bool(forKey: Preferences.kFrontApp))
            // ask to just refresh the windows list instead of rebuilding it all
        }
        return true
    }

    func requestPermissions() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Azayaka needs permissions!".local
            alert.informativeText = "Azayaka needs screen recording permissions, even if you only intend on recording audio.".local
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
        }
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
