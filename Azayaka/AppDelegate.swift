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

@main
class AppDelegate: NSObject, NSApplicationDelegate, SCStreamDelegate, SCStreamOutput {
    // todo: clear these up
    var vwInput, awInput: AVAssetWriterInput!
    var vW: AVAssetWriter!
    var sessionBeginAtSourceTime: CMTime!
    var duration: Double = 0.0

    var audioSettings: [String : Any]!

    var stream: SCStream?
    var audioFile: AVAudioFile?
    var availableContent: SCShareableContent?
    var filter: SCContentFilter?
    var updateTimer: Timer?
    var menu = NSMenu()

    var isRecording = false
    var screen: SCDisplay?
    var window: SCWindow?

    let excludedWindows = ["", "com.apple.dock", "com.apple.controlcenter", "com.apple.notificationcenterui", "dev.mnpn.Azayaka", "com.gaosun.eul"]

    var statusItem: NSStatusItem!
    let preferences = NSWindow()
    let ud = UserDefaults.standard
    let info = NSMenuItem(title: "One moment, waiting on update", action: nil, keyEquivalent: "")
    let noneAvailable = NSMenuItem(title: "None available", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let userDesktop = (NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true) as [String]).first
        ud.register( // default defaults (used if not set)
            defaults: [
                "audioFormat": AudioFormat.aac.rawValue,
                "audioQuality": AudioQuality.high.rawValue,
                "frameRate": 60,
                "videoFormat": VideoFormat.mp4.rawValue,
                "encoder": Encoder.h264.rawValue,
                "saveDirectory": userDesktop!
            ]
        )
        // create a menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        statusItem.menu = menu
        updateAvailableContent(buildMenu: true)
    }

    @objc func updateAvailableContent(buildMenu: Bool) {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            if error != nil {
                print("[err] failed to fetch available content, permission error?:", error!.localizedDescription)
                return
            }
            self.availableContent = content
            assert((self.availableContent?.displays.count)! > 0, "There needs to be at least one display connected")
            if buildMenu {
                self.createMenu()
                return
            }
            Task { await self.refreshWindows() } // ask to just refresh the windows list instead of rebuilding it all
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if isRecording {
            stopRecording()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if !isRecording {
            updateAvailableContent(buildMenu: false)
        }
    }

    func menuDidClose(_ menu: NSMenu) {}
}
