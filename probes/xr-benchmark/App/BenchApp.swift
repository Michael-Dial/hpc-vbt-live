import AVFoundation
import AprilTag
import Combine
import SwiftUI

@main
struct BenchApp: App {
    var body: some Scene {
        WindowGroup { BenchView() }
    }
}

struct PreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class Layered: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> Layered {
        let view = Layered()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: Layered, context: Context) {
        if let connection = view.preview.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

struct BenchView: View {
    @State private var controller = CaptureController()
    @State private var config = BenchConfig()
    @State private var running = false
    @State private var found = false
    @State private var readout = "Aim at the tag, then press Start."
    @State private var message = ""
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            PreviewView(session: controller.session)
                .frame(maxWidth: .infinity).frame(height: 300)
                .background(.black)
                .overlay(alignment: .topLeading) {
                    Text(found ? "TAG FOUND" : "NO TAG")
                        .font(.headline).padding(6)
                        .background(found ? .green : .red).foregroundStyle(.white)
                        .opacity(running ? 1 : 0)
                }
            Text(readout)
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.orange) }
            Spacer(minLength: 0)
            Group {
                Picker("Tag", selection: $config.family) {
                    Text("36h11").tag(TagFamily.tag36h11)
                    Text("41h12").tag(TagFamily.tagStandard41h12)
                }
                Picker("Capture", selection: $config.fps) {
                    Text("60 fps").tag(60); Text("120 fps").tag(120); Text("240 fps").tag(240)
                }
                Picker("Detect", selection: $config.detectEvery) {
                    Text("every frame").tag(1); Text("every 2nd").tag(2)
                }
            }
            .pickerStyle(.segmented).disabled(running)
            Toggle("Record video", isOn: $config.record).disabled(running)
            Button(running ? "Stop and save" : "Start") { running ? stop() : start() }
                .font(.title3.bold()).frame(maxWidth: .infinity).padding(10)
                .background(running ? .red : .blue).foregroundStyle(.white).clipShape(.rect(cornerRadius: 10))
        }
        .padding(12)
        .onReceive(tick) { _ in
            guard running else { return }
            controller.stats.noteDeviceState()
            let screen = controller.stats.screen(fileBytes: CaptureController.size(controller.movieURL))
            found = screen.found
            readout = screen.text
        }
    }

    private func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                do {
                    guard granted else { throw BenchError.cameraDenied }
                    UIDevice.current.isBatteryMonitoringEnabled = true
                    try controller.start(config)
                    UIApplication.shared.isIdleTimerDisabled = true
                    running = true
                    message = controller.stats.formatLine
                } catch {
                    message = error.localizedDescription
                }
            }
        }
    }

    private func stop() {
        running = false
        UIApplication.shared.isIdleTimerDisabled = false
        message = "Saving..."
        controller.stop { folder in
            message = "Saved \(folder?.lastPathComponent ?? "nothing"). Open the Files app > On My iPhone > XR Bench."
        }
    }
}
