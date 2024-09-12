//
//  Recording.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import ScreenCaptureKit
import AVFAudio
import KeyboardShortcuts

extension AppDelegate {
    @objc func prepRecord(_ sender: NSMenuItem) {
        guard availableContent != nil else { print("no available content?"); allowShortcuts(true); return }
        screen = availableContent!.displays.first(where: { sender.title == $0.displayID.description })
        window = availableContent!.windows.first(where: { sender.title == $0.windowID.description })

        switch (sender.identifier?.rawValue) {
            case "window":  streamType = .window
            case "display": streamType = .screen
            case "audio":   streamType = .systemaudio
            default: return // if we don't even know what to record I don't think we should even try
        }

        statusItem.menu = nil
        updateAudioSettings()

        // filter content
        let contentFilter: SCContentFilter?
        if streamType == .window {
            contentFilter = SCContentFilter(desktopIndependentWindow: window!)
        } else {
            let excluded = availableContent?.applications.filter { app in
                Bundle.main.bundleIdentifier == app.bundleIdentifier && ud.bool(forKey: Preferences.kHideSelf)
            }
            contentFilter = SCContentFilter(display: screen ?? availableContent!.displays.first!, excludingApplications: excluded ?? [], exceptingWindows: [])
        }

        // count down and start setting up recording
        let countdown = ud.integer(forKey: Preferences.kCountdownSecs)
        if countdown > 0 {
            let cdMenu = NSMenu()
            cdMenu.addItem(NSMenuItemWithIcon(icon: "chevron.forward.2", title: "Skip countdown".local, action: #selector(skipCountdown)))
            cdMenu.addItem(NSMenuItemWithIcon(icon: "xmark", title: "Cancel".local, action: #selector(stopCountdown)))
            addMenuFooter(toMenu: cdMenu)
            statusItem.menu = cdMenu
        }
        allowShortcuts(true)
        Task {
            guard await CountdownManager.shared.showCountdown(countdown) else {
                stopRecording(withError: true)
                return
            }
            allowShortcuts(false)
            DispatchQueue.main.async { [self] in
                if streamType == .systemaudio { // this creates the file, so make sure this happens after the countdown
                    prepareAudioRecording()
                }
            }
            await record(audioOnly: streamType == .systemaudio, filter: contentFilter!)
        }

        // while recording, keep a timer which updates the menu's stats
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateMenu()
        }
        RunLoop.current.add(updateTimer!, forMode: .common) // required to have the menu update while open
        updateTimer?.fire()
    }

    @objc func stopCountdown() { CountdownManager.shared.finishCountdown(startRecording: false) }
    @objc func skipCountdown() { CountdownManager.shared.finishCountdown(startRecording: true) }

    func record(audioOnly: Bool, filter: SCContentFilter) async {
        var conf = SCStreamConfiguration()
        if #available(macOS 15.0, *), !audioOnly {
            if await ud.bool(forKey: Preferences.kEnableHDR) {
                conf = SCStreamConfiguration(preset: .captureHDRStreamCanonicalDisplay)
            }
            conf.captureMicrophone = await ud.bool(forKey: Preferences.kRecordMic) && !audioOnly
        }

        conf.width = 2
        conf.height = 2

        if !audioOnly {
            if #available(macOS 14, *) {
                let scale = await ud.bool(forKey: Preferences.kHighResolution) ? Int(filter.pointPixelScale) : 1
                conf.width = Int(filter.contentRect.width) * scale
                conf.height = Int(filter.contentRect.height) * scale
            } else { // ventura..
                // this code is just bad but I don't know how to do it better, the good solution (above) is sonoma+..
                // it seems windows are available on all displays, and there's no way to get a window's display
                let scale = Int(
                    (screen != nil
                        ? NSScreen.screens.first(where: { $0.displayID == screen?.displayID })!.backingScaleFactor
                        : NSScreen.main?.backingScaleFactor)
                    ?? 1)
                conf.width = streamType == .screen
                    ? availableContent!.displays[0].width*scale
                    : Int( (window?.frame.width)!*CGFloat(scale) )
                conf.height = streamType == .screen
                    ? availableContent!.displays[0].height*scale
                    : Int( (window?.frame.height)!*CGFloat(scale) )
            }
        }

        conf.queueDepth = 5 // ensure higher fps at the expense of some memory
        conf.minimumFrameInterval = await CMTime(value: 1, timescale: audioOnly ? CMTimeScale.max : CMTimeScale(ud.integer(forKey: Preferences.kFrameRate)))
        conf.showsCursor = await ud.bool(forKey: Preferences.kShowMouse)
        conf.capturesAudio = true
        conf.sampleRate = audioSettings["AVSampleRateKey"] as! Int
        conf.channelCount = audioSettings["AVNumberOfChannelsKey"] as! Int

        stream = SCStream(filter: filter, configuration: conf, delegate: self)
        startRecording: do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            if #available(macOS 15.0, *), conf.captureMicrophone {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: .global())
            }
            if !audioOnly {
                if !initVideo(conf: conf) { break startRecording }
            } else {
                startTime = Date.now
            }
            try await stream.startCapture()
        } catch {
            alertRecordingFailure(error)
            stream = nil
            stopRecording(withError: true)
            return
        }

