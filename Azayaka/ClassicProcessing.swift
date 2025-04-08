//
//  ClassicProcessing.swift
//  Azayaka
//
//  Created by Martin Persson on 2024-08-08.
//

import ScreenCaptureKit

// This file contains code related to the "classic" recorder. It uses an
// AVAssetWriter instead of the ScreenCaptureKit recorder found in macOS Sequoia.
// System audio-only recording still uses this.

class ClassicProcessing: NSObject {
    var startTime: Date?
    var vW: AVAssetWriter!
    var vwInput: AVAssetWriterInput!
    var awInput: AVAssetWriterInput!
    var micInput: AVAssetWriterInput!
    var audioFile: AVAudioFile!
    var recordMic: Bool!
    var downloadsFolder: String!
    var stream: SCStream!
    var fileType: AVFileType!
    var videoSettings: [String: Any]!
    var audioSettings: [String: Any]!
    var ud = UserDefaults.standard
    var audioEngine = AVAudioEngine()
    var replayBuffer: ReplayBuffer?

    init(stream: SCStream, conf: SCStreamConfiguration, encoder: AVVideoCodecType, filePath: String, fileType: AVFileType, videoSettings: [String: Any], audioSettings: [String: Any]) {
        super.init()
        self.stream = stream
        self.fileType = fileType
        self.videoSettings = videoSettings
        self.audioSettings = audioSettings
        downloadsFolder = ud.string(forKey: Preferences.kDownloadsFolder) ?? "~/Downloads".local.standardizingPath
        
        startTime = nil

        vW = try? AVAssetWriter.init(outputURL: URL(fileURLWithPath: filePath), fileType: fileType)
        let fpsMultiplier: Double = Double(ud.integer(forKey: Preferences.kFrameRate))/8
        let encoderMultiplier: Double = encoder == .hevc ? 0.5 : 0.9
        let targetBitrate = (Double(conf.width) * Double(conf.height) * fpsMultiplier * encoderMultiplier * ud.double(forKey: Preferences.kVideoQuality))
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
        
        if vW.canAdd(vwInput) {
            vW.add(vwInput)
        }
        
        if vW.canAdd(awInput) {
            vW.add(awInput)
        }
        
        recordMic = ud.bool(forKey: Preferences.kRecordMic)
        if recordMic {
            micInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
            micInput.expectsMediaDataInRealTime = true
            
            if vW.canAdd(micInput) {
                vW.add(micInput)
            }
        }

        // on macOS 15, the system recorder will handle mic recording directly with SCK + AVAssetWriter
        if #unavailable(macOS 15), recordMic {
            let input = audioEngine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.inputFormat(forBus: 0)) { [self] (buffer, time) in
                if micInput.isReadyForMoreMediaData && startTime != nil {
                    micInput.append(buffer.asSampleBuffer!)
                }
            }
            try! audioEngine.start()
        }

        vW.startWriting()
        
        replayBuffer = ReplayBuffer(frameRate: Double(ud.integer(forKey: Preferences.kFrameRate)))
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        
        replayBuffer?.add(sampleBuffer)

        switch outputType {
            case .screen:
                guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                      let attachments = attachmentsArray.first else { return }
                guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                      let status = SCFrameStatus(rawValue: statusRawValue),
                      status == .complete else { return }
                
                if vW != nil && vW?.status == .writing, startTime == nil {
                    startTime = Date.now
                    vW.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                }
                if vwInput.isReadyForMoreMediaData {
                    vwInput.append(sampleBuffer)
                }
                break
            case .audio:
                if awInput != nil && awInput.isReadyForMoreMediaData {
                    awInput.append(sampleBuffer)
                }
                break
            case .microphone: // only available on sequoia - older versions will use AVAudioEngine
                if micInput != nil && micInput.isReadyForMoreMediaData {
                    micInput.append(sampleBuffer)
                }
                break
            @unknown default:
                assertionFailure("unknown stream type".local)
        }
    }
}

extension ClassicProcessing {
    @objc func saveReplayBuffer() {
        guard let replayBuffer = self.replayBuffer else { return }
        let samples = replayBuffer.getSamples()
        guard !samples.isEmpty else { return }
        
        let filePath = "\(downloadsFolder)/Replay \(Date().formatted(date: .numeric, time: .standard)).\(fileType.fileExtension)"
        
        let vW = try? AVAssetWriter.init(outputURL: URL(fileURLWithPath: filePath), fileType: fileType)
        let vwInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        vwInput.expectsMediaDataInRealTime = true
        
        if vW.canAdd(vwInput) {
            vW.add(vwInput)
        }
        
        vW.startWriting()
        vW.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(samples.first!))
        
        for sample in samples {
            if vwInput.isReadyForMoreMediaData {
                vwInput.append(sample)
            }
        }
        
        vwInput.markAsFinished()
        vW.finishWriting {
            guard let error = vW.error else {
                DispatchQueue.main.async {
                    let notif = NSUserNotification()
                    notif.title = "Replay saved!".local
                    notif.informativeText = "Your replay has been saved to \(self.downloadsFolder ?? "Downloads".local) as Replay \(Date().formatted(date: .numeric, time: .standard)).\(self.fileType?.fileExtension ?? "mp4")."
                    NSUserNotificationCenter.default.deliver(notif)
                }
                replayBuffer.clear()
                return
            }
            
            DispatchQueue.main.async {
                let notif = NSUserNotification()
                notif.title = "Replay failed!".local
                notif.informativeText = "There was an issue saving the replay, sorry! \(error.localizedDescription)"
                NSUserNotificationCenter.default.deliver(notif)
            }
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
