import AVFoundation
import Combine
import RoughReps
import SwiftUI

@main
struct BenchApp: App {
    var body: some Scene {
        WindowGroup { StationView() }
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

struct StationView: View {
    @StateObject private var model = SessionModel()
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !model.sessionRunning {
                StartView(model: model)
            } else if model.setOpen {
                SetOpenView(model: model)
            } else {
                BetweenSetsView(model: model)
            }
        }
        .onReceive(tick) { _ in model.refresh() }
    }
}

struct StartView: View {
    @ObservedObject var model: SessionModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Station prototype").font(.largeTitle.bold())
            Text("Prop the phone about 2 m from the bar end, looking along the bar, plugged in. "
                 + "Starting a Session starts the Recording; Sets are marked inside it.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Rep rules are provisional (\(RoughRepLogic.version)).").font(.footnote).foregroundStyle(.secondary)
            if !model.message.isEmpty { Text(model.message).foregroundStyle(.orange) }
            Spacer()
            BigButton(title: "Start Session", color: .blue) { model.startSession() }
        }
        .padding(20)
    }
}

struct BetweenSetsView: View {
    @ObservedObject var model: SessionModel
    @State private var confirmEnd = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                PreviewView(session: model.controller.session)
                    .frame(height: 200).frame(maxWidth: .infinity).background(.black)
                    .overlay(alignment: .topLeading) { TagBadge(found: model.tagFound) }
                    .overlay(alignment: .bottomTrailing) {
                        Text(String(format: "height %+.0f cm", model.heightChange * 100))
                            .font(.caption.monospaced()).padding(4).background(.black.opacity(0.6)).foregroundStyle(.white)
                    }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Lift.allCases) { lift in
                        Button(lift.rawValue) { model.lift = lift }
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(model.lift == lift ? Color.blue : Color.gray.opacity(0.25))
                            .foregroundStyle(model.lift == lift ? .white : .primary)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                }

                HStack(spacing: 6) {
                    let steps: [Double] = model.useKilograms ? [5, 2.5] : [10, 5]
                    StepButton(label: "-\(steps[0].formatted())") { model.load = max(0, model.load - steps[0]) }
                    StepButton(label: "-\(steps[1].formatted())") { model.load = max(0, model.load - steps[1]) }
                    Text("\(model.load.formatted()) \(model.unit)")
                        .font(.title.bold().monospacedDigit()).frame(maxWidth: .infinity)
                    StepButton(label: "+\(steps[1].formatted())") { model.load += steps[1] }
                    StepButton(label: "+\(steps[0].formatted())") { model.load += steps[0] }
                }

                HStack {
                    Picker("Participant", selection: $model.participant) {
                        ForEach(model.participants, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Toggle("kg", isOn: $model.useKilograms).fixedSize()
                    Toggle("Speak", isOn: $model.speakVelocity).fixedSize()
                }

                BigButton(title: "Start Set", color: .green) { model.startSet() }
                if !model.tagFound {
                    Text("No tag in view. A Set can start, but nothing is measured until the tag is found.")
                        .font(.footnote).foregroundStyle(.orange)
                }

                ForEach(model.closedSets.reversed()) { set in
                    Text(set.summary).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                }

                DisclosureGroup("Diagnostics") {
                    Text(model.diagnostics).font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("End Session", role: .destructive) { confirmEnd = true }
                    .padding(.top, 8)
                    .confirmationDialog("End the Session and save the Recording?", isPresented: $confirmEnd,
                                        titleVisibility: .visible) {
                        Button("End Session", role: .destructive) { model.endSession() }
                    }
            }
            .padding(12)
        }
    }
}

/// Meant to be read from 2 to 3 m away.
struct SetOpenView: View {
    @ObservedObject var model: SessionModel

    var body: some View {
        VStack(spacing: 4) {
            Text("\(model.lift.rawValue)  \(model.load.formatted()) \(model.unit)  \(model.participant)")
                .font(.headline).foregroundStyle(.white.opacity(0.8))
            if !model.tagFound {
                Text("TAG LOST").font(.system(size: 44, weight: .heavy)).foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            Text(model.reps.last.map { String(format: "%.2f", $0.meanVelocity) } ?? "--")
                .font(.system(size: 170, weight: .heavy).monospacedDigit())
                .minimumScaleFactor(0.4).lineLimit(1).foregroundStyle(.white)
            Text("m/s, last Rep").font(.title3).foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                VStack {
                    Text("\(model.reps.count)").font(.system(size: 90, weight: .bold).monospacedDigit())
                    Text("Reps")
                }
                VStack {
                    Text(model.velocityLoss.map { String(format: "%.0f%%", $0) } ?? "--")
                        .font(.system(size: 90, weight: .bold).monospacedDigit()).minimumScaleFactor(0.5).lineLimit(1)
                    Text("loss from best")
                }
            }
            .foregroundStyle(.white)
            Text(model.reps.suffix(6).map { String(format: "%.2f", $0.meanVelocity) }.joined(separator: "  "))
                .font(.title3.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 0)
            if !model.reps.isEmpty, model.stillFor > 2 {
                Text(String(format: "Set ends in %.0f s", max(0, SessionModel.stillSecondsToEndSet - model.stillFor)))
                    .foregroundStyle(.white.opacity(0.8))
            }
            BigButton(title: "End Set", color: .white.opacity(0.25)) { model.endSet(automatic: false) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.tagFound ? Color.black : Color.red)
    }
}

struct TagBadge: View {
    let found: Bool
    var body: some View {
        Text(found ? "TAG FOUND" : "NO TAG").font(.headline).padding(6)
            .background(found ? .green : .red).foregroundStyle(.white)
    }
}

struct StepButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(label, action: action)
            .font(.headline.monospacedDigit()).frame(width: 54, height: 48)
            .background(Color.gray.opacity(0.25)).clipShape(.rect(cornerRadius: 10))
    }
}

struct BigButton: View {
    let title: String
    let color: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.title.bold()).frame(maxWidth: .infinity).padding(.vertical, 18)
        }
        .background(color).foregroundStyle(.white).clipShape(.rect(cornerRadius: 14))
    }
}
