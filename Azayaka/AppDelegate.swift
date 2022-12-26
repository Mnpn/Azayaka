//
//  AppDelegate.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-25.
//

import AVFoundation
import AVFAudio
import Cocoa
import ScreenCaptureKit

@main
class AppDelegate: NSObject, NSApplicationDelegate, SCStreamDelegate, SCStreamOutput {
    var vwInput, awInput: AVAssetWriterInput!
    var vW: AVAssetWriter!
    var sessionBeginAtSourceTime: CMTime!

    let audioSettings: [String : Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC,
                              AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                                       AVSampleRateKey: 48000,
                                   AVEncoderBitRateKey: 320000,
                                 AVNumberOfChannelsKey: 2]

    var stream: SCStream?
    var audioFile: AVAudioFile?
    var availableContent: SCShareableContent?
    var filter: SCContentFilter?

    var isRecording = false
    var screen: SCDisplay?
    var window: SCWindow?

    let excludedWindows = ["", "com.apple.dock", "com.apple.controlcenter", "dev.mnpn.Azayaka"]

    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // create a menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()

        updateAvailableContent()
    }

    func updateAvailableContent() {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
            if error != nil {
                print("[err] failed to fetch available content, permission error?")
                return
            }
            self.availableContent = content
            assert((self.availableContent?.displays.count)! > 0, "There needs to be at least one display connected")
            self.createMenu()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch outputType {
            case .screen:
                if screen == nil && window == nil { break }
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

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            print("stream commited sudoku with error:")
            print(error)
            print("presumably this is due to the window closing")
            self.stopRecording()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        stopRecording()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateAvailableContent()
    }

    func menuDidClose(_ menu: NSMenu) { }
}
