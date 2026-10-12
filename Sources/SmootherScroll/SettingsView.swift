import AppKit
import ScrollCore
import SwiftUI
import UniformTypeIdentifiers

/// The settings panel that drops down from the menu bar item.
struct SettingsView: View {
    static let size = NSSize(width: 420, height: 640)

    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Header(model: model)
            }

            if !model.hasAccess {
                AccessSection(model: model)
            }

            Section {
                ValueSlider("Distance per notch", value: $model.settings.stepSize, in: ScrollSettings.ranges.stepSize, step: 10) {
                    "\(Int($0)) pt"
                }
                ValueSlider("Duration per notch", value: $model.settings.animationTime, in: ScrollSettings.ranges.animationTime, step: 10) {
                    "\(Int($0)) ms"
                }
                ValueSlider("Speed up fast spins", value: $model.settings.acceleration, in: ScrollSettings.ranges.acceleration, step: 0.1) {
                    level($0, ["Gentle": 0, "Normal": 0.75, "Strong": 1.25, "Max": 1.75])
                }
                ValueStepper("Fastest speed-up", value: $model.settings.accelerationMax, in: ScrollSettings.ranges.accelerationMax, step: 1)
                Toggle("Ease in and out", isOn: $model.settings.easing)
                if model.settings.easing {
                    ValueStepper("Ease-out length", value: $model.settings.tailToHeadRatio, in: ScrollSettings.ranges.tailToHeadRatio, step: 0.5)
                }
                Toggle("Smooth sideways scrolling", isOn: $model.settings.smoothHorizontal)
                Toggle("Reverse wheel direction", isOn: $model.settings.reverseDirection)
            } header: {
                Text("Scrolling")
            } footer: {
                Text("A notch at a time moves exactly its distance; spin faster and each goes further. Shift scrolls sideways. With ⌘, ⌥ or ⌃ held, the app gets the wheel as usual.")
                    .settingsFooter()
            }

            Section {
                FeelChart(settings: model.settings)
                ValueSlider("Glide after fast spins", value: $model.settings.momentum, in: ScrollSettings.ranges.momentum, step: 0.05) {
                    level($0, ["Short": 0, "Medium": 0.3, "Long": 0.7])
                }
                Toggle(isOn: $model.settings.trackpadPhases) {
                    Text("Bounce at page ends")
                    Text("Scrolling past the top or bottom stretches the page, then it springs back.")
                }
            } header: {
                Text("Like a Trackpad")
            } footer: {
                Text("Both off by default. The curve shows how fast a page moves after one notch and after a fast spin.")
                    .settingsFooter()
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let error = model.loginItemError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            ExcludedAppsSection(model: model)

            UpdateSection(model: model)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// The name of the highest level `value` reaches, by where each level starts.
    private func level(_ value: Double, _ levels: KeyValuePairs<String, Double>) -> String {
        guard value > 0 else { return "Off" }
        return levels.last { value >= $0.value }?.key ?? "Off"
    }
}

private struct Header: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Smoother Scroll")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 7, height: 7)
                    Text(status.text)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("Smooth scrolling", isOn: $model.settings.enabled)
                .labelsHidden()
                .disabled(!model.hasAccess)
        }
        .padding(.vertical, 2)
    }

    private var status: (text: String, color: Color) {
        guard model.hasAccess else { return ("Needs Accessibility access", .orange) }
        guard model.settings.enabled else { return ("Paused", .secondary) }
        return ("Smoothing your mouse wheel", .green)
    }
}

private struct UpdateSection: View {
    let model: AppModel

    var body: some View {
        let updater = model.updater
        Section {
            if let update = updater.available {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smoother Scroll \(update.version) is available")
                            Text("You have \(Updater.currentVersion). It restarts once installed.")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    if updater.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Install and Restart") {
                        Task { await updater.install() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(updater.isInstalling)
                }
            }
            HStack {
                Text("Version \(Updater.currentVersion)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check for Updates") {
                    Task { await updater.check() }
                }
                .disabled(updater.isChecking || updater.isInstalling)
            }
            HStack {
                Button("Restore Defaults") { model.restoreDefaults() }
                Spacer()
                Button("Quit Smoother Scroll") { NSApp.terminate(nil) }
            }
        }
    }
}

