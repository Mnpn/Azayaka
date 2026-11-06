//
//  Recording.swift
//  Framelet
//
//  Created by Martin Persson on 2022-12-26.
//

import ScreenCaptureKit
import AVFoundation
import Darwin
import AVFAudio
import KeyboardShortcuts

extension AppDelegate {
    @objc func prepRecord(_ sender: NSMenuItem) {
        guard !isStopping, !isStarting, streamType == nil else {
            if !isStopping && !isStarting { allowShortcuts(true) }
            return
        }
        guard let content = availableContent, sender.identifier?.rawValue == "window",
              let selectedWindow = content.windows.first(where: { sender.title == $0.windowID.description }),
              let owner = selectedWindow.owningApplication,
              let focusedPID = focusedApplicationPID(), owner.processID == focusedPID,
              getValidWindows(for: focusedPID).contains(where: { $0.windowID == selectedWindow.windowID }) else {
            allowShortcuts(true)
            return
        }
        screen = nil
        window = selectedWindow
        streamType = .window
        statusItem.menu = nil
        updateAudioSettings()
        let contentFilter = SCContentFilter(desktopIndependentWindow: selectedWindow)

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
            guard streamType != nil, !isStopping else { return }
            allowShortcuts(false)
            if streamType == .systemaudio { // this creates the file, so make sure this happens after the countdown
                do {
                    try prepareAudioRecording()
                } catch {
                    stopRecording(withError: true)
                    return
                }
            }
            await record(audioOnly: false, filter: contentFilter)
        }
    }

    @objc func stopCountdown() { CountdownManager.shared.finishCountdown(startRecording: false) }
    @objc func skipCountdown() { CountdownManager.shared.finishCountdown(startRecording: true) }

    func record(audioOnly: Bool, filter: SCContentFilter) async {
        isStarting = true
        let conf = SCStreamConfiguration()
        if #available(macOS 15.0, *), !audioOnly {
            conf.captureMicrophone = await ud.bool(forKey: Preferences.kRecordMic) && !audioOnly
        }

        conf.width = 2
        conf.height = 2

        if !audioOnly {
            if #available(macOS 14, *) {
                let scale = 1
                conf.width = Int(filter.contentRect.width) * scale
                conf.height = Int(filter.contentRect.height) * scale
            } else { // macOS Ventura: capture at 1x logical resolution
                conf.width = streamType == .screen
                    ? (screen?.width ?? availableContent!.displays[0].width)
                    : Int(window!.frame.width)
                conf.height = streamType == .screen
                    ? (screen?.height ?? availableContent!.displays[0].height)
                    : Int(window!.frame.height)
            }
        }

        conf.queueDepth = 5 // ensure higher fps at the expense of some memory
        conf.minimumFrameInterval = await CMTime(value: 1, timescale: audioOnly ? CMTimeScale.max : CMTimeScale(ud.integer(forKey: Preferences.kFrameRate)))
        conf.showsCursor = await ud.bool(forKey: Preferences.kShowMouse)
        conf.capturesAudio = true
        conf.sampleRate = 48000
        conf.channelCount = 2

        stream = SCStream(filter: filter, configuration: conf, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
            if #available(macOS 15.0, *), conf.captureMicrophone {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: captureQueue)
            }
            if !audioOnly {
                try initVideo(conf: conf)
            } else {
                startTime = Date.now
            }
            try await stream.startCapture()
            isStarting = false
            if let currentPath = filePath { startDiskSpaceMonitoring(for: currentPath) }
            if stopAfterStart {
                stopAfterStart = false
                stopRecording()
                return
            }
            allowShortcuts(true)
        } catch {
            isStarting = false
            stopAfterStart = false
            alertRecordingFailure(error)
            stream = nil
            stopRecording(withError: true)
            return
        }

        DispatchQueue.main.async { [self] in
            updateIcon()
            createMenu()
        }
    }

    @objc func stopRecordingFromMenu(_ sender: NSMenuItem) {
        stopRecording()
    }

    func stopRecording(withError: Bool = false) {
        DispatchQueue.main.async { [self] in
            guard !isStopping else { return }
            if isStarting { stopAfterStart = true; return }
            guard streamType != nil else { allowShortcuts(true); return }
            isStopping = true
            diskSpaceTimer?.invalidate()
            diskSpaceTimer = nil
            let lowSpaceReason = diskStopReason
            diskStopReason = nil
            allowShortcuts(false)
            let endingStream = stream
            let audioOnly = streamType == .systemaudio
            let finishedPath = filePath
            let finish: () -> Void = { [self] in
                captureQueue.async {
                    let complete: (Error?) -> Void = { error in
                        DispatchQueue.main.async { [self] in
                            stream = nil
                            streamType = nil
                            audioFile = nil
                            window = nil
                            screen = nil
                            startTime = nil
                            vW = nil
                            vwInput = nil
                            awInput = nil
                            micInput = nil
                            updateTimer?.invalidate()
                            isStopping = false
                            updateIcon()
                            if availableContent != nil { createMenu() }
                            allowShortcuts(true)
                            if let error {
                                if withError { print("Framelet finalization: \(error.localizedDescription)") }
                                else { alertRecordingFailure(error) }
                            } else if !withError, let finishedPath {
                                if lowSpaceReason == nil && ud.bool(forKey: Preferences.kMergeAudio) {
                                    postprocessRecording(at: finishedPath)
                                } else {
                                    deliverRecording(at: finishedPath)
                                }
                            }
                            if let lowSpaceReason {
                                let alert = NSAlert()
                                alert.messageText = "Recording stopped"
                                alert.informativeText = lowSpaceReason + "\n\nAudio merging was skipped to conserve disk space."
                                alert.addButton(withTitle: "OK")
                                alert.runModal()
                            }
                        }
                    }
                    if audioOnly { complete(nil) } else { self.closeVideo(completion: complete) }
                }
            }
            if let endingStream {
                endingStream.stopCapture { error in
                    if let error { print("Framelet: stop capture: \(error.localizedDescription)") }
                    finish()
                }
            } else { finish() }
        }
    }

    func updateAudioSettings() {
        audioSettings = [
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey: ud.integer(forKey: Preferences.kAudioQuality) * 1000
        ]
    }

    func prepareAudioRecording() throws {
        var fileEnding = ud.string(forKey: Preferences.kAudioFormat) ?? "wat"
        switch fileEnding { // todo: I'd like to store format info differently
        case AudioFormat.aac.rawValue: fallthrough
        case AudioFormat.alac.rawValue: fileEnding = "m4a"
        case AudioFormat.flac.rawValue: fileEnding = "flac"
        case AudioFormat.opus.rawValue: fileEnding = "ogg"
        default: assertionFailure("loaded unknown audio format: ".local + fileEnding)
        }
        filePath = "\(getFilePath()).\(fileEnding)"
        do {
            audioFile = try AVAudioFile(forWriting: URL(fileURLWithPath: filePath), settings: audioSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Couldn't initialise the audio file!".local
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "Okay".local)
                alert.alertStyle = .critical
                alert.runModal()
            }
            throw error
        }
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

        let saveDirectory = ud.string(forKey: Preferences.kSaveDirectory) ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!.path
        // ensure the destination folder exists
        do {
            try FileManager.default.createDirectory(atPath: saveDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed to create destination folder: ".local + error.localizedDescription)
        }

        return saveDirectory + "/" + fileNameWithDates
    }

    func getRecordingLength() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        formatter.unitsStyle = .positional
        //if self.streamType == nil { self.startTime = nil }
        if !useSystemRecorder || streamType == .systemaudio {
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
        if !useSystemRecorder || streamType == .systemaudio {
            do {
                if let filePath = filePath {
                    let fileAttr = try FileManager.default.attributesOfItem(atPath: filePath)
                    if let size = fileAttr[.size] as? NSNumber {
                        return byteFormat.string(fromByteCount: size.int64Value)
                    }
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
        allowShortcuts(false)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Recording error".local
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Okay".local)
            alert.alertStyle = .critical
            alert.runModal()
            self.allowShortcuts(true)
        }
    }
}

extension AppDelegate {
    func deliverRecording(at path: String) {
        sendRecordingFinishedNotification(filePath: path)
    }

    func postprocessRecording(at path: String) {
        let audioBitrate = max(128, ud.integer(forKey: Preferences.kAudioQuality))
        let reserveBytes = diskSpaceReserveBytes
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let inputURL = URL(fileURLWithPath: path)
            let asset = AVURLAsset(url: inputURL)
            guard asset.tracks(withMediaType: .audio).count >= 2 else {
                DispatchQueue.main.async { self?.deliverRecording(at: path) }
                return
            }
            let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
                + ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
            guard let binary = pathDirs.map({ URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg").path })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                DispatchQueue.main.async { self?.postprocessingFailed("FFmpeg was not found. Install it to merge audio tracks.", original: path) }
                return
            }
            let ext = inputURL.pathExtension
            let tempURL = inputURL.deletingLastPathComponent()
                .appendingPathComponent(".framelet-mix-" + UUID().uuidString)
                .appendingPathExtension(ext)
            let tempPath = tempURL.path
            let fileManager = FileManager.default
            do {
                let originalAttributes = try fileManager.attributesOfItem(atPath: path)
                let fileSystem = try fileManager.attributesOfFileSystem(forPath: inputURL.deletingLastPathComponent().path)
                guard let freeBytes = (fileSystem[.systemFreeSize] as? NSNumber)?.int64Value,
                      let originalBytes = (originalAttributes[.size] as? NSNumber)?.int64Value,
                      originalBytes >= 0, originalBytes <= Int64.max - reserveBytes,
                      freeBytes >= originalBytes + reserveBytes else {
                    throw NSError(domain: "Framelet", code: 22, userInfo: [NSLocalizedDescriptionKey:
                        "Not enough free space for audio merging while keeping the 1 GB reserve."])
                }
                guard !fileManager.fileExists(atPath: tempPath) else {
                    throw NSError(domain: "Framelet", code: 10, userInfo: [NSLocalizedDescriptionKey: "Temporary output already exists."])
                }
                defer { try? fileManager.removeItem(at: tempURL) }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = ["-nostdin", "-n", "-hide_banner", "-loglevel", "error", "-i", path,
                    "-filter_complex", "[0:a:0][0:a:1]amix=inputs=2:duration=longest:dropout_transition=0[a]",
                    "-map", "0:v:0", "-map", "[a]", "-c:v", "copy", "-c:a", "aac", "-b:a", "\(audioBitrate)k",
                    "-movflags", "+faststart", tempPath]
                let errorPipe = Pipe()
                process.standardOutput = FileHandle.nullDevice
                process.standardError = errorPipe
                try process.run()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let detail = String(data: errorData, encoding: .utf8) ?? "FFmpeg failed."
                    throw NSError(domain: "Framelet", code: 11, userInfo: [NSLocalizedDescriptionKey: detail])
                }
                let mixed = AVURLAsset(url: tempURL)
                let originalSeconds = CMTimeGetSeconds(asset.duration)
                let mixedSeconds = CMTimeGetSeconds(mixed.duration)
                let validDuration = originalSeconds.isFinite && mixedSeconds.isFinite && originalSeconds > 0 &&
                    mixedSeconds >= max(0, originalSeconds - 1.0)
                guard mixed.isPlayable, mixed.tracks(withMediaType: .video).count == 1,
                      mixed.tracks(withMediaType: .audio).count == 1, validDuration else {
                    throw NSError(domain: "Framelet", code: 12, userInfo: [NSLocalizedDescriptionKey: "Mixed output failed validation; the original was retained."])
                }
                let currentAttributes = try fileManager.attributesOfItem(atPath: path)
                guard (originalAttributes[.systemFileNumber] as? NSNumber) == (currentAttributes[.systemFileNumber] as? NSNumber),
                      (originalAttributes[.size] as? NSNumber) == (currentAttributes[.size] as? NSNumber),
                      (originalAttributes[.modificationDate] as? Date) == (currentAttributes[.modificationDate] as? Date) else {
                    throw NSError(domain: "Framelet", code: 13, userInfo: [NSLocalizedDescriptionKey: "The original changed during processing; it was not replaced."])
                }
                // Both files are in the same folder. POSIX rename replaces the original atomically.
                let result = tempPath.withCString { source in
                    path.withCString { destination in Darwin.rename(source, destination) }
                }
                guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                DispatchQueue.main.async { self?.deliverRecording(at: path) }
            } catch {
                DispatchQueue.main.async { self?.postprocessingFailed(error.localizedDescription, original: path) }
            }
        }
    }

    func postprocessingFailed(_ message: String, original: String) {
        let alert = NSAlert()
        alert.messageText = "Could not merge audio tracks"
        alert.informativeText = "The original recording is safe. \n\n" + message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        deliverRecording(at: original)
    }
}

