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

    let excludedWindows = ["", "com.apple.dock", "com.apple.controlcenter", "dev.mnpn.Azayaka"]

    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // create a menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Azayaka")
        }

        updateAvailableContent()
    }

    func createMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let centreText = NSMutableParagraphStyle()
        centreText.alignment = .center
        let title = NSMenuItem(title: "Title", action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(string: "PICK CONTENT TO RECORD", attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 12, weight: .heavy), .paragraphStyle: centreText])
        menu.addItem(title)

        let audio = NSMenuItem(title: "System Audio", action: #selector(prepRecord), keyEquivalent: "")
        audio.identifier = NSUserInterfaceItemIdentifier(rawValue: "audio")
        menu.addItem(audio)

        menu.addItem(NSMenuItem.separator())

        let displays = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
        displays.attributedTitle = NSAttributedString(string: "DISPLAYS", attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 10, weight: .heavy)])
        menu.addItem(displays)
        
        for display in availableContent!.displays {
            let display = NSMenuItem(title: "Display " + display.displayID.description, action: #selector(prepRecord), keyEquivalent: "")
            display.identifier = NSUserInterfaceItemIdentifier(rawValue: "display")
            menu.addItem(display)
        }

        let windows = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
        windows.attributedTitle = NSAttributedString(string: "WINDOWS", attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 10, weight: .heavy)])
        menu.addItem(windows)

        for app in availableContent!.applications.filter({ !excludedWindows.contains($0.bundleIdentifier) }) {
            menu.addItem(NSMenuItem(title: app.applicationName, action: #selector(prepRecord), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Azayaka", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
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

    @objc func prepRecord(_ sender: NSMenuItem) {
        // todo: prep filtering stuff
        Task { await record(screen: sender.identifier?.rawValue != "audio") }
        // todo: turn menu into info & stopper
    }

    func record(screen: Bool) async {
        do {
            let conf = SCStreamConfiguration()
            conf.width = screen ? availableContent!.displays[0].width : 2
            conf.height = screen ? availableContent!.displays[0].height : 2
            conf.minimumFrameInterval = CMTime(value: 1, timescale: screen ? CMTimeScale(60) : CMTimeScale(1))
            conf.showsCursor = true
            conf.capturesAudio = true
            conf.sampleRate = 48000
            conf.channelCount = 2
            
            stream = SCStream(filter: filter!, configuration: conf, delegate: self)

            // file preparation
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
            audioFile = try! AVAudioFile(forWriting: NSURL(fileURLWithPath: "/Users/mnpn/Downloads/Recording at " + dateFormatter.string(from: Date()) + ".m4a") as URL, settings:
                                            [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                  AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                                           AVSampleRateKey: 48000,
                                       AVEncoderBitRateKey: 320000,
                                     AVNumberOfChannelsKey: 2],
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
            try! stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            try! stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            try await stream?.startCapture()
        } catch {
            assertionFailure("uh idk man")
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

    // https://developer.apple.com/documentation/screencapturekit/capturing_screen_content_in_macos
    private func createPCMBuffer(for sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        var ablPointer: UnsafePointer<AudioBufferList>?
        try? sampleBuffer.withAudioBufferList { audioBufferList, blockBuffer in
            ablPointer = audioBufferList.unsafePointer
        }
        guard let audioBufferList = ablPointer,
              let absd = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              let format = AVAudioFormat(standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame) else { return nil }
        return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            print("stream commited sudoku with error:")
            print(error)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        audioFile = nil // nilling the file closes it
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
