//
//  Countdown.swift
//  Azayaka
//
//  Created by resistanceto on 2024/5/30.
//

import SwiftUI

class CountdownManager: ObservableObject {
    @Published var countdown: Int = 0
    static let shared = CountdownManager()
    private var countdownWindow: NSWindow?
    var timer: DispatchSourceTimer!
    private var continuation: CheckedContinuation<Bool, Never>?

    @MainActor
    func showCountdown(_ countdown: Int) async -> Bool { // returns if the countdown completed
        if countdown == 0 { return true }
        return await withCheckedContinuation { cont in
            continuation = cont
            self.countdown = countdown
            countdownWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                styleMask: [.borderless],
                backing: .buffered, defer: false)
            countdownWindow?.isReleasedWhenClosed = false
            countdownWindow?.level = .floating
            countdownWindow?.center()
            countdownWindow?.backgroundColor = .clear
            countdownWindow?.isOpaque = false
            countdownWindow?.hasShadow = true
            countdownWindow?.ignoresMouseEvents = true
            let countdownView = NSHostingView(rootView: CountdownView().environmentObject(self))
            countdownWindow?.contentView = countdownView
            if let countdownWindow = countdownWindow { countdownWindow.orderFrontRegardless() }
            timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + 1, repeating: 1.0)
            timer.setEventHandler {
                Task { @MainActor in
                    self.countdown -= 1
                    if self.countdown < 1 {
                        self.finishCountdown(startRecording: true)
                    }
                }
            }
            timer.resume()
        }
    }

    @objc func finishCountdown(startRecording: Bool = false) {
        timer.cancel()
        countdownWindow?.close()
        countdownWindow = nil
        timer = nil
        continuation?.resume(returning: startRecording)
    }
}

struct CountdownView: View {
    @EnvironmentObject var countdownManager: CountdownManager
    @State var progress: Double = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(.gray, lineWidth: 8)
                .scaleEffect(0.7)
            Circle() // because apparently scaling a ProgressView doesn't work?
                .trim(from: 0, to: progress)
                .rotation(.degrees(-90))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .scaleEffect(0.7)
                .onAppear {
                    withAnimation(.linear(duration: TimeInterval(countdownManager.countdown))) {
                        progress = 1
                    }
                }
            Text("\(countdownManager.countdown)")
                .font(.largeTitle)
                .foregroundColor(.primary)
        }
        .background(.regularMaterial)
        .cornerRadius(.infinity)
    }
}
