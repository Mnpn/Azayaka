//
//  Recording.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import Foundation
import AppKit
import ScreenCaptureKit
import AVFAudio

extension AppDelegate {
    @objc func prepRecord(_ sender: NSMenuItem) {
        // todo: prep filtering stuff
        Task { await record(screen: sender.identifier?.rawValue != "audio") }
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Azayaka")
        }
    }

    func record(screen: Bool) async {
        let conf = SCStreamConfiguration()
        conf.width = screen ? availableContent!.displays[0].width : 2
        conf.height = screen ? availableContent!.displays[0].height : 2
        conf.minimumFrameInterval = CMTime(value: 1, timescale: screen ? CMTimeScale(60) : CMTimeScale(1))
        conf.showsCursor = true
        conf.capturesAudio = true
        conf.sampleRate = 48000
        conf.channelCount = 2

        stream = SCStream(filter: filter!, configuration: conf, delegate: self)

        // file preparation
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
        audioFile = try! AVAudioFile(forWriting: NSURL(fileURLWithPath: "/Users/mnpn/Downloads/Recording at " + dateFormatter.string(from: Date()) + ".m4a") as URL, settings:
                                        [AVFormatIDKey: kAudioFormatMPEG4AAC,
                              AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                                       AVSampleRateKey: 48000,
                                   AVEncoderBitRateKey: 320000,
                                 AVNumberOfChannelsKey: 2],
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        do {
            try! stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            try! stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            try await stream?.startCapture()
        } catch {
            assertionFailure("capture failed")
        }
        isRecording = true
        createMenu()
    }

    @objc func stopRecording() {
        stream?.stopCapture()
        audioFile = nil // nilling the file closes it
        isRecording = false
        updateIcon()
        createMenu()
    }
}
