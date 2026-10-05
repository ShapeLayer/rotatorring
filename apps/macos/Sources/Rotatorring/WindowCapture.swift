import CoreMedia
import CoreVideo
import IOSurface
import ScreenCaptureKit

/// Streams a single window's contents via ScreenCaptureKit.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    /// Called on the main queue with each new frame.
    var onFrame: ((IOSurface) -> Void)?
    /// Called on the main queue when the stream stops unexpectedly.
    var onStop: ((Error?) -> Void)?

    private(set) var pointPixelScale: CGFloat = 2
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "rotatorring.capture", qos: .userInteractive)

    func start(window: SCWindow) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        pointPixelScale = CGFloat(filter.pointPixelScale)
        let stream = SCStream(filter: filter, configuration: configuration(for: window.frame.size), delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    /// Match the output resolution to the source window's new size (in points).
    func update(pointSize: CGSize) {
        stream?.updateConfiguration(configuration(for: pointSize)) { _ in }
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        stream.stopCapture { _ in }
    }

    private func configuration(for pointSize: CGSize) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = max(1, Int((pointSize.width * pointPixelScale).rounded()))
        config.height = max(1, Int((pointSize.height * pointPixelScale).rounded()))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.preservesAspectRatio = true
        return config
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusRaw) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        let surface = unsafeBitCast(surfaceRef, to: IOSurface.self)
        DispatchQueue.main.async { [weak self] in self?.onFrame?(surface) }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.stream = nil
            self?.onStop?(error)
        }
    }
}

/// Current on-screen bounds (points, top-left origin) of a window, or nil if it no longer exists.
func currentBounds(ofWindow id: CGWindowID) -> CGRect? {
    guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
          let entry = info.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == id }),
          let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary
    else { return nil }
    return CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
}
