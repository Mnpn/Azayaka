//
//  Processing.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-26.
//

import Foundation
import AVFAudio

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
