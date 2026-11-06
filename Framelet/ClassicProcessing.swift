//
//  ClassicProcessing.swift
//  Framelet
//
//  Created by Martin Persson on 2024-08-08.
//

import ScreenCaptureKit

// This file contains code related to the "classic" recorder. It uses an
// AVAssetWriter instead of the ScreenCaptureKit recorder found in macOS Sequoia.
// System audio-only recording still uses this.

extension AppDelegate {
    func initClassicRecorder(conf: SCStreamConfiguration, encoder: AVVideoCodecType, filePath: String, fileType: AVFileType) throws {
        startTime = nil

        vW = try AVAssetWriter.init(outputURL: URL(fileURLWithPath: filePath), fileType: fileType)
        vW?.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
        let fpsMultiplier: Double = Double(ud.integer(forKey: Preferences.kFrameRate))/8
        let encoderMultiplier: Double = encoder == .hevc ? 0.5 : 0.9
        let targetBitrate = max(250_000, (Double(conf.width) * Double(conf.height) * fpsMultiplier * encoderMultiplier * 0.7))
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: encoder,
            AVVideoWidthKey: conf.width,
            AVVideoHeightKey: conf.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Int(targetBitrate),
                AVVideoExpectedSourceFrameRateKey: ud.integer(forKey: Preferences.kFrameRate)
            ] as [String : Any]
        ]
        vwInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        awInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
        vwInput.expectsMediaDataInRealTime = true
        awInput.expectsMediaDataInRealTime = true

        guard vW.canAdd(vwInput), vW.canAdd(awInput) else {
            throw NSError(domain: "Framelet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video or system audio to the recording."])
        }
        vW.add(vwInput)
        vW.add(awInput)

        recordMic = ud.bool(forKey: Preferences.kRecordMic)
        if recordMic {
            micInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
            micInput.expectsMediaDataInRealTime = true

            guard vW.canAdd(micInput) else {
                throw NSError(domain: "Framelet", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot add microphone audio to the recording."])
            }
            vW.add(micInput)
        }

        // on macOS 15, the system recorder will handle mic recording directly with SCK + AVAssetWriter
        if #unavailable(macOS 15), recordMic {
            let input = audioEngine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.inputFormat(forBus: 0)) { [self] (buffer, time) in
                guard let sample = buffer.asSampleBuffer else { return }
                captureQueue.async { [weak self] in
                    guard let self, self.startTime != nil, let input = self.micInput,
                          input.isReadyForMoreMediaData else { return }
                    input.append(sample)
                }
            }
            do { try audioEngine.start() }
            catch { input.removeTap(onBus: 0); throw error }
        }

        guard vW.startWriting() else {
            if #unavailable(macOS 15), recordMic {
                audioEngine.inputNode.removeTap(onBus: 0)
                audioEngine.stop()
            }
            throw vW.error ?? NSError(domain: "Framelet", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to start writing the recording."])
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid, let writer = vW, writer.status == .writing else { return }

        switch outputType {
            case .screen:
                if screen == nil && window == nil { break }
                guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let attachments = attachmentsArray.first else { return }
                guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                      let status = SCFrameStatus(rawValue: statusRawValue),
                      status == .complete else { return }

                if vW != nil && vW?.status == .writing, startTime == nil {
                    startTime = Date.now
                    vW.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                }
                if startTime != nil && vwInput.isReadyForMoreMediaData {
                    vwInput.append(sampleBuffer)
                }
                break
            case .audio:
                if streamType == .systemaudio { // write directly to file if not video recording
                    guard let samples = sampleBuffer.asPCMBuffer else { return }
                    do {
                        try audioFile!.write(from: samples)
                    }
                    catch { assertionFailure("audio file writing issue".local) }
                } else { // otherwise send the audio data to AVAssetWriter
                    if startTime != nil && (awInput != nil) && awInput.isReadyForMoreMediaData {
                        awInput.append(sampleBuffer)
                    }
                }
            case .microphone: // only available on sequoia - older versions will use AVAudioEngine
                if streamType != .systemaudio {
                    if startTime != nil && (micInput != nil) && micInput.isReadyForMoreMediaData {
                        micInput.append(sampleBuffer)
                    }
                }
            @unknown default:
                assertionFailure("unknown stream type".local)
        }
    }
}

// https://developer.apple.com/documentation/screencapturekit/capturing_screen_content_in_macos
// For Sonoma updated to https://developer.apple.com/forums/thread/727709
extension CMSampleBuffer {
    var asPCMBuffer: AVAudioPCMBuffer? {
        try? self.withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
            guard let absd = self.formatDescription?.audioStreamBasicDescription else { return nil }
            guard let format = AVAudioFormat(standardFormatWithSampleRate: absd.mSampleRate, channels: absd.mChannelsPerFrame) else { return nil }
            return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: audioBufferList.unsafePointer)
        }
    }
}

// Based on https://gist.github.com/aibo-cora/c57d1a4125e145e586ecb61ebecff47c
extension AVAudioPCMBuffer {
    var asSampleBuffer: CMSampleBuffer? {
        let asbd = self.format.streamDescription
        var sampleBuffer: CMSampleBuffer? = nil
        var format: CMFormatDescription? = nil

        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(asbd.pointee.mSampleRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: CMItemCount(self.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer!,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: self.mutableAudioBufferList
        ) == noErr else { return nil }

        return sampleBuffer
    }
}
