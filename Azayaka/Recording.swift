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
        // file preparation
        audioOnly = sender.identifier?.rawValue == "audio"
        if audioOnly {
            audioFile = try! AVAudioFile(forWriting: NSURL(fileURLWithPath: "/Users/mnpn/Downloads/" + getFileName() + ".m4a") as URL, settings: audioSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        }
        Task { await record(screen: !audioOnly) }
    }

    func record(screen: Bool) async {
        let conf = SCStreamConfiguration()
        if screen && window != nil { // todo: cleanup
            conf.width = window == nil ? availableContent!.displays[0].width*2 : Int((window?.frame.width)!*2)
            conf.height = window == nil ? availableContent!.displays[0].height*2 : Int((window?.frame.height)!*2)
        } else {
            conf.width = 2
            conf.height = 2
        }

        conf.minimumFrameInterval = CMTime(value: 1, timescale: screen ? 60 : CMTimeScale(1))
        conf.showsCursor = true
        conf.capturesAudio = true
        conf.sampleRate = 48000
        conf.channelCount = 2

        stream = SCStream(filter: filter!, configuration: conf, delegate: self)
        do {
            try! stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global())
            try! stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            if screen {
                initVideo(conf: conf)
            }
            try await stream?.startCapture()
        } catch {
            assertionFailure("capture failed")
            return
        }
        isRecording = true
        updateIcon()
        createMenu()
    }

    @objc func stopRecording() {
        if !audioOnly {
            closeVideo()
        } else {
            audioFile = nil // nilling the file closes it
        }
        stream?.stopCapture()
        isRecording = false
        window = nil
        updateIcon()
        createMenu()
    }

    func getFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "y-MM-dd HH.mm.ss"
        return "Recording at " + dateFormatter.string(from: Date())
    }
}
