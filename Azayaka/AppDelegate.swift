//
//  AppDelegate.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-25.
//

import AVFoundation
import AVFAudio
import Cocoa
import ScreenCaptureKit
import UserNotifications
import SwiftUI

@main
struct AzayakaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            Preferences()
                .fixedSize()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, SCStreamDelegate, SCStreamOutput {
    var vW: AVAssetWriter!
    var vwInput, awInput, micInput: AVAssetWriterInput!
    let audioEngine = AVAudioEngine()
    var startTime: Date?
    var stream: SCStream!
    var filePath: String!
    var audioFile: AVAudioFile?
    var audioSettings: [String : Any]!
    var availableContent: SCShareableContent?
    var filter: SCContentFilter?
    var updateTimer: Timer?
    var recordMic = false

    var screen: SCDisplay?
    var window: SCWindow?
    var streamType: StreamType?

    let excludedWindows = ["", "com.apple.dock", "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.systemuiserver", "com.apple.WindowManager", "dev.mnpn.Azayaka", "com.gaosun.eul", "com.pointum.hazeover", "net.matthewpalmer.Vanilla", "com.dwarvesv.minimalbar", "com.bjango.istatmenus.status"]

    var statusItem: NSStatusItem!
    var menu = NSMenu()
    let info = NSMenuItem(title: "One moment, waiting on update".local, action: nil, keyEquivalent: "")
    let noneAvailable = NSMenuItem(title: "None available".local, action: nil, keyEquivalent: "")
    let preferences = NSWindow()
    let ud = UserDefaults.standard

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        lazy var userDesktop = (NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true) as [String]).first!
        
        // the `com.apple.screencapture` domain has the user set path for where they want to store screenshots or videos
        let saveDirectory = (UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") ?? userDesktop) as NSString
        
        ud.register( // default defaults (used if not set)
            defaults: [
                "audioFormat": AudioFormat.aac.rawValue,
                "audioQuality": AudioQuality.high.rawValue,
                "frameRate": 60,
                "videoQuality": 1.0,
                "videoFormat": VideoFormat.mp4.rawValue,
                "encoder": Encoder.h264.rawValue,
                "saveDirectory": saveDirectory,
                "hideSelf": false,
                Preferences.frontAppKey: false,
                "showMouse": true,
                "recordMic": false,
                "highRes": true
            ]
        )
        // create a menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        statusItem.menu = menu
        menu.minimumWidth = 250
        updateAvailableContent(buildMenu: true)
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error { print("Notification authorization denied: \(error.localizedDescription)") }
        }
    }

    func updateAvailableContent(buildMenu: Bool) {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            if let error = error {
                switch error {
                    case SCStreamError.userDeclined: self.requestPermissions()
                default: print("[err] failed to fetch available content:".local, error.localizedDescription)
                }
                return
            }
            self.availableContent = content
            assert(self.availableContent?.displays.isEmpty != nil, "There needs to be at least one display connected".local)
            let frontOnly = UserDefaults.standard.bool(forKey: Preferences.frontAppKey)
            DispatchQueue.main.async {
                if buildMenu {
                    self.createMenu()
                }
                self.refreshWindows(frontOnly: frontOnly) 
                // ask to just refresh the windows list instead of rebuilding it all
            }
        }
    }

    func requestPermissions() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Azayaka needs permissions!".local
            alert.informativeText = "Azayaka needs screen recording permissions, even if you only intend on recording audio.".local
            alert.addButton(withTitle: "Open Settings".local)
            alert.addButton(withTitle: "No thanks, quit".local)
            alert.alertStyle = .informational
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            NSApp.terminate(self)
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

