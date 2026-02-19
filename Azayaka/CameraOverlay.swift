//
//  CameraOverlay.swift
//  Azayaka
//
//  Floating circular camera preview overlay (Loom-style).
//  Uses a non-activating NSPanel so it doesn't steal focus.
//  Captured as part of the screen recording (not excluded).
//

import AVFoundation
import Cocoa


class CameraOverlay: NSPanel {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var circleView: NSView!
    private var initialLocation: NSPoint?

    init(size: CGFloat = 150) {
        let frame = NSRect(x: 100, y: 100, width: size, height: size)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenNone]
        if #available(macOS 13.0, *) {
            collectionBehavior.insert(.auxiliary)
        }

        circleView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        circleView.wantsLayer = true
        circleView.layer?.cornerRadius = size / 2
        circleView.layer?.masksToBounds = true
        circleView.layer?.borderWidth = 2
        circleView.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        contentView = circleView
    }

    func startCamera(deviceID: String? = nil) {
        stopCamera()

        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.setupCaptureSession(deviceID: deviceID) }
                }
            }
            return
        case .denied, .restricted:
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Azayaka needs camera permissions!".local
                alert.informativeText = "Azayaka needs permission to access your camera for the overlay.".local
                alert.addButton(withTitle: "Open Settings".local)
                alert.addButton(withTitle: "No thanks".local)
                alert.alertStyle = .warning
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
            }
            return
        case .authorized:
            setupCaptureSession(deviceID: deviceID)
        @unknown default:
            return
        }
    }

    private func setupCaptureSession(deviceID: String? = nil) {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .medium

        let device: AVCaptureDevice?
        if let deviceID, !deviceID.isEmpty,
           let specific = AVCaptureDevice(uniqueID: deviceID) {
            device = specific
        } else {
            device = AVCaptureDevice.default(for: .video)
        }

        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return }
        guard captureSession?.canAddInput(input) == true else { return }
        captureSession?.addInput(input)

        let preview = AVCaptureVideoPreviewLayer(session: captureSession!)
        preview.videoGravity = .resizeAspectFill
        preview.frame = circleView.bounds
        preview.cornerRadius = circleView.bounds.width / 2
        preview.masksToBounds = true
        circleView.layer?.addSublayer(preview)
        previewLayer = preview

        captureSession?.startRunning()
    }

    func stopCamera() {
        captureSession?.stopRunning()
        captureSession = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    func updateSize(_ size: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let origin = frame.origin
        setFrame(NSRect(x: origin.x, y: origin.y, width: size, height: size), display: true)
        circleView.frame = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        circleView.layer?.cornerRadius = size / 2
        previewLayer?.frame = circleView.bounds
        previewLayer?.cornerRadius = size / 2
        CATransaction.commit()
    }

    // MARK: - Dragging

    override func mouseDown(with event: NSEvent) {
        initialLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let initialLocation else { return }
        let screenLocation = event.locationInWindow
        let origin = frame.origin
        let newOrigin = NSPoint(
            x: origin.x + (screenLocation.x - initialLocation.x),
            y: origin.y + (screenLocation.y - initialLocation.y)
        )
        setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        initialLocation = nil
    }

    deinit {
        stopCamera()
    }
}
