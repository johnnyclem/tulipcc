import SwiftUI

/// Visual recreation of a Roland JU-06A / Juno-style front panel.
struct JunoPanelView: View {
    @ObservedObject var midi: AMYboardMIDI
    @Binding var address: JunoMemoryAddress

    // Cosmetic slider positions (0…1) — filter/level also tweak live sound.
    @State private var lfoRate: Double = 0.3
    @State private var lfoDelay: Double = 0.2
    @State private var dcoLfo: Double = 0.1
    @State private var dcoPwm: Double = 0.4
    @State private var dcoSub: Double = 0.5
    @State private var dcoNoise: Double = 0.0
    @State private var vcfFreq: Double = 0.7
    @State private var vcfRes: Double = 0.25
    @State private var vcfEnv: Double = 0.45
    @State private var vcfLfo: Double = 0.1
    @State private var vcfKybd: Double = 0.5
    @State private var vcaLevel: Double = 0.85
    @State private var envA: Double = 0.05
    @State private var envD: Double = 0.35
    @State private var envS: Double = 0.7
    @State private var envR: Double = 0.3
    @State private var chorus: Int = 1 // 0 off, 1=I, 2=II
    @State private var rangeStop: Int = 1 // 0=16', 1=8', 2=4'

    private let panel = Color(red: 0.08, green: 0.08, blue: 0.09)
    private let cream = Color(red: 0.93, green: 0.90, blue: 0.82)
    private let label = Color(red: 0.88, green: 0.86, blue: 0.78)

