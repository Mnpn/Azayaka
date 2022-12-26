//
//  AppDelegate.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-25.
//

import AVFAudio
import Cocoa
import ScreenCaptureKit

@main
class AppDelegate: NSObject, NSApplicationDelegate, SCStreamDelegate, SCStreamOutput {
    var stream: SCStream?
    var audioFile: AVAudioFile?
    var availableContent: SCShareableContent?
    var filter: SCContentFilter?

    var isRecording = false

    let excludedWindows = ["", "com.apple.dock", "com.apple.controlcenter", "dev.mnpn.Azayaka"]

    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // create a menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()

        updateAvailableContent()
    }

    func updateAvailableContent() {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            if error != nil {
                print("[err] failed to fetch available content, permission error?")
                return
            }
            self.availableContent = content
            assert((self.availableContent?.displays.count)! > 0, "There needs to be at least one display connected")
            let excluded = self.availableContent?.applications.filter { app in
                self.excludedWindows.contains(app.bundleIdentifier)
            }
            self.filter = SCContentFilter(display: (self.availableContent?.displays[0])!, excludingApplications: [], exceptingWindows: [])
            self.createMenu()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        
        switch outputType {
            case .screen: print("got screen data"); break
            case .audio:
                guard let samples = createPCMBuffer(for: sampleBuffer) else { return }
                do {
                    try audioFile?.write(from: samples)
                }
                catch { assertionFailure("audio file writing issue") }
            @unknown default:
                assertionFailure("unknown stream type")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            print("stream commited sudoku with error:")
            print(error)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        stopRecording()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateAvailableContent()
    }

    func menuDidClose(_ menu: NSMenu) { }
}
