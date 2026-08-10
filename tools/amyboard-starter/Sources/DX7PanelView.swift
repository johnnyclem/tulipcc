import SwiftUI

/// Visual recreation of a classic Yamaha DX7 front panel.
struct DX7PanelView: View {
    @ObservedObject var midi: AMYboardMIDI
    @Binding var address: DX7MemoryAddress

    @State private var dataEntry: Double = 0.5
    @State private var volume: Double = 0.8
    @State private var selectedOp: Int = 1
    @State private var opOn: [Bool] = Array(repeating: true, count: 6)
    @State private var algorithm: Int = 5

    private let beige = Color(red: 0.78, green: 0.70, blue: 0.55)
    private let beigeDark = Color(red: 0.62, green: 0.54, blue: 0.40)
    private let beigeLight = Color(red: 0.88, green: 0.82, blue: 0.68)
    private let brown = Color(red: 0.35, green: 0.28, blue: 0.20)
    private let blueKey = Color(red: 0.25, green: 0.45, blue: 0.72)
    private let lcdGreen = Color(red: 0.55, green: 0.85, blue: 0.45)

    private var currentName: String {
        PresetLibrary.dx7[safe: address.patchIndex]?.shortName ?? "—"
    }

    /// Classic DX7 algorithm diagram (simplified) — just a label; real algs are 1–32.
    private var algorithmLabel: String { String(format: "%02d", algorithm) }

