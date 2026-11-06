import AVFoundation
import AVFAudio
import ScreenCaptureKit

extension AppDelegate: SCRecordingOutputDelegate {
    func initVideo(conf: SCStreamConfiguration) throws {
        let encoder: AVVideoCodecType = ud.string(forKey: Preferences.kEncoder) == Encoder.h265.rawValue ? .hevc : .h264
        let isMOV = ud.string(forKey: Preferences.kVideoFormat) == VideoFormat.mov.rawValue
        let fileType: AVFileType = isMOV ? .mov : .mp4
        let ext = isMOV ? "mov" : "mp4"
        let base = getFilePath()
        let destination = URL(fileURLWithPath: base).deletingLastPathComponent()
        let freeBytes = try availableDiskBytes(at: destination)
        guard freeBytes >= diskSpaceReserveBytes else {
            throw NSError(domain: "Framelet", code: 20, userInfo: [NSLocalizedDescriptionKey:
                "Not enough free space to start recording. Free at least 1 GB on the destination volume."])
        }
        var candidate = "\(base).\(ext)"
        var number = 2
        while FileManager.default.fileExists(atPath: candidate) {
            candidate = "\(base) \(number).\(ext)"
            number += 1
        }
        filePath = candidate
        useSystemRecorder = false
        try initClassicRecorder(conf: conf, encoder: encoder, filePath: candidate, fileType: fileType)
    }

    // Called on captureQueue after stopCapture has returned and queued samples have drained.
    func closeVideo(completion: @escaping (Error?) -> Void) {
        if #unavailable(macOS 15), recordMic {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        guard let writer = vW else { completion(nil); return }
        guard writer.status == .writing, startTime != nil else {
            let error = writer.error ?? NSError(domain: "Framelet", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The recording ended before a video frame was written."])
            writer.cancelWriting()
            completion(error)
            return
        }
        vwInput?.markAsFinished()
        awInput?.markAsFinished()
        micInput?.markAsFinished()
        writer.finishWriting {
            if writer.status == .completed { completion(nil) }
            else {
                completion(writer.error ?? NSError(domain: "Framelet", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Could not finish the recording."]))
            }
        }
    }

    func stream(_ stoppedStream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            guard self.stream === stoppedStream, !self.isStopping else { return }
            print("Framelet capture stopped: \(error.localizedDescription)")
            self.stopRecording(withError: true)
        }
    }
}
