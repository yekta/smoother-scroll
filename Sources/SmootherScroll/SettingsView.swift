import AppKit
import ScrollCore
import SwiftUI
import UniformTypeIdentifiers

enum Palette {
    static let accent = Color(red: 0.24, green: 0.52, blue: 1.0)
    static let violet = Color(red: 0.58, green: 0.36, blue: 1.0)
    static let teal = Color(red: 0.16, green: 0.74, blue: 0.78)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.2)
    static let pink = Color(red: 1.0, green: 0.33, blue: 0.52)
    static let green = Color(red: 0.2, green: 0.78, blue: 0.42)
    static let graphite = Color(red: 0.45, green: 0.47, blue: 0.52)
}

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Header(model: model)

                if !model.hasAccess {
                    AccessCard(model: model)
                }

                FeelCard(settings: model.settings)

                Group {
                    CardSection("Scrolling") {
                        SliderRow("Step size", symbol: "arrow.up.and.down", color: Palette.accent,
                                  value: $model.settings.stepSize, in: ScrollSettings.ranges.stepSize, step: 10) {
                            "\(Int($0)) px"
                        }
                        RowDivider()
                        SliderRow("Animation time", symbol: "timer", color: Palette.violet,
                                  value: $model.settings.animationTime, in: ScrollSettings.ranges.animationTime, step: 10) {
                            "\(Int($0)) ms"
                        }
                        RowDivider()
                        SliderRow("Acceleration", symbol: "hare.fill", color: Palette.orange,
                                  value: $model.settings.acceleration, in: ScrollSettings.ranges.acceleration, step: 0.1) {
                            level($0, ["Low": 0, "Medium": 0.6, "High": 1.4, "Very high": 2.2])
                        }
                        RowDivider()
                        SliderRow("Momentum", symbol: "wind", color: Palette.teal,
                                  value: $model.settings.momentum, in: ScrollSettings.ranges.momentum, step: 0.05) {
                            level($0, ["Short": 0, "Medium": 0.3, "Long": 0.7])
                        }
                    }

                    CardSection("Behavior") {
                        ToggleRow("Behave like a trackpad", symbol: "hand.point.up.left.fill", color: Palette.pink,
                                  detail: "Pages stretch at their edges and spring back.",
                                  isOn: $model.settings.trackpadPhases)
                        RowDivider()
                        ToggleRow("Smooth horizontal scrolling", symbol: "arrow.left.and.right", color: Palette.accent,
                                  detail: "Hold Shift to scroll sideways.",
                                  isOn: $model.settings.smoothHorizontal)
                        RowDivider()
                        ToggleRow("Reverse wheel direction", symbol: "arrow.up.arrow.down", color: Palette.graphite,
                                  isOn: $model.settings.reverseDirection)
                    }

                    CardSection("General") {
                        ToggleRow("Launch at login", symbol: "power", color: Palette.green,
                                  detail: model.loginItemError,
                                  isOn: Binding(get: { model.launchesAtLogin }, set: { model.setLaunchAtLogin($0) }))
                        RowDivider()
                        ToggleRow("Show in menu bar", symbol: "menubar.rectangle", color: Palette.graphite,
                                  detail: model.showsMenuBarIcon ? nil : "Open Smoother Scroll again to come back here.",
                                  isOn: $model.showsMenuBarIcon)
                    }

                    CardSection("Advanced") {
                        StepperRow("Tail to head ratio", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill",
                                   color: Palette.violet, value: $model.settings.tailToHeadRatio,
                                   in: ScrollSettings.ranges.tailToHeadRatio, step: 0.5)
                        RowDivider()
                        StepperRow("Maximum acceleration", symbol: "gauge.with.dots.needle.67percent",
                                   color: Palette.orange, value: $model.settings.maxAcceleration,
                                   in: ScrollSettings.ranges.maxAcceleration, step: 1)
                    }

                    AppsCard(model: model)
                }

                Footer(model: model)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.never)
        .background { Backdrop() }
        .overlay {
            // The backdrop again over the title bar, fading out, so what scrolls under it frosts.
            Backdrop()
                .mask {
                    VStack(spacing: 0) {
                        Color.black.frame(height: 22)
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 26)
                        Spacer()
                    }
                    .ignoresSafeArea()
                }
                .allowsHitTesting(false)
        }
    }

    /// The name of the highest level `value` reaches, by where each level starts.
    private func level(_ value: Double, _ levels: KeyValuePairs<String, Double>) -> String {
        guard value > 0 else { return "Off" }
        return levels.last { value >= $0.value }?.key ?? "Off"
    }
}

// MARK: Header and footer

private struct Header: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text("Smoother Scroll")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 7, height: 7)
                        .shadow(color: status.color.opacity(0.8), radius: 3)
                    Text(status.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("Smooth scrolling", isOn: $model.settings.enabled)
                .toggleStyle(.switch)
                .controlSize(.large)
                .labelsHidden()
                .disabled(!model.hasAccess)
        }
    }

    private var status: (text: String, color: Color) {
        guard model.hasAccess else { return ("Needs Accessibility access", Palette.orange) }
        guard model.settings.enabled else { return ("Paused", Palette.graphite) }
        return ("Smoothing your mouse wheel", Palette.green)
    }
}

private struct Footer: View {
    let model: AppModel

    var body: some View {
        HStack {
            Text("Version \(UpdateChecker.currentVersion)")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Check for Updates") {
                Task { await UpdateChecker.check() }
            }
            .glassButton()
            Button("Restore Defaults") { model.restoreDefaults() }
                .glassButton()
        }
        .padding(.horizontal, 4)
    }
}