    var body: some View {
        VStack(spacing: 0) {
            // Top brand bar
            HStack {
                Text("YAMAHA")
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(brown.opacity(0.75))
                    .tracking(2)
                Spacer()
                Text("DIGITAL PROGRAMMABLE ALGORITHM SYNTHESIZER")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(brown.opacity(0.55))
                    .tracking(0.8)
                Spacer()
                Text("DX7")
                    .font(.system(size: 18, weight: .heavy, design: .serif))
                    .foregroundStyle(brown)
                    .tracking(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            HStack(alignment: .top, spacing: 14) {
                // Left: volume + data
                VStack(spacing: 10) {
                    dxSlider(title: "VOLUME", value: $volume) {
                        midi.tweak(volume: volume)
                    }
                    dxSlider(title: "DATA\nENTRY", value: $dataEntry)
                    HStack(spacing: 6) {
                        dxBlueButton("-1 / NO")
                        dxBlueButton("+1 / YES")
                    }
                }
                .frame(width: 90)

                // Center: LCD + operators
                VStack(spacing: 10) {
                    lcdBlock
                    operatorsRow
                    functionRow
                }

                // Right: memory select legend
                VStack(alignment: .leading, spacing: 6) {
                    Text("INTERNAL")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(brown.opacity(0.7))
                    Text("BANK \(address.bankLabel)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(brown)
                    Text("VOICE \(address.voice)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(brown.opacity(0.85))
                    Divider().overlay(brown.opacity(0.3))
                    Text("AMY #\(address.amyPatch)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(brown.opacity(0.55))
                    Spacer(minLength: 0)
                    Text("AMYboard")
                        .font(.system(size: 10, weight: .semibold, design: .serif))
                        .foregroundStyle(brown.opacity(0.5))
                }
                .frame(width: 100)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            // Voice select 1–32
            voiceGrid
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            // Bank select
            HStack(spacing: 8) {
                Text("BANK")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(brown.opacity(0.65))
                ForEach(1...4, id: \.self) { b in
                    Button {
                        address.bank = b
                        // keep voice, clamp if needed
                        applySelection()
                    } label: {
                        Text(["I", "II", "III", "IV"][b - 1])
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(address.bank == b ? beigeLight : brown)
                            .frame(width: 36, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(address.bank == b ? brown : beigeLight)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(brown.opacity(0.4), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!midi.isConnected)
                }
                Spacer()
                Text("32 voices × 4 banks = 128 DX7 presets")
                    .font(.system(size: 9))
                    .foregroundStyle(brown.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [beigeLight, beige, beigeDark.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(brown.opacity(0.35), lineWidth: 1)
        )
        .onAppear { applySelection() }
    }

    // MARK: - LCD

    private var lcdBlock: some View {
        HStack(spacing: 12) {
            // Algorithm graphic box
            VStack(spacing: 4) {
                Text("ALGORITHM")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(lcdGreen.opacity(0.7))
                Text(algorithmLabel)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(lcdGreen)
                    .shadow(color: lcdGreen.opacity(0.5), radius: 4)
                // Tiny fake operator stack diagram
                AlgorithmGlyph(algorithm: algorithm)
                    .frame(height: 36)
            }
            .frame(width: 88)
            .padding(8)
            .background(Color.black.opacity(0.85))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1)))

            // Main LCD
            VStack(alignment: .leading, spacing: 4) {
                Text("Yamaha DX7")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(lcdGreen.opacity(0.65))
                Text("INT \(String(format: "%02d", address.voice))   BANK \(address.bankLabel)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lcdGreen)
                Text(currentName)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(lcdGreen)
                    .shadow(color: lcdGreen.opacity(0.45), radius: 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.black.opacity(0.85))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1)))
        }
        .frame(height: 100)
    }

    // MARK: - Operators

    private var operatorsRow: some View {
        HStack(spacing: 6) {
            Text("OPERATOR\nON/OFF")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(brown.opacity(0.7))
                .multilineTextAlignment(.trailing)
                .frame(width: 52)

            ForEach(1...6, id: \.self) { op in
                Button {
                    selectedOp = op
                    opOn[op - 1].toggle()
                } label: {
                    VStack(spacing: 2) {
                        Circle()
                            .fill(opOn[op - 1] ? Color.red.opacity(0.9) : Color.black.opacity(0.25))
                            .frame(width: 6, height: 6)
                            .shadow(color: opOn[op - 1] ? .red.opacity(0.6) : .clear, radius: 3)
                        Text("\(op)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(selectedOp == op ? beigeLight : brown)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(selectedOp == op ? brown : beigeLight)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(brown.opacity(0.35), lineWidth: 1)
                            )
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            VStack(spacing: 4) {
                Text("ALGORITHM")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(brown.opacity(0.65))
                HStack(spacing: 4) {
                    Button {
                        algorithm = max(1, algorithm - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(brown)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 3).fill(beigeLight))
                    }
                    .buttonStyle(.plain)
                    Text(algorithmLabel)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(brown)
                        .frame(width: 28)
                    Button {
                        algorithm = min(32, algorithm + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(brown)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 3).fill(beigeLight))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var functionRow: some View {
        HStack(spacing: 5) {
            ForEach(["WHEEL", "EG BIAS", "BREATH", "PITCH", "LFO", "PORTA", "EDIT", "FUNC"], id: \.self) { t in
                Text(t)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(beigeLight)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 2).fill(blueKey))
            }
        }
    }

    // MARK: - Voice grid 1–32

    private var voiceGrid: some View {
        VStack(spacing: 4) {
            Text("VOICE SELECT")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(brown.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 16), spacing: 4) {
                ForEach(1...32, id: \.self) { v in
                    Button {
                        address.voice = v
                        applySelection()
                    } label: {
                        Text("\(v)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(address.voice == v ? beigeLight : brown)
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(address.voice == v ? brown : beigeLight.opacity(0.9))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(brown.opacity(0.3), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!midi.isConnected)
                }
            }
        }
    }

    // MARK: - Actions

    private func applySelection() {
        midi.loadDX7(address: address)
    }

    // MARK: - Chrome

    private func dxSlider(title: String, value: Binding<Double>, onChange: (() -> Void)? = nil) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(brown.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(height: 22)
            GeometryReader { geo in
                let h = geo.size.height
                let y = (1 - value.wrappedValue) * (h - 16)
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 6)
                        .frame(maxHeight: .infinity)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.9), beigeDark],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 18, height: 14)
                        .offset(y: y)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let v = 1 - (g.location.y / h)
                            value.wrappedValue = min(1, max(0, v))
                        }
                        .onEnded { _ in onChange?() }
                )
            }
            .frame(height: 100)
        }
    }

    private func dxBlueButton(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(beigeLight)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 2).fill(blueKey))
    }
}

/// Tiny decorative algorithm diagram.
private struct AlgorithmGlyph: View {
    let algorithm: Int

    var body: some View {
        Canvas { context, size in
            let cols = 3
            let rows = 2
            let w = size.width / CGFloat(cols)
            let h = size.height / CGFloat(rows)
            for i in 0..<6 {
                let c = i % cols
                let r = i / cols
                let rect = CGRect(
                    x: CGFloat(c) * w + 4,
                    y: CGFloat(r) * h + 2,
                    width: w - 8,
                    height: h - 6
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(Color(red: 0.55, green: 0.85, blue: 0.45).opacity(0.85))
                )
                // connector
                if r == 0 {
                    var line = Path()
                    line.move(to: CGPoint(x: rect.midX, y: rect.maxY))
                    line.addLine(to: CGPoint(x: rect.midX, y: rect.maxY + 4))
                    context.stroke(line, with: .color(Color(red: 0.55, green: 0.85, blue: 0.45).opacity(0.5)), lineWidth: 1)
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
