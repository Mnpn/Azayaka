//
//  Recording.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import UserNotifications
import ScreenCaptureKit
import AVFAudio
import KeyboardShortcuts

extension AppDelegate {
    @objc func prepRecord(_ sender: NSMenuItem) {
        switch (sender.identifier?.rawValue) {
            case "window":  streamType = .window
            case "display": streamType = .screen
            case "audio":   streamType = .systemaudio
            default: return // if we don't even know what to record I don't think we should even try
        }
        statusItem.menu = nil
        updateAudioSettings()
        // file preparation
        screen = availableContent!.displays.first(where: { sender.title == $0.displayID.description })
        window = availableContent!.windows.first(where: { sender.title == $0.windowID.description })
        if streamType == .window {
            filter = SCContentFilter(desktopIndependentWindow: window!)
        } else {
            let excluded = availableContent?.applications.filter { app in
                Bundle.main.bundleIdentifier == app.bundleIdentifier && ud.bool(forKey: "hideSelf")
            }
            filter = SCContentFilter(display: screen ?? availableContent!.displays.first!, excludingApplications: excluded ?? [], exceptingWindows: [])
        }
        if streamType == .systemaudio {
            prepareAudioRecording()
        }
        Task { await record(audioOnly: streamType == .systemaudio, filter: filter!) }

        // while recording, keep a timer which updates the menu's stats
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateMenu()
        }
        RunLoop.current.add(updateTimer!, forMode: .common) // required to have the menu update while open
        updateTimer?.fire()
    }

    func record(audioOnly: Bool, filter: SCContentFilter) async {
        let conf = SCStreamConfiguration()
        conf.width = 2
        conf.height = 2

        if !audioOnly {
            conf.width = Int(filter.contentRect.width) * (ud.bool(forKey: "highRes") ? Int(filter.pointPixelScale) : 1)
            conf.height = Int(filter.contentRect.height) * (ud.bool(forKey: "highRes") ? Int(filter.pointPixelScale) : 1)
        }

        conf.minimumFrameInterval = CMTime(value: 1, timescale: audioOnly ? CMTimeScale.max : CMTimeScale(ud.integer(forKey: "frameRate")))
        conf.showsCursor = ud.bool(forKey: "showMouse")
        conf.capturesAudio = true
        conf.sampleRate = audioSettings["AVSampleRateKey"] as! Int
        conf.channelCount = audioSettings["AVNumberOfChannelsKey"] as! Int

        stream = SCStream(filter: filter, configuration: conf, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            if !audioOnly {
                initVideo(conf: conf)
            } else {
                startTime = Date.now
            }
            try await stream.startCapture()
        } catch {
            assertionFailure("capture failed".local)
            return
        }

        DispatchQueue.main.async { [self] in
            updateIcon()
            createMenu()
        }

        allowShortcuts(true)
    }

    @objc func stopRecording() {
        statusItem.menu = nil

        if stream != nil {
            stream.stopCapture()
        }
        stream = nil
        if streamType != .systemaudio {
            closeVideo()
        }
        streamType = nil
        audioFile = nil // close audio file
        window = nil
        screen = nil
        startTime = nil
        updateTimer?.invalidate()

        DispatchQueue.main.async { [self] in
            updateIcon()
            createMenu()
        }

        allowShortcuts(true)

        let content = UNMutableNotificationContent()
        content.title = "Recording Completed".local
        if let filePath = filePath {
            content.body = String(format: "File saved to: %@".local, filePath)
        } else {
            content.body = String(format: "File saved to folder: %@".local, ud.string(forKey: "saveDirectory")!)
        }
        content.sound = UNNotificationSound.default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "azayaka.completed.\(Date.now)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Notification failed to send: \(error.localizedDescription)") }
        }
    }

    func updateAudioSettings() {
        audioSettings = [AVSampleRateKey : 48000, AVNumberOfChannelsKey : 2] // reset audioSettings
        switch ud.string(forKey: "audioFormat") {
        case AudioFormat.aac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] = ud.integer(forKey: "audioQuality") * 1000
        case AudioFormat.alac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatAppleLossless
            audioSettings[AVEncoderBitDepthHintKey] = 16
        case AudioFormat.flac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatFLAC
        case AudioFormat.opus.rawValue:
            audioSettings[AVFormatIDKey] = ud.string(forKey: "videoFormat") != VideoFormat.mp4.rawValue ? kAudioFormatOpus : kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] =  ud.integer(forKey: "audioQuality") * 1000
        default:
            assertionFailure("unknown audio format while setting audio settings: ".local + (ud.string(forKey: "audioFormat") ?? "[no defaults]".local))
        }
    }

    func prepareAudioRecording() {
        var fileEnding = ud.string(forKey: "audioFormat") ?? "wat"
        switch fileEnding { // todo: I'd like to store format info differently
            case AudioFormat.aac.rawValue: fallthrough
            case AudioFormat.alac.rawValue: fileEnding = "m4a"
            case AudioFormat.flac.rawValue: fileEnding = "flac"
            case AudioFormat.opus.rawValue: fileEnding = "ogg"
            default: assertionFailure("loaded unknown audio format: ".local + fileEnding)
        }
        filePath = "\(getFilePath()).\(fileEnding)"
        audioFile = try! AVAudioFile(forWriting: URL(fileURLWithPath: filePath), settings: audioSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func getFilePath() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
        var fileName = ud.string(forKey: Preferences.fileName)
        if fileName == nil || fileName!.isEmpty {
            fileName = "Recording at %t".local
        }
        // bit of a magic number but worst case ".flac" is 5 characters on top of this..
        let fileNameWithDates = fileName!.replacingOccurrences(of: "%t", with: dateFormatter.string(from: Date())).prefix(Int(NAME_MAX) - 5)
        return ud.string(forKey: "saveDirectory")! + "/" + fileNameWithDates
    }

    func getRecordingLength() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        //if self.streamType == nil { self.startTime = nil }
        return formatter.string(from: Date.now.timeIntervalSince(startTime ?? Date.now)) ?? "Unknown".local
    }

    func getRecordingSize() -> String {
        do {
            if let filePath = filePath {
                let fileAttr = try FileManager.default.attributesOfItem(atPath: filePath)
                let byteFormat = ByteCountFormatter()
                byteFormat.allowedUnits = [.useMB]
                byteFormat.countStyle = .file
                return byteFormat.string(fromByteCount: fileAttr[FileAttributeKey.size] as! Int64)
            }
        } catch {
            print(String(format: "failed to fetch file for size indicator: %@".local, error.localizedDescription))
        }
        return "Unknown".local
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}