private struct AccessSection: View {
    let model: AppModel

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Accessibility access")
                    Text("Smoother Scroll needs it to smooth your wheel. If it is already in the list, remove it with − and add it again.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Open System Settings") { model.requestAccess() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// How fast the page moves after one notch and after a fast spin, with the settings as they are.
private struct FeelChart: View {
    let settings: ScrollSettings

    private static let duration = 2.4

    var body: some View {
        let tuning = ScrollTuning(settings)
        let notch = Self.speeds(notches: [0.05], tuning: tuning)
        let spin = Self.speeds(notches: (0..<8).map { 0.05 + Double($0) / 15 }, tuning: tuning)

        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                Curve(values: spin, closed: true)
                    .fill(LinearGradient(colors: [.purple.opacity(0.25), .purple.opacity(0)], startPoint: .top, endPoint: .bottom))
                Curve(values: spin, closed: false)
                    .stroke(.purple, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Curve(values: notch, closed: true)
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0)], startPoint: .top, endPoint: .bottom))
                Curve(values: notch, closed: false)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Divider()
            }
            .frame(height: 84)
            HStack(spacing: 14) {
                Legend(color: .accentColor, text: "One notch")
                Legend(color: .purple, text: "Fast spin")
                Spacer()
                Text("2 seconds")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    /// Each curve is scaled to its own peak: the shapes are what matter, not the distances.
    private static func speeds(notches: [Double], tuning: ScrollTuning) -> [Double] {
        let frame = 1.0 / 120
        var animator = ScrollAnimator()
        var next = 0
        var deltas: [Double] = []
        for index in 0..<Int(duration / frame) {
            let time = Double(index) * frame
            while next < notches.count, notches[next] <= time {
                animator.notch(dx: 0, dy: 1, at: notches[next], tuning: tuning)
                next += 1
            }
            let moved = animator.advance(to: time, tuning: tuning).reduce(0) { $0 + Double($1.dy) }
            deltas.append(moved)
        }
        let smoothed = deltas.indices.map { index in
            let window = deltas[max(0, index - 5)...min(deltas.count - 1, index + 5)]
            return window.reduce(0, +) / Double(window.count)
        }
        let peak = max(smoothed.max() ?? 1, 0.001)
        return smoothed.map { $0 / peak }
    }
}

private struct Curve: Shape {
    let values: [Double]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            let step = rect.width / CGFloat(values.count - 1)
            let point = { (index: Int) in
                CGPoint(x: rect.minX + CGFloat(index) * step, y: rect.maxY - CGFloat(values[index]) * rect.height * 0.92)
            }
            path.move(to: closed ? CGPoint(x: rect.minX, y: rect.maxY) : point(0))
            for index in values.indices {
                path.addLine(to: point(index))
            }
            guard closed else { return }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct Legend: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 12, height: 3)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ExcludedAppsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            if model.settings.excludedApps.isEmpty {
                Text("Smooth in every app")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.settings.excludedApps) { app in
                HStack(spacing: 8) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(app.name)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle.fill") {
                        model.include(app.bundleID)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Smooth scrolling in \(app.name) again")
                }
            }
            HStack {
                Spacer()
                Menu("Add App…") {
                    ForEach(runningApps(), id: \.bundleID) { app in
                        Button {
                            model.exclude(app)
                        } label: {
                            Label { Text(app.name) } icon: { Image(nsImage: menuIcon(app.icon)) }
                        }
                    }
                    Divider()
                    Button("Choose…", action: chooseApp)
                }
                .fixedSize()
            }
        } header: {
            Text("Disabled Apps")
        } footer: {
            Text("The wheel scrolls as it would without Smoother Scroll in these apps.")
                .settingsFooter()
        }
    }

    private func runningApps() -> [ExcludedApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap(ExcludedApp.init)
            .filter { !model.isExcluded($0.bundleID) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func menuIcon(_ icon: NSImage) -> NSImage {
        let sized = icon.copy() as? NSImage ?? icon
        sized.size = NSSize(width: 16, height: 16)
        return sized
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Disable"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let app = ExcludedApp(url: url) else { continue }
            model.exclude(app)
        }
    }
}

private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, format: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                    .labelsHidden()
                    .frame(width: 130)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }
}

private struct ValueStepper: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("\(value.formatted(.number.precision(.fractionLength(0...1))))×")
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

private extension Text {
    func settingsFooter() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
