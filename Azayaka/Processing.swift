//
//  Processing.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import AVFoundation
import AVFAudio
import ScreenCaptureKit

extension AppDelegate: SCRecordingOutputDelegate {
    func initVideo(conf: SCStreamConfiguration) -> Bool { // returns "success?"
        let encoderIsH265 = ud.string(forKey: "encoder") == Encoder.h265.rawValue
        let encoder = encoderIsH265 ? AVVideoCodecType.hevc : AVVideoCodecType.h264 // yes, not ideal if we want more than these encoders in the future, but it's ok for now
        var fileType: AVFileType!
        let fileEnding = ud.string(forKey: "videoFormat") ?? ""
        switch fileEnding {
            case VideoFormat.mov.rawValue: fileType = AVFileType.mov
            case VideoFormat.mp4.rawValue: fileType = AVFileType.mp4
            default: assertionFailure("loaded unknown video format".local)
        }
        filePath = "\(getFilePath()).\(fileEnding)"
        useLegacyRecorder = ud.bool(forKey: Preferences.useLegacyRecorderKey)
        if #available(macOS 15.0, *), !useLegacyRecorder { // sequoia+, write using SCK if desired
            let output = SCRecordingOutputConfiguration()
            output.outputURL = URL(fileURLWithPath: filePath)
            output.outputFileType = fileType
            output.videoCodecType = .h264

            recordingOutput = SCRecordingOutput(configuration: output, delegate: self)
            do {
                try stream?.addRecordingOutput(recordingOutput as! SCRecordingOutput)
            } catch {
                alertRecordingFailure(error)
                stream = nil
                stopRecording(withError: true)
                return false
            }
        } else { // ventura & sonoma, always write using AVAssetWriter
            initLegacyRecorder(conf: conf, encoder: encoder, filePath: filePath, fileType: fileType!)
        }
        return true
    }

    func closeVideo() {
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        vwInput.markAsFinished()
        awInput.markAsFinished()
        if recordMic {
            micInput.markAsFinished()
            if #unavailable(macOS 15) {
                audioEngine.inputNode.removeTap(onBus: 0)
                audioEngine.stop()
            }
        }
        vW.finishWriting {
            self.startTime = nil
            dispatchGroup.leave()
        }
        dispatchGroup.wait()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { // stream error
        print("closing stream with error:\n".local, error,
              "\nthis might be due to the window closing or the user stopping from the sonoma ui".local)
        DispatchQueue.main.async {
            self.stream = nil
            self.stopRecording()
        }
    }
}
