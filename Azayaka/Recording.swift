//
//  Recording.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import ScreenCaptureKit
import AVFAudio

extension AppDelegate {
    @objc func prepRecord(_ sender: NSMenuItem) {
        updateAudioSettings()
        // file preparation
        screen = availableContent!.displays.first(where: { sender.title == $0.displayID.description })
        window = availableContent!.windows.first(where: { sender.title == $0.windowID.description })
        if window != nil {
            filter = SCContentFilter(desktopIndependentWindow: window!)
        } else {
            let excluded = self.availableContent?.applications.filter { app in
                Bundle.main.bundleIdentifier == app.bundleIdentifier && ud.bool(forKey: "hideSelf")
            }
            filter = SCContentFilter(display: screen ?? availableContent!.displays.first!, excludingApplications: excluded ?? [], exceptingWindows: [])
        }
        let audioOnly = screen == nil && window == nil
        if audioOnly {
            prepareAudioRecording()
        }
        Task { await record(audioOnly: audioOnly, filter: filter ?? SCContentFilter()) }

        // while recording, keep a timer which updates the menu's stats
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateMenu()
        }
        RunLoop.current.add(updateTimer!, forMode: .common) // required to have the menu update while open
    }

    func record(audioOnly: Bool, filter: SCContentFilter) async {
        let conf = SCStreamConfiguration()
        conf.width = 2
        conf.height = 2

        if !audioOnly {
            let scale: Int = Int((screen != nil ? NSScreen.screens.first(where: { $0.displayID == screen?.displayID })!.backingScaleFactor : NSScreen.main?.backingScaleFactor) ?? 1)
            // todo: find relevant scaling factor. it seems windows are available on all displays though, and there's no way to get a window's display, so this is tricky
            conf.width = window == nil ? availableContent!.displays[0].width*scale : Int((window?.frame.width)!*CGFloat(scale))
            conf.height = window == nil ? availableContent!.displays[0].height*scale : Int((window?.frame.height)!*CGFloat(scale))
        }

        conf.minimumFrameInterval = CMTime(value: 1, timescale: audioOnly ? 1 : CMTimeScale(ud.integer(forKey: "frameRate")))
        conf.showsCursor = true
        conf.capturesAudio = true
        conf.sampleRate = audioSettings["AVSampleRateKey"] as! Int
        conf.channelCount = audioSettings["AVNumberOfChannelsKey"] as! Int

        stream = SCStream(filter: filter, configuration: conf, delegate: self)
        do {
            try! stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            try! stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            if !audioOnly {
                initVideo(conf: conf)
            }
            try await stream.startCapture()
        } catch {
            assertionFailure("capture failed")
            return
        }
        isRecording = true
        updateIcon()
        createMenu()
    }

    @objc func stopRecording() {
        if screen != nil || window != nil {
            closeVideo()
        } else {
            audioFile = nil // close file
        }
        stream.stopCapture()
        isRecording = false
        window = nil
        screen = nil
        updateIcon()
        updateTimer?.invalidate()
        createMenu()
    }

    func updateAudioSettings() {
        audioSettings = [AVSampleRateKey : 48000, AVNumberOfChannelsKey : 2] // reset audioSettings
        switch ud.string(forKey: "audioFormat") {
        case AudioFormat.aac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] = ud.integer(forKey: "audioQuality")*1000
        case AudioFormat.alac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatAppleLossless
            audioSettings[AVEncoderBitDepthHintKey] = 16
        case AudioFormat.flac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatFLAC
        case AudioFormat.opus.rawValue:
            audioSettings[AVFormatIDKey] = ud.string(forKey: "videoFormat") != VideoFormat.mp4.rawValue ? kAudioFormatOpus : kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] =  ud.integer(forKey: "audioQuality")*1000
        default:
            assertionFailure("unknown audio format while setting audio settings: " + (ud.string(forKey: "audioFormat") ?? "[no defaults]"))
        }
    }

    func prepareAudioRecording() {
        var fileEnding = ud.string(forKey: "audioFormat") ?? ""
        switch fileEnding { // todo: I'd like to store format info differently
            case AudioFormat.aac.rawValue: fallthrough
            case AudioFormat.alac.rawValue: fileEnding = "m4a"
            case AudioFormat.flac.rawValue: fileEnding = "flac"
            case AudioFormat.opus.rawValue: fileEnding = "ogg"
            default: assertionFailure("loaded unknown audio format: " + fileEnding)
        }
        filePath = "\(getFilePath()).\(fileEnding)"
        audioFile = try! AVAudioFile(forWriting: URL(fileURLWithPath: filePath), settings: audioSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func getFilePath() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
        return ud.string(forKey: "saveDirectory")! + "/Recording at " + dateFormatter.string(from: Date())
    }

    func getRecordingLength() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        return formatter.string(from: TimeInterval(duration))!
    }

    func getRecordingSize() -> String {
        do {
            let fileAttr = try FileManager.default.attributesOfItem(atPath: filePath)
            let byteFormat = ByteCountFormatter()
            byteFormat.allowedUnits = [.useMB]
            byteFormat.countStyle = .file
            return byteFormat.string(fromByteCount: fileAttr[FileAttributeKey.size] as! Int64)
        } catch {
            print("failed to fetch file for size indicator: \(error.localizedDescription)")
        }
        return "Unknown"
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}
