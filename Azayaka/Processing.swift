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

        vW = try? AVAssetWriter.init(outputURL: URL(fileURLWithPath: "/Users/mnpn/Downloads/\(getFileName()).mov"), fileType: AVFileType.mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: conf.width,
            AVVideoHeightKey: conf.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: (Double(conf.width) * Double(conf.height) * 10.1),
                //AVVideoExpectedSourceFrameRateKey: 30
            ]
        ]
        vwInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        awInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
        vwInput.expectsMediaDataInRealTime = true
        awInput.expectsMediaDataInRealTime = true

        if vW.canAdd(vwInput) {
            vW.add(vwInput)
        }

        if vW.canAdd(awInput!) {
            vW.add(awInput!)
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
}
