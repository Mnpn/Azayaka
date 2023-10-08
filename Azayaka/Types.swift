//
//  Types.swift
//  Azayaka
//
//  Created by Martin Persson on 2022-12-27.
//

enum AudioQuality: Int {
    case normal = 128, good = 192, high = 256, extreme = 320
}

enum AudioFormat: String {
    case aac, alac, flac, opus
}

enum VideoFormat: String {
    case mov, mp4
}

enum Encoder: String {
    case h264, h265
}

enum StreamType: Int {
    case screen, window, systemaudio
}