extension AppDelegate {
    func availableDiskBytes(at directory: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        guard let free = attrs[.systemFreeSize] as? NSNumber else {
            throw NSError(domain: "Framelet", code: 21, userInfo: [NSLocalizedDescriptionKey:
                "Could not determine free space on the recording destination."])
        }
        return free.int64Value
    }

    func startDiskSpaceMonitoring(for path: String) {
        diskSpaceTimer?.invalidate()
        diskStopReason = nil
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        let check = { [weak self] in
            guard let self, !self.diskCheckInFlight, !self.isStopping, self.streamType != nil else { return }
            self.diskCheckInFlight = true
            DispatchQueue.global(qos: .utility).async {
                let result = Result { try self.availableDiskBytes(at: directory) }
                DispatchQueue.main.async {
                    self.diskCheckInFlight = false
                    guard !self.isStopping, self.filePath == path, self.streamType != nil else { return }
                    switch result {
                    case .success(let freeBytes) where freeBytes < self.diskSpaceReserveBytes:
                        self.diskStopReason = "Less than 1 GB remains on the recording destination. Framelet stopped recording to help protect the file."
                        self.stopRecording()
                    case .failure(let error):
                        self.diskStopReason = "Framelet could not check the destination's free space and stopped recording: \(error.localizedDescription)"
                        self.stopRecording()
                    default: break
                    }
                }
            }
        }
        let timer = Timer(timeInterval: 5, repeats: true) { _ in check() }
        diskSpaceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        check()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
    }
}
