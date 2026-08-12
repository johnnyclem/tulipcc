import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var midi = AMYboardMIDI()
    @State private var instrument: SynthInstrument = .dx7
    @State private var junoAddress = JunoMemoryAddress(groupIsB: false, bank: 2, patch: 7) // Elect. Piano I-ish
    @State private var dx7Address = DX7MemoryAddress.home
    @State private var showSetup = true
    @State private var keyMonitor: Any?
    @State private var oledDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showSetup {
                SetupBanner(midi: midi) {
                    withAnimation { showSetup = false }
                }
                Divider()
            }

            ScrollView {
                VStack(spacing: 16) {
                    instrumentPicker
                    panel
                    oledPanel
                    statusLine
                }
                .padding(16)
            }

            Divider()
            keyboardBar
        }
        .frame(minWidth: 960, minHeight: 780)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            installKeyMonitor()
            // Load default voice for current instrument
            if instrument == .dx7 {
                midi.loadDX7(address: dx7Address)
            } else {
                midi.loadJuno(address: junoAddress)
            }
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: instrument) { newValue in
            switch newValue {
            case .juno: midi.loadJuno(address: junoAddress)
            case .dx7: midi.loadDX7(address: dx7Address)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AMYboard Starter")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Full JUNO + DX-7 factory banks · no code required")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            connectionBadge

            Button {
                midi.playTestPhrase()
            } label: {
                Label("Play test", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!midi.isConnected)
            .keyboardShortcut(.return, modifiers: [.command])

            Button {
                withAnimation { showSetup.toggle() }
            } label: {
                Label(showSetup ? "Hide setup" : "Setup help", systemImage: "questionmark.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var connectionBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(midi.isConnected ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
                .shadow(color: (midi.isConnected ? Color.green : Color.orange).opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(midi.isConnected ? "Connected" : "Not connected")
                    .font(.subheadline.weight(.semibold))
                Text(midi.portName ?? "Waiting for USB…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: - Instrument picker

    private var instrumentPicker: some View {
        HStack(spacing: 12) {
            ForEach(SynthInstrument.allCases) { inst in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        instrument = inst
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(inst == .juno ? "🎹" : "✨")
                            Text(inst.fullName)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Spacer()
                            if instrument == inst {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.white)
                            }
                        }
                        Text(inst.tagline)
                            .font(.caption)
                            .opacity(0.85)
                    }
                    .foregroundStyle(instrument == inst ? Color.white : Color.primary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(instrument == inst ? chipColor(inst) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(instrument == inst ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chipColor(_ inst: SynthInstrument) -> Color {
        switch inst {
        case .juno: return Color(red: 0.75, green: 0.15, blue: 0.15)
        case .dx7: return Color(red: 0.45, green: 0.38, blue: 0.28)
        }
    }

    // MARK: - Panel

    @ViewBuilder
    private var panel: some View {
        switch instrument {
        case .juno:
            JunoPanelView(midi: midi, address: $junoAddress)
        case .dx7:
            DX7PanelView(midi: midi, address: $dx7Address)
        }
    }

    private var statusLine: some View {
        HStack {
            if let err = midi.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(midi.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let p = midi.loadedPreset {
                Text("\(p.familyLabel) · \(p.shortName) · #\(p.id)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - OLED (hardware + Mac preview)

    private var oledPanel: some View {
        HStack(alignment: .top, spacing: 16) {
            // Mac-side preview of the 128×128 panel (8×16 chars).
            VStack(alignment: .leading, spacing: 6) {
                Text("OLED preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(midi.oledPreviewLines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.75, green: 0.95, blue: 0.55))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .frame(width: 168, height: 148, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
                Text(midi.isConnected
                     ? (midi.oledReady ? "Pushing to front I2C panel" : "Preparing display…")
                     : "Connect board to drive OLED")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Hardware OLED")
                    .font(.headline)
                Text("Shows engine, bank, patch, and live notes on the 128×128 front-panel screen. Type a short classroom message below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    TextField("Message for the OLED (e.g. Hello class!)", text: $oledDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { sendOLEDMessage() }
                    Button("Show on OLED") { sendOLEDMessage() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!midi.isConnected || oledDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Clear") {
                        oledDraft = ""
                        midi.setOLEDUserText("")
                    }
                    .disabled(!midi.isConnected)
                }

                HStack {
                    Button("Refresh OLED") { midi.refreshOLED() }
                        .disabled(!midi.isConnected)
                    Spacer()
                    if !midi.activeNotes.isEmpty {
                        Text("Playing: " + midi.activeNotes.sorted().map(AMYboardMIDI.noteName).joined(separator: " "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func sendOLEDMessage() {
        let t = oledDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        midi.setOLEDUserText(t)
    }

    // MARK: - Keyboard

    private var keyboardBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Play")
                    .font(.headline)
                Text("Click keys, or type A W S E D F T G Y H J K  ·  sound from the AMYboard jack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Silence") {
                    midi.allNotesOff()
                }
                .disabled(!midi.isConnected)
            }
            KeyboardView(midi: midi)
                .opacity(midi.isConnected ? 1 : 0.45)
                .allowsHitTesting(midi.isConnected)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Computer keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            if event.modifierFlags.contains(.command) { return event }
            guard let note = ComputerKeys.note(for: event) else { return event }
            if event.isARepeat { return nil }
            if event.type == .keyDown {
                midi.noteOn(note)
            } else {
                midi.noteOff(note)
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

// MARK: - Setup banner

private struct SetupBanner: View {
    @ObservedObject var midi: AMYboardMIDI
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Classroom setup — 60 seconds", systemImage: "graduationcap.fill")
                    .font(.headline)
                Spacer()
                Button("Got it", action: onDismiss)
                    .buttonStyle(.bordered)
            }

            HStack(alignment: .top, spacing: 16) {
                step(num: "1", title: "Plug in USB-C", body: "Data cable into AMYboard + Mac. Wait for green Connected.")
                step(num: "2", title: "Plug in sound", body: "Headphones/speakers into the AMYboard audio OUT. Start quiet.")
                step(num: "3", title: "Pick JUNO or DX-7", body: "Tap a bank/patch on the panel (try DX-7 voice 11 — Electric Piano). Then Play test. The front OLED tracks engine/bank/patch + notes.")
            }

            if !midi.isConnected {
                Label("No board yet — check the cable, and close amyboard.com or any other app using the board.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.08))
    }

    private func step(num: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(num)
                    .font(.caption.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
                    .foregroundStyle(.white)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
