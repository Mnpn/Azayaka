//
//  Processing.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import AVFoundation
import AVFAudio
import ScreenCaptureKit

extension AppDelegate {
    func initMedia(conf: SCStreamConfiguration, audioOnly: Bool = false) {
        startTime = nil
        
        let filePathAndAssetWriter = getFilePathAndAssetWriter(audioOnly: audioOnly)

        filePath = filePathAndAssetWriter.0
        vW = filePathAndAssetWriter.1
        let encoderIsH265 = ud.string(forKey: "encoder") == Encoder.h265.rawValue
        let fpsMultiplier: Double = Double(ud.integer(forKey: "frameRate"))/8
        let encoderMultiplier: Double = encoderIsH265 ? 0.5 : 0.9
        let targetBitrate = (Double(conf.width) * Double(conf.height) * fpsMultiplier * encoderMultiplier)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: encoderIsH265 ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            // yes, not ideal if we want more than these encoders in the future, but it's ok for now
            AVVideoWidthKey: conf.width,
            AVVideoHeightKey: conf.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate,
                AVVideoExpectedSourceFrameRateKey: ud.integer(forKey: "frameRate")
            ] as [String : Any]
        ]
        recordMic = ud.bool(forKey: "recordMic")
        vwInput = audioOnly ? nil : AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        awInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
        micInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
        vwInput?.expectsMediaDataInRealTime = true
        awInput.expectsMediaDataInRealTime = true
        micInput.expectsMediaDataInRealTime = true

        if !audioOnly, vW.canAdd(vwInput) {
            vW.add(vwInput)
        }

        if vW.canAdd(awInput) {
            vW.add(awInput)
        }

        if recordMic {
            if vW.canAdd(micInput) {
                vW.add(micInput)
            }

            let input = audioEngine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.inputFormat(forBus: 0)) { [self] (buffer, time) in
                if micInput.isReadyForMoreMediaData {
                    micInput.append(buffer.asSampleBuffer!)
                }
            }
            try! audioEngine.start()
        }
        vW.startWriting()
    }

    func closeMedia() {
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        vwInput?.markAsFinished()
        awInput.markAsFinished()
        if recordMic {
            micInput.markAsFinished()
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        vW.finishWriting {
            self.startTime = nil
            dispatchGroup.leave()
        }
        dispatchGroup.wait()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        if vW != nil && vW?.status == .writing, startTime == nil {
            startTime = Date.now
            vW.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        
        switch outputType {
            case .screen:
                if screen == nil && window == nil { break }
                guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let attachments = attachmentsArray.first else { return }
                guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                      let status = SCFrameStatus(rawValue: statusRawValue),
                      status == .complete else { return }
               
                if vwInput.isReadyForMoreMediaData {
                    vwInput.append(sampleBuffer)
                }
                break
            case .audio:
                if awInput.isReadyForMoreMediaData {
                    awInput.append(sampleBuffer)
                }
            @unknown default:
                assertionFailure("unknown stream type")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { // stream error
        print("closing stream with error:\n", error,
              "\nthis might be due to the window closing or the user stopping from the sonoma ui")
        DispatchQueue.main.async {
            self.stream = nil
            self.stopRecording()
        }
    }
    
    /**
    Get the filepath of where the asset writer is writing to and asset writer itself
     */
    private func getFilePathAndAssetWriter(audioOnly: Bool)-> (String, AVAssetWriter?){
        var assetWriter: AVAssetWriter? = nil
        
        var fileEnding: String!
        var fileType: AVFileType!
        
        if audioOnly{
            fileEnding = ud.string(forKey: "audioFormat") ?? "wat"
            fileType = .m4a // it looks like file type m4a works for all tyle extensions. but maybe need to revise this
            switch fileEnding { // todo: I'd like to store format info differently
                case AudioFormat.aac.rawValue: fallthrough
                case AudioFormat.alac.rawValue: fileEnding = "m4a"
                case AudioFormat.flac.rawValue: fileEnding = "flac"
                case AudioFormat.opus.rawValue: fileEnding = "ogg"
                default: assertionFailure("loaded unknown audio format: " + fileEnding)
            }
        }else{
            fileEnding = ud.string(forKey: "videoFormat") ?? ""
            switch fileEnding {
                case VideoFormat.mov.rawValue: fileType = AVFileType.mov
                case VideoFormat.mp4.rawValue: fileType = AVFileType.mp4
                default: assertionFailure("loaded unknown video format")
            }
        }
        
        filePath = "\(getFilePath()).\(fileEnding!)"
        assetWriter = try? AVAssetWriter(outputURL: URL(fileURLWithPath: filePath), fileType: fileType)
        
        return (filePath, assetWriter)
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
