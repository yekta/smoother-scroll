import AppKit
import ScrollCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            if !model.hasAccess {
                AccessSection(model: model)
            }

            Section {
                Toggle("Smooth scrolling", isOn: $model.settings.enabled)
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let error = model.loginItemError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Toggle("Show in menu bar", isOn: $model.showsMenuBarIcon)
            } footer: {
                if !model.showsMenuBarIcon {
                    Text("Open Smoother Scroll again to come back to these settings.")
                        .settingsFooter()
                }
            }

            Section {
                ValueSlider("Step size", value: $model.settings.stepSize, in: ScrollSettings.ranges.stepSize, step: 10) {
                    "\(Int($0)) px"
                }
                ValueSlider("Animation time", value: $model.settings.animationTime, in: ScrollSettings.ranges.animationTime, step: 10) {
                    "\(Int($0)) ms"
                }
                ValueSlider("Acceleration", value: $model.settings.acceleration, in: ScrollSettings.ranges.acceleration, step: 0.1) {
                    level($0, ["Low": 0, "Medium": 0.6, "High": 1.4, "Very high": 2.2])
                }
                ValueSlider("Momentum", value: $model.settings.momentum, in: ScrollSettings.ranges.momentum, step: 0.05) {
                    level($0, ["Short": 0, "Medium": 0.3, "Long": 0.7])
                }
            } header: {
                Text("Scrolling")
            } footer: {
                Text("Acceleration covers more ground when the wheel spins fast. Momentum lets a fast spin glide on after the wheel stops, like a flick on a trackpad.")
                    .settingsFooter()
            }

            Section {
                Toggle(isOn: $model.settings.trackpadPhases) {
                    Text("Behave like a trackpad")
                    Text("Pages stretch at their edges and spring back, and apps see a trackpad's gestures.")
                }
                Toggle("Smooth horizontal scrolling", isOn: $model.settings.smoothHorizontal)
                Toggle("Reverse wheel direction", isOn: $model.settings.reverseDirection)
            } footer: {
                Text("Hold Shift to scroll sideways. Scrolling with ⌘, ⌥ or ⌃ held is left to the app, for zooming.")
                    .settingsFooter()
            }

            Section("Advanced") {
                NumberStepper("Tail to head ratio", value: $model.settings.tailToHeadRatio, in: ScrollSettings.ranges.tailToHeadRatio, step: 0.5, suffix: "×")
                NumberStepper("Maximum acceleration", value: $model.settings.maxAcceleration, in: ScrollSettings.ranges.maxAcceleration, step: 1, suffix: "×")
            }

            ExcludedAppsSection(model: model)

            Section {
                HStack {
                    Text("Version \(UpdateChecker.currentVersion)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { model.restoreDefaults() }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The name of the highest level `value` reaches, by where each level starts.
    private func level(_ value: Double, _ levels: KeyValuePairs<String, Double>) -> String {
        guard value > 0 else { return "Off" }
        return levels.last { value >= $0.value }?.key ?? "Off"
    }
}

private struct AccessSection: View {
    let model: AppModel

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Accessibility access")
                        .font(.headline)
                    Text("Smoother Scroll needs it to smooth the wheel's scrolling. Turn it on in System Settings → Privacy & Security → Accessibility. If Smoother Scroll is already listed there, remove it with − and add it again.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            HStack {
                Spacer()
                Button("Open System Settings") { model.requestAccess() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct ExcludedAppsSection: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            if model.settings.excludedApps.isEmpty {
                Text("No apps")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.settings.excludedApps) { app in
                HStack(spacing: 8) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(app.name)
                    Spacer()
                    Button {
                        model.include(app.bundleID)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Smooth scrolling in \(app.name) again")
                }
            }
            HStack {
                Spacer()
                Menu("Add App") {
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
                .menuStyle(.button)
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
            HStack(spacing: 10) {
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                    .labelsHidden()
                    .frame(width: 180)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}

private struct NumberStepper: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, suffix: String) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.suffix = suffix
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .onSubmit { value = min(max(value, range.lowerBound), range.upperBound) }
                Text(suffix)
                    .foregroundStyle(.secondary)
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
