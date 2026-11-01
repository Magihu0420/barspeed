import AVFoundation
import Foundation

/// 采集相机帧，逐帧回调。画面不出设备。
final class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "barspeed.camera")
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back

    /// 每帧回调（后台队列）
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    /// 录像回调
    var onRecordedFrame: ((CVPixelBuffer, CMTime) -> Void)?

    @Published private(set) var authorized = false

    private(set) var videoSize: CGSize = CGSize(width: 1920, height: 1080)

    func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
            return true
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            authorized = ok
            return ok
        default:
            authorized = false
            return false
        }
    }

    /// 必须在后台队列调用，耗时数百毫秒
    func configure(position: AVCaptureDevice.Position = .back) {
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1920x1080

            if let old = self.input { self.session.removeInput(old) }

            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video)
            if let device, let newInput = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.input = newInput
                self.currentPosition = position
                try? device.lockForConfiguration()
                // 60fps：提升测速精度
                if let range = device.activeFormat.videoSupportedFrameRateRanges.first(where: { $0.maxFrameRate >= 60 }) {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                    _ = range
                }
                device.unlockForConfiguration()
            }

            self.output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            self.output.alwaysDiscardsLateVideoFrames = true
            self.output.setSampleBufferDelegate(self, queue: self.queue)
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
                self.output.connection(with: .video)?.videoRotationAngle = 90
            }
            self.session.commitConfiguration()
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func flip() {
        let next: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        configure(position: next)
    }

    func setTorch(_ on: Bool) {
        guard let device = input?.device, device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrame?(pb, t)
        onRecordedFrame?(pb, t)
    }
}
