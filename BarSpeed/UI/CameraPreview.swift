import SwiftUI
import AVFoundation

/// 相机预览 + 点击取点（返回设备归一化坐标 0...1）
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.onTap = onTap
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onTap = onTap
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var onTap: ((CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            let g = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            addGestureRecognizer(g)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let conn = previewLayer.connection, conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }
        }

        @objc private func handleTap(_ g: UITapGestureRecognizer) {
            let p = g.location(in: self)
            let device = previewLayer.captureDevicePointConverted(fromLayerPoint: p)
            onTap?(device)
        }
    }
}
