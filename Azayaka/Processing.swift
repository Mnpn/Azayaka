//
//  Processing.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import AVFoundation
import AVFAudio
import ScreenCaptureKit

// https://developer.apple.com/documentation/screencapturekit/capturing_screen_content_in_macos
func createPCMBuffer(for sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
    var ablPointer: UnsafePointer<AudioBufferList>?
    try? sampleBuffer.withAudioBufferList { audioBufferList, blockBuffer in
        ablPointer = audioBufferList.unsafePointer
    }
    guard let audioBufferList = ablPointer,
          let absd = sampleBuffer.formatDescription?.audioStreamBasicDescription,
          let format = AVAudioFormat(standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame) else { return nil }
    return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList)
}

extension AppDelegate {
    func initVideo(conf: SCStreamConfiguration) {
        sessionBeginAtSourceTime = nil

        let fileEnding = ud.string(forKey: "videoFormat") ?? ""
        var fileType: AVFileType?
        switch fileEnding {
            case VideoFormat.mov.rawValue: fileType = AVFileType.mov
            case VideoFormat.mp4.rawValue: fileType = AVFileType.mp4
            default: assertionFailure("loaded unknown video format")
        }

        vW = try? AVAssetWriter.init(outputURL: URL(fileURLWithPath: "/Users/mnpn/Downloads/\(getFileName()).\(fileEnding)"), fileType: fileType!)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: ud.string(forKey: "encoder") == Encoder.h264.rawValue ? AVVideoCodecType.h264 : AVVideoCodecType.hevc,
            // yes, not ideal if we want more than these encoders in the future, but it's ok for now
            AVVideoWidthKey: conf.width,
            AVVideoHeightKey: conf.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: (Double(conf.width) * Double(conf.height) * 10.1),
                AVVideoExpectedSourceFrameRateKey: ud.integer(forKey: "frameRate")
            ]
        ]
        vwInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        awInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
        vwInput.expectsMediaDataInRealTime = true
        awInput.expectsMediaDataInRealTime = true

        if vW.canAdd(vwInput) {
            vW.add(vwInput)
        }

        if vW.canAdd(awInput) {
            vW.add(awInput)
        }

        vW.startWriting()
    }

    func closeVideo() {
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        vwInput.markAsFinished()
        awInput.markAsFinished()
        vW.finishWriting {
            self.sessionBeginAtSourceTime = nil
            dispatchGroup.leave()
        }
        dispatchGroup.wait()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch outputType {
            case .screen:
                if screen == nil && window == nil { break }
                duration = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) - (sessionBeginAtSourceTime?.seconds ?? 0) // todo: this probably runs a bit too much, can this be moved?
                guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let attachments = attachmentsArray.first else { return }
                guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                      let status = SCFrameStatus(rawValue: statusRawValue),
                      status == .complete else { return }

                if vW != nil && vW?.status == .writing, sessionBeginAtSourceTime == nil {
                    sessionBeginAtSourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    vW.startSession(atSourceTime: sessionBeginAtSourceTime!)
                }
                if vwInput.isReadyForMoreMediaData {
                    vwInput.append(sampleBuffer)
                }
                break
            case .audio:
                if screen == nil && window == nil { // write directly to file if not video recording
                    guard let samples = createPCMBuffer(for: sampleBuffer) else { return }
                    do {
                        try audioFile?.write(from: samples)
                    }
                    catch { assertionFailure("audio file writing issue") }
                } else { // otherwise send the audio data to AVAssetWriter
                    if awInput.isReadyForMoreMediaData {
                        awInput.append(sampleBuffer)
                    }
                }
            @unknown default:
                assertionFailure("unknown stream type")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { // stream error
        DispatchQueue.main.async {
            print("Closing stream with error:", error)
            print("This might be due to the window closing")
            self.stopRecording()
        }
    }
}