    private var currentName: String {
        PresetLibrary.juno[safe: address.patchIndex]?.shortName ?? "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top section headers
            HStack(spacing: 1) {
                sectionHeader("KEYBOARD", color: Color(red: 0.82, green: 0.80, blue: 0.72), dark: true)
                sectionHeader("ARPEGGIO", color: Color(red: 0.15, green: 0.35, blue: 0.75))
                sectionHeader("LFO", color: Color(red: 0.75, green: 0.12, blue: 0.12))
                sectionHeader("DCO", color: Color(red: 0.75, green: 0.12, blue: 0.12))
                sectionHeader("HPF", color: Color(red: 0.75, green: 0.12, blue: 0.12))
                sectionHeader("VCF", color: Color(red: 0.75, green: 0.12, blue: 0.12))
                sectionHeader("VCA", color: Color(red: 0.75, green: 0.12, blue: 0.12))
                sectionHeader("ENV", color: Color(red: 0.75, green: 0.12, blue: 0.12))
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // Main controls row
            HStack(alignment: .top, spacing: 6) {
                keyboardSection
                arpeggioSection
                lfoSection
                dcoSection
                hpfSection
                vcfSection
                vcaSection
                envSection
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color(red: 0.15, green: 0.35, blue: 0.75))
                .frame(height: 3)
                .padding(.horizontal, 8)

            // Memory / chorus row
            memoryRow
                .padding(.horizontal, 10)
                .padding(.vertical, 10)

            // Name readout + logos
            HStack {
                Text("Roland")
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .foregroundStyle(cream.opacity(0.7))
                    .italic()
                Spacer()
                Text(currentName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(cream)
                    .lineLimit(1)
                Spacer()
                Text("JU-06A  ·  AMYboard")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(cream.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(panel)
                .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onAppear { applySelection() }
    }

    // MARK: - Sections

    private var keyboardSection: some View {
        VStack(spacing: 6) {
            junoButton("HOLD", lit: false)
            junoButton("CHORD", lit: false)
            junoButton("NOTE", lit: false)
        }
        .frame(width: 52)
    }

    private var arpeggioSection: some View {
        VStack(spacing: 6) {
            junoButton("ON/OFF", lit: false, accent: true)
            Text("MODE")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(label.opacity(0.7))
            Text("UP  U&D  DOWN")
                .font(.system(size: 6, weight: .medium, design: .monospaced))
                .foregroundStyle(label.opacity(0.55))
            // Rate knob (visual)
            ZStack {
                Circle()
                    .fill(Color(white: 0.12))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                Capsule()
                    .fill(Color.orange)
                    .frame(width: 3, height: 12)
                    .offset(y: -8)
            }
            Text("RATE")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(label.opacity(0.7))
        }
        .frame(width: 70)
    }

    private var lfoSection: some View {
        HStack(alignment: .bottom, spacing: 4) {
            JunoSlider(label: "RATE", value: $lfoRate)
            JunoSlider(label: "DELAY", value: $lfoDelay)
        }
    }

    private var dcoSection: some View {
        HStack(alignment: .bottom, spacing: 4) {
            VStack(spacing: 3) {
                ForEach(["16'", "8'", "4'"], id: \.self) { r in
                    let idx = ["16'", "8'", "4'"].firstIndex(of: r)!
                    miniLitButton(r, on: rangeStop == idx) {
                        rangeStop = idx
                    }
                }
                Text("RANGE")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(label.opacity(0.65))
            }
            JunoSlider(label: "LFO", value: $dcoLfo)
            JunoSlider(label: "PWM", value: $dcoPwm)
            JunoSlider(label: "SUB", value: $dcoSub)
            JunoSlider(label: "NOISE", value: $dcoNoise)
        }
    }

    private var hpfSection: some View {
        VStack(spacing: 4) {
            ForEach([3, 2, 1, 0], id: \.self) { n in
                miniLitButton("\(n)", on: false) {}
            }
            Text("FREQ")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(label.opacity(0.65))
        }
        .frame(width: 36)
    }

    private var vcfSection: some View {
        HStack(alignment: .bottom, spacing: 4) {
            JunoSlider(label: "FREQ", value: $vcfFreq) {
                // Map 0…1 → ~80Hz…8kHz
                let hz = 80.0 * pow(100.0, vcfFreq)
                midi.tweak(filterFreqHz: hz, resonance: vcfRes)
            }
            JunoSlider(label: "RES", value: $vcfRes) {
                let hz = 80.0 * pow(100.0, vcfFreq)
                midi.tweak(filterFreqHz: hz, resonance: vcfRes)
            }
            JunoSlider(label: "ENV", value: $vcfEnv)
            JunoSlider(label: "LFO", value: $vcfLfo)
            JunoSlider(label: "KYBD", value: $vcfKybd)
        }
    }

    private var vcaSection: some View {
        HStack(alignment: .bottom, spacing: 4) {
            JunoSlider(label: "LEVEL", value: $vcaLevel) {
                midi.tweak(volume: vcaLevel)
            }
        }
    }

    private var envSection: some View {
        HStack(alignment: .bottom, spacing: 4) {
            JunoSlider(label: "A", value: $envA)
            JunoSlider(label: "D", value: $envD)
            JunoSlider(label: "S", value: $envS)
            JunoSlider(label: "R", value: $envR)
        }
    }

    private var memoryRow: some View {
        HStack(alignment: .center, spacing: 12) {
            // LED
            Text(address.ledText)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 1, green: 0.25, blue: 0.15))
                .shadow(color: Color.red.opacity(0.7), radius: 6)
                .frame(width: 56)
                .padding(.vertical, 4)
                .background(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.15)))

            // Group A/B
            VStack(spacing: 4) {
                Text("GROUP")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(label.opacity(0.65))
                HStack(spacing: 4) {
                    memButton("A", on: !address.groupIsB) {
                        address.groupIsB = false
                        applySelection()
                    }
                    memButton("B", on: address.groupIsB) {
                        address.groupIsB = true
                        applySelection()
                    }
                }
            }

            // Banks 1–8
            VStack(spacing: 4) {
                Text("BANK")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color(red: 0.45, green: 0.65, blue: 1.0))
                HStack(spacing: 3) {
                    ForEach(1...8, id: \.self) { b in
                        memButton("\(b)", on: address.bank == b, wide: false) {
                            address.bank = b
                            applySelection()
                        }
                    }
                }
            }

            // Patches 1–8
            VStack(spacing: 4) {
                Text("PATCH")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.55))
                HStack(spacing: 3) {
                    ForEach(1...8, id: \.self) { p in
                        memButton("\(p)", on: address.patch == p, wide: false) {
                            address.patch = p
                            applySelection()
                        }
                    }
                }
            }

            // Chorus
            VStack(spacing: 4) {
                Text("CHORUS")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color(red: 0.9, green: 0.2, blue: 0.2))
                HStack(spacing: 3) {
                    ForEach([(0, "Off"), (1, "I"), (2, "II")], id: \.0) { item in
                        memButton(item.1, on: chorus == item.0, accent: item.0 > 0) {
                            chorus = item.0
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(address.displayCode)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(cream)
                Text("patch \(address.patchIndex)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(label.opacity(0.5))
            }
        }
    }

    // MARK: - Actions

    private func applySelection() {
        midi.loadJuno(address: address)
    }

    // MARK: - Chrome

    private func sectionHeader(_ title: String, color: Color, dark: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(dark ? Color.black.opacity(0.75) : Color.white.opacity(0.95))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(color)
    }

    private func junoButton(_ title: String, lit: Bool, accent: Bool = false) -> some View {
        Text(title)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.7))
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(lit || accent ? Color.orange : cream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.black.opacity(0.35), lineWidth: 0.5)
            )
    }

    private func miniLitButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(on ? Color.orange : cream.opacity(0.7))
                .frame(width: 28, height: 14)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.14)))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(on ? Color.orange.opacity(0.8) : Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func memButton(_ title: String, on: Bool, wide: Bool = true, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.75))
                .frame(width: wide ? 28 : 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(on ? (accent ? Color.orange : Color(red: 1, green: 0.92, blue: 0.55)) : cream)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.black.opacity(0.35), lineWidth: 0.5)
                )
                .shadow(color: on ? Color.orange.opacity(0.35) : .clear, radius: 3)
        }
        .buttonStyle(.plain)
        .disabled(!midi.isConnected)
    }
}

// MARK: - Vertical slider (Juno fader)

struct JunoSlider: View {
    let label: String
    @Binding var value: Double
    var onChange: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let h = geo.size.height
                let y = (1 - value) * (h - 14)
                ZStack(alignment: .top) {
                    // Track
                    Capsule()
                        .fill(Color(white: 0.18))
                        .frame(width: 5)
                        .frame(maxHeight: .infinity)
                    // Cap
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.75), Color(white: 0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 16, height: 12)
                        .offset(y: y)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let v = 1 - (g.location.y / h)
                            value = min(1, max(0, v))
                        }
                        .onEnded { _ in onChange?() }
                )
            }
            .frame(width: 22, height: 88)

            Text(label)
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(Color(red: 0.88, green: 0.86, blue: 0.78).opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 28)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
