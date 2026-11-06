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
import Vision

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
                                    deliverRecording(at: finishedPath, allowOCR: lowSpaceReason == nil)
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
        // A window title can contain path separators or control characters.
        let rawTitle = window?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = rawTitle.isEmpty ? "Window" : rawTitle
        let unsafeCharacters = CharacterSet(charactersIn: "/:").union(.controlCharacters)
        let safeTitle = title.components(separatedBy: unsafeCharacters).joined(separator: "-")
        let expandedName = fileName!
            .replacingOccurrences(of: "%t", with: dateFormatter.string(from: Date()))
            .replacingOccurrences(of: "%n", with: safeTitle)
        // Leave room for the extension and a duplicate-file suffix; NAME_MAX is in bytes.
        var fileNameWithDates = ""
        for character in expandedName {
            guard fileNameWithDates.utf8.count + String(character).utf8.count <= 200 else { break }
            fileNameWithDates.append(character)
        }

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
    func deliverRecording(at path: String, allowOCR: Bool = true) {
        let runOCR = allowOCR && ud.bool(forKey: Preferences.kOCREnabled)
        let runTranscription = allowOCR && ud.bool(forKey: Preferences.kMacWhisper)
        guard runOCR || runTranscription else {
            sendRecordingFinishedNotification(filePath: path)
            return
        }
        let configuredInterval = ud.integer(forKey: Preferences.kOCRInterval)
        let interval = [30, 60, 120, 300].contains(configuredInterval) ? configuredInterval : 60
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let videoURL = URL(fileURLWithPath: path)
            var errors: [String] = []
            if runOCR {
                do { try self.writeOCRTranscript(for: videoURL, interval: interval) }
                catch { errors.append("OCR: " + error.localizedDescription) }
            }
            if runTranscription {
                do { try self.writeMacWhisperTranscript(for: videoURL) }
                catch { errors.append("MacWhisper: " + error.localizedDescription) }
            }
            DispatchQueue.main.async {
                if !errors.isEmpty {
                    let alert = NSAlert()
                    alert.messageText = "Postprocessing could not be completed"
                    alert.informativeText = "The recording is safe.\n\n" + errors.joined(separator: "\n\n")
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                self.sendRecordingFinishedNotification(filePath: path)
            }
        }
    }

    private func writeOCRTranscript(for videoURL: URL, interval: Int) throws {
        let outputURL = videoURL.deletingLastPathComponent()
            .appendingPathComponent(videoURL.deletingPathExtension().lastPathComponent + " - ocr.md")
        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".framelet-ocr-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw NSError(domain: "FrameletOCR", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create a temporary transcript."])
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let file = try FileHandle(forWritingTo: temporaryURL)
        let asset = AVURLAsset(url: videoURL)
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else {
            try? file.close()
            throw NSError(domain: "FrameletOCR", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not read the video duration."])
        }
        defer { try? file.close() }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try file.write(contentsOf: Data("# OCR transcript\n\n".utf8))
        var seconds = 0
        while Double(seconds) < duration {
            try autoreleasepool {
                var actualTime = CMTime.zero
                let image = try generator.copyCGImage(at: CMTime(seconds: Double(seconds), preferredTimescale: 600), actualTime: &actualTime)
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                let actualSeconds = CMTimeGetSeconds(actualTime)
                let timestampSeconds = actualSeconds.isFinite ? max(0, Int(actualSeconds)) : seconds
                let timestamp = String(format: "%02d:%02d:%02d", timestampSeconds / 3600, (timestampSeconds / 60) % 60, timestampSeconds % 60)
                let text = lines.isEmpty ? "_No text recognized._" : lines.joined(separator: "\n\n")
                try file.write(contentsOf: Data("## \(timestamp)\n\n\(text)\n\n".utf8))
            }
            seconds += interval
        }
        try file.close()
        // Never replace a transcript that already exists.
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
    }

    private func writeMacWhisperTranscript(for videoURL: URL) throws {
        let directory = videoURL.deletingLastPathComponent()
        let outputURL = directory.appendingPathComponent(videoURL.deletingPathExtension().lastPathComponent + " - transcript.md")
        let temporaryURL = directory.appendingPathComponent(".framelet-transcript-" + UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw NSError(domain: "FrameletMacWhisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "A transcript with this name already exists."])
        }
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/usr/local/bin", "/opt/homebrew/bin", "/opt/local/bin"]
        guard let executable = directories.map({ URL(fileURLWithPath: $0).appendingPathComponent("mw").path })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw NSError(domain: "FrameletMacWhisper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Install the CLI in MacWhisper Settings > Advanced > Command-Line Tool."])
        }
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["transcribe", videoURL.path, "--language", "auto", "--format", "md", "--output", temporaryURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(domain: "FrameletMacWhisper", code: 3, userInfo: [NSLocalizedDescriptionKey: detail.isEmpty ? "MacWhisper failed (exit \(process.terminationStatus))." : detail])
        }
        guard FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw NSError(domain: "FrameletMacWhisper", code: 4, userInfo: [NSLocalizedDescriptionKey: "MacWhisper did not produce a transcript."])
        }
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
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