        DispatchQueue.main.async { [self] in
            updateIcon()
            createMenu()
        }

        allowShortcuts(true)
    }

    @objc func stopRecording(withError: Bool = false) {
        statusItem.menu = nil

        if stream != nil {
            stream.stopCapture()
            stream = nil
        }

        if useLegacyRecorder {
            startTime = nil
            if streamType != .systemaudio {
                closeVideo()
            }
        } else {
            recordingOutput = nil
        }
        streamType = nil
        audioFile = nil // close audio file
        window = nil
        screen = nil
        
        updateTimer?.invalidate()

        DispatchQueue.main.async { [self] in
            updateIcon()
            createMenu()
        }

        allowShortcuts(true)
        if !withError {
            sendRecordingFinishedNotification()
        }
    }

    func updateAudioSettings() {
        audioSettings = [AVSampleRateKey : 48000, AVNumberOfChannelsKey : 2] // reset audioSettings
        switch ud.string(forKey: Preferences.kAudioFormat) {
        case AudioFormat.aac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] = ud.integer(forKey: Preferences.kAudioQuality) * 1000
        case AudioFormat.alac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatAppleLossless
            audioSettings[AVEncoderBitDepthHintKey] = 16
        case AudioFormat.flac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatFLAC
        case AudioFormat.opus.rawValue:
            audioSettings[AVFormatIDKey] = ud.string(forKey: Preferences.kAudioFormat) != VideoFormat.mp4.rawValue ? kAudioFormatOpus : kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] = ud.integer(forKey: Preferences.kAudioQuality) * 1000
        default:
            assertionFailure("unknown audio format while setting audio settings: ".local + (ud.string(forKey: Preferences.kAudioFormat) ?? "[no defaults]".local))
        }
    }

    func prepareAudioRecording() {
        var fileEnding = ud.string(forKey: Preferences.kAudioFormat) ?? "wat"
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
        var fileName = ud.string(forKey: Preferences.kFileName)
        if fileName == nil || fileName!.isEmpty {
            fileName = "Recording at %t".local
        }
        // bit of a magic number but worst case ".flac" is 5 characters on top of this..
        let fileNameWithDates = fileName!.replacingOccurrences(of: "%t", with: dateFormatter.string(from: Date())).prefix(Int(NAME_MAX) - 5)

        let saveDirectory = ud.string(forKey: Preferences.kSaveDirectory)
        // ensure the destination folder exists
        do {
            try FileManager.default.createDirectory(atPath: saveDirectory!, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create destination folder: ".local + error.localizedDescription)
        }

        return saveDirectory! + "/" + fileNameWithDates
    }

    func getRecordingLength() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        //if self.streamType == nil { self.startTime = nil }
        if useLegacyRecorder || streamType == .systemaudio {
            return formatter.string(from: Date.now.timeIntervalSince(startTime ?? Date.now)) ?? "Unknown".local
        } else if #available(macOS 15, *) {
            if let recOut = (recordingOutput as? SCRecordingOutput) {
                if recOut.recordedDuration.seconds.isNaN { return "00:00" }
                return formatter.string(from: recOut.recordedDuration.seconds) ?? "Unknown".local
            }
        }
        return "--:--"
    }

    func getRecordingSize() -> String {
        let byteFormat = ByteCountFormatter()
        byteFormat.allowedUnits = [.useMB]
        byteFormat.countStyle = .file
        if useLegacyRecorder || streamType == .systemaudio {
            do {
                if let filePath = filePath {
                    let fileAttr = try FileManager.default.attributesOfItem(atPath: filePath)
                    return byteFormat.string(fromByteCount: fileAttr[FileAttributeKey.size] as! Int64)
                }
            } catch {
                print(String(format: "failed to fetch file for size indicator: %@".local, error.localizedDescription))
            }
        } else if #available(macOS 15, *), let recOut = (recordingOutput as? SCRecordingOutput) {
            return byteFormat.string(fromByteCount: Int64(recOut.recordedFileSize))
        }
        return "Unknown".local
    }
    
    func alertRecordingFailure(_ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Capture failed!".local
            alert.informativeText = String(format: "Couldn't start the recording:\n“%@”\n\nIt is possible that the recording settings, such as HDR or the encoder, are not compatible with your device.".local, error.localizedDescription)
            alert.addButton(withTitle: "Okay".local)
            alert.alertStyle = .critical
            alert.runModal()
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}