private struct AccessCard: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: "hand.raised.fill", color: Palette.orange, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Accessibility access")
                        .font(.headline)
                    Text("Smoother Scroll needs it to smooth your wheel. If it is already in the list, remove it with − and add it again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Open System Settings") { model.requestAccess() }
                    .glassButton(prominent: true)
            }
        }
        .padding(16)
        .glassCard(tint: Palette.orange.opacity(0.18))
    }
}

// MARK: The curve

/// How fast the page moves after one notch and after a fast spin, with the settings as they are.
private struct FeelCard: View {
    let settings: ScrollSettings

    private static let duration = 2.4

    var body: some View {
        let tuning = ScrollTuning(settings)
        let notch = Self.speeds(notches: [0.05], tuning: tuning)
        let spin = Self.speeds(notches: (0..<8).map { 0.05 + Double($0) / 15 }, tuning: tuning)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Feel")
                    .font(.headline)
                Spacer()
                Legend(color: Palette.accent, text: "One notch")
                Legend(color: Palette.violet, text: "Fast spin")
            }
            ZStack {
                Curve(values: spin, closed: true)
                    .fill(LinearGradient(colors: [Palette.violet.opacity(0.45), Palette.violet.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                Curve(values: spin, closed: false)
                    .stroke(Palette.violet, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Curve(values: notch, closed: true)
                    .fill(LinearGradient(colors: [Palette.accent.opacity(0.4), Palette.accent.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                Curve(values: notch, closed: false)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 96)
            HStack {
                Text("0 s")
                Spacer()
                Text("1 s")
                Spacer()
                Text("2 s")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(16)
        .glassCard()
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
                .frame(width: 10, height: 4)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }
}

// MARK: Apps

private struct AppsCard: View {
    @Bindable var model: AppModel

    var body: some View {
        CardSection("Disabled Apps") {
            if model.settings.excludedApps.isEmpty {
                HStack(spacing: 12) {
                    IconTile(symbol: "checkmark", color: Palette.green)
                    Text("Smooth in every app")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            ForEach(model.settings.excludedApps) { app in
                if app.id != model.settings.excludedApps.first?.id {
                    RowDivider()
                }
                HStack(spacing: 12) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 26, height: 26)
                    Text(app.name)
                    Spacer()
                    Button {
                        model.include(app.bundleID)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Smooth scrolling in \(app.name) again")
                }
            }
        } accessory: {
            Menu {
                ForEach(runningApps(), id: \.bundleID) { app in
                    Button {
                        model.exclude(app)
                    } label: {
                        Label { Text(app.name) } icon: { Image(nsImage: menuIcon(app.icon)) }
                    }
                }
                Divider()
                Button("Choose…", action: chooseApp)
            } label: {
                Label("Add", systemImage: "plus")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .glassButton()
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

// MARK: Building blocks

private struct CardSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let accessory: Accessory

    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                accessory
            }
            .padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCard()
        }
    }
}

private extension CardSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, content: content, accessory: { EmptyView() })
    }
}

private struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: color.opacity(0.35), radius: 4, y: 2)
    }
}

private struct RowDivider: View {
    var body: some View {
        Divider()
            .opacity(0.5)
            .padding(.leading, 38)
    }
}

private struct RowLabel: View {
    let title: String
    let symbol: String
    let color: Color
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let symbol: String
    let color: Color
    let detail: String?
    @Binding var isOn: Bool

    init(_ title: String, symbol: String, color: Color, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.symbol = symbol
        self.color = color
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        HStack {
            RowLabel(title: title, symbol: symbol, color: color, detail: detail)
            Spacer()
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 6)
    }
}

private struct SliderRow: View {
    let title: String
    let symbol: String
    let color: Color
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    init(_ title: String, symbol: String, color: Color, value: Binding<Double>, in range: ClosedRange<Double>,
         step: Double, format: @escaping (Double) -> String) {
        self.title = title
        self.symbol = symbol
        self.color = color
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                RowLabel(title: title, symbol: symbol, color: color)
                Spacer()
                Text(format(value))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
            }
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                .labelsHidden()
                .tint(color)
                .padding(.leading, 38)
        }
        .padding(.vertical, 6)
    }
}

private struct StepperRow: View {
    let title: String
    let symbol: String
    let color: Color
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    init(_ title: String, symbol: String, color: Color, value: Binding<Double>, in range: ClosedRange<Double>, step: Double) {
        self.title = title
        self.symbol = symbol
        self.color = color
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        HStack {
            RowLabel(title: title, symbol: symbol, color: color)
            Spacer()
            Text("\(value.formatted(.number.precision(.fractionLength(0...1))))×")
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(color)
            Stepper(title, value: $value, in: range, step: step)
                .labelsHidden()
        }
        .padding(.vertical, 6)
    }
}

/// Soft colour behind the glass, so it has something to refract.
private struct Glow: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            blob(Palette.accent, size: 360, x: -150, y: -200, alignment: .top)
            blob(Palette.violet, size: 320, x: 170, y: -140, alignment: .top)
            blob(Palette.teal, size: 300, x: -170, y: 120, alignment: .bottom)
            blob(Palette.pink, size: 260, x: 180, y: 160, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .blur(radius: 110)
        .opacity(colorScheme == .dark ? 0.5 : 0.3)
        .allowsHitTesting(false)
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat, alignment: Alignment) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(x: x, y: y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// The desktop behind the window, blurred, with colour in it.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            WindowBlur()
            Glow()
        }
        .ignoresSafeArea()
    }
}

/// The desktop behind the window, blurred.
private struct WindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private extension View {
    @ViewBuilder
    func glassCard(tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .background(tint ?? .clear, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.12)))
        }
    }

    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
