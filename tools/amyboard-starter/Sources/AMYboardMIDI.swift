import Foundation
import CoreMIDI
import Combine

/// Talks to a plugged-in AMYboard over USB MIDI (CoreMIDI).
///
/// Control path matches docs/amyboard/control_api.md:
///   SysEx F0 00 03 45 <ASCII payload> F7  — load patches, ping, zP Python
///   Channel-voice note on/off on channel 1 — play the loaded synth
///
/// Front-panel 128×128 OLED (SH1107/SSD1327) is driven with short `zP` lines that
/// call `amyboard.display` — same API as on-device sketches.
@MainActor
final class AMYboardMIDI: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var portName: String?
    @Published private(set) var statusMessage = "Plug in an AMYboard with a USB-C cable."
    @Published private(set) var lastError: String?
    @Published private(set) var loadedPreset: SoundPreset?
    @Published var activeNotes: Set<UInt8> = []
    /// Optional classroom message shown on the bottom of the OLED.
    @Published var oledUserText: String = ""
    /// Last lines we pushed (for the Mac-side OLED preview).
    @Published private(set) var oledPreviewLines: [String] = Array(repeating: "", count: 8)
    @Published private(set) var oledReady = false

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var destEndpoint: MIDIEndpointRef = 0
    private var sourceEndpoint: MIDIEndpointRef = 0
    private var pollTimer: Timer?
    private var oledDebounceTask: Task<Void, Never>?
    private var oledPrepared = false
    private let channel: UInt8 = 0  // MIDI channel 1 (0-indexed)

    /// SPSS manufacturer ID used by AMYboard SysEx control frames.
    private let mfr: [UInt8] = [0x00, 0x03, 0x45]

    /// 8×8 font → 16 columns on a 128-wide panel.
    private let oledCols = 16

    init() {
        setupMIDI()
        startPolling()
        refreshConnection()
    }

    deinit {
        pollTimer?.invalidate()
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: - Setup

    private func setupMIDI() {
        var status = MIDIClientCreateWithBlock("AMYboardStarter" as CFString, &client) { [weak self] notification in
            Task { @MainActor in
                self?.handleMIDINotification(notification)
            }
        }
        if status != noErr {
            lastError = "Could not start MIDI (error \(status))."
            return
        }

        status = MIDIOutputPortCreate(client, "AMYboardStarterOut" as CFString, &outputPort)
        if status != noErr {
            lastError = "Could not open MIDI output (error \(status))."
            return
        }

        status = MIDIInputPortCreateWithBlock(client, "AMYboardStarterIn" as CFString, &inputPort) { _, _ in }
        if status != noErr {
            inputPort = 0
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshConnection()
            }
        }
    }

    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgObjectAdded, .msgObjectRemoved, .msgSetupChanged:
            refreshConnection()
        default:
            break
        }
    }

    // MARK: - Connection

    func refreshConnection() {
        let match = findAMYboard()
        let wasConnected = isConnected

        if let match {
            destEndpoint = match.dest
            sourceEndpoint = match.source
            portName = match.name
            isConnected = true
            if !wasConnected {
                statusMessage = "Connected to \(match.name). Pick a sound!"
                lastError = nil
                oledPrepared = false
                // Claim the OLED for this app (stops a running sketch loop that
                // would otherwise overwrite the panel).
                prepareOLED()
                scheduleOLEDRefresh(immediate: true)
            }
            if inputPort != 0, sourceEndpoint != 0 {
                MIDIPortConnectSource(inputPort, sourceEndpoint, nil)
            }
        } else {
            if wasConnected {
                statusMessage = "AMYboard disconnected. Plug it back in with USB-C."
            } else {
                statusMessage = "Plug in an AMYboard with a USB-C cable."
            }
            destEndpoint = 0
            sourceEndpoint = 0
            portName = nil
            isConnected = false
            loadedPreset = nil
            activeNotes.removeAll()
            oledPrepared = false
            oledReady = false
            oledPreviewLines = Array(repeating: "", count: 8)
        }
    }

    private struct Match {
        let name: String
        let dest: MIDIEndpointRef
        let source: MIDIEndpointRef
    }

    private func findAMYboard() -> Match? {
        let destCount = MIDIGetNumberOfDestinations()
        var dests: [(String, MIDIEndpointRef)] = []
        for i in 0..<destCount {
            let ep = MIDIGetDestination(i)
            let name = endpointName(ep)
            if isAMYboardName(name) {
                dests.append((name, ep))
            }
        }
        guard let firstDest = dests.first else { return nil }

        let srcCount = MIDIGetNumberOfSources()
        var source: MIDIEndpointRef = 0
        for i in 0..<srcCount {
            let ep = MIDIGetSource(i)
            if isAMYboardName(endpointName(ep)) {
                source = ep
                break
            }
        }
        return Match(name: firstDest.0, dest: firstDest.1, source: source)
    }

    private func isAMYboardName(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("amyboard") || n.contains("spss")
    }

    private func endpointName(_ endpoint: MIDIEndpointRef) -> String {
        var cfName: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &cfName) == noErr,
              let name = cfName?.takeRetainedValue() as String? else {
            return "MIDI device"
        }
        return name
    }

    // MARK: - Load patch

    /// Load a factory preset onto channel/synth 1 with comfortable polyphony.
    func load(_ preset: SoundPreset) {
        guard isConnected else {
            lastError = "No AMYboard connected."
            return
        }

        // Raw AMY wire over SysEx — sets patch + polyphony on synth 1.
        let voices = preset.family == .juno ? 6 : 8
        let wire = "i1K\(preset.id)iv\(voices)Z"
        sendSysExPayload(Array(wire.utf8))

        // Bank + PC so the board's MIDI layer stays in sync.
        send([0xB0 | channel, 0x00, preset.bankMSB])
        send([0xC0 | channel, preset.program])

        loadedPreset = preset
        statusMessage = "Loaded \(preset.familyLabel) — \(preset.shortName)"
        lastError = nil
        scheduleOLEDRefresh(immediate: true)
    }

    func loadJuno(address: JunoMemoryAddress) {
        let idx = address.patchIndex
        guard let preset = PresetLibrary.juno[safe: idx] else { return }
        load(preset)
    }

    func loadDX7(address: DX7MemoryAddress) {
        let idx = address.patchIndex
        guard let preset = PresetLibrary.dx7[safe: idx] else { return }
        load(preset)
    }

    /// Lightweight live tweak (filter / level) via Python on the board.
    /// Values are 0…1. Short zP lines only.
    func tweak(filterFreqHz: Double? = nil, resonance: Double? = nil, volume: Double? = nil) {
        guard isConnected else { return }
        var parts: [String] = []
        if let f = filterFreqHz {
            let hz = Int(max(40, min(12000, f)))
            parts.append("filter_freq=\(hz)")
        }
        if let r = resonance {
            let q = String(format: "%.2f", max(0, min(1, r)))
            parts.append("resonance=\(q)")
        }
        if let v = volume {
            let vol = String(format: "%.2f", max(0, min(1, v)))
            parts.append("amp=\(vol)")
        }
        guard !parts.isEmpty else { return }
        // Target voice osc 0 of the current synth — best-effort live tweak.
        let code = "import amy;amy.send(synth=1,osc=0,\(parts.joined(separator: ",")))"
        if code.utf8.count <= 250 {
            sendSysExPayload(Array("zP\(code)Z".utf8))
        }
    }

    /// Play a short C major arpeggio + chord.
    func playTestPhrase() {
        guard isConnected else {
            lastError = "No AMYboard connected."
            return
        }
        if loadedPreset == nil {
            loadDX7(address: .home)
        }

        let notes: [UInt8] = [60, 64, 67, 72]
        Task {
            for n in notes {
                noteOn(n, velocity: 100)
                try? await Task.sleep(nanoseconds: 280_000_000)
                noteOff(n)
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            for n: UInt8 in [60, 64, 67] {
                noteOn(n, velocity: 90)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            allNotesOff()
        }
    }

    // MARK: - Notes

    func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        guard isConnected else { return }
        let vel = max(1, min(velocity, 127))
        send([0x90 | channel, note, vel])
        activeNotes.insert(note)
        scheduleOLEDRefresh()
    }

    func noteOff(_ note: UInt8) {
        guard isConnected else { return }
        send([0x80 | channel, note, 0])
        activeNotes.remove(note)
        scheduleOLEDRefresh()
    }

    func allNotesOff() {
        guard isConnected else { return }
        send([0xB0 | channel, 123, 0])
        for n in activeNotes {
            send([0x80 | channel, n, 0])
        }
        activeNotes.removeAll()
        scheduleOLEDRefresh(immediate: true)
    }

    // MARK: - OLED (front-panel 128×128)

    /// Apply user text and refresh the panel immediately.
    func setOLEDUserText(_ text: String) {
        oledUserText = String(text.prefix(48))
        scheduleOLEDRefresh(immediate: true)
    }

    /// Force a redraw of engine / bank / patch / notes / user text.
    func refreshOLED() {
        scheduleOLEDRefresh(immediate: true)
    }

    /// Stop any sketch loop and init the I2C OLED once per connection.
    private func prepareOLED() {
        guard isConnected else { return }
        // stop_sketch so menu_nav (etc.) doesn't overwrite our draws.
        runPython("import amyboard;amyboard.stop_sketch()")
        runPython("import amyboard;amyboard.init_display()")
        oledPrepared = true
        oledReady = true
    }

    private func scheduleOLEDRefresh(immediate: Bool = false) {
        oledDebounceTask?.cancel()
        let delay: UInt64 = immediate ? 20_000_000 : 90_000_000
        oledDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await pushOLEDFrame()
        }
    }

    private func pushOLEDFrame() async {
        guard isConnected else { return }
        if !oledPrepared {
            prepareOLED()
            // Let stop_sketch / init_display finish before drawing.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
        }

        let lines = buildOLEDLines()
        oledPreviewLines = lines

        // Pack 2 rows per zP; brief pause so the board can ACK (control_api.md).
        // Color 255 works on SH1107/SSD1327; mono panels treat non-zero as on.
        runPython("import amyboard as A;d=A.display;d.fill(0) if (d and d.available) else None")
        try? await Task.sleep(nanoseconds: 30_000_000)
        guard !Task.isCancelled else { return }

        var i = 0
        while i < lines.count {
            let y0 = i * 12
            let a = pyQuote(lines[i])
            if i + 1 < lines.count {
                let y1 = (i + 1) * 12
                let b = pyQuote(lines[i + 1])
                runPython("import amyboard as A;d=A.display;(d.text('\(a)',0,\(y0),255),d.text('\(b)',0,\(y1),255)) if (d and d.available) else None")
            } else {
                runPython("import amyboard as A;d=A.display;d.text('\(a)',0,\(y0),255) if (d and d.available) else None")
            }
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard !Task.isCancelled else { return }
            i += 2
        }
        runPython("import amyboard as A;d=A.display;d.show() if (d and d.available) else None")
    }

    /// Layout (8 rows × 16 chars) for the 128×128 panel.
    private func buildOLEDLines() -> [String] {
        var lines = Array(repeating: "", count: 8)

        if let p = loadedPreset {
            lines[0] = fit("ENGINE \(p.familyLabel)")
            lines[1] = fit("BANK  \(bankLabel(for: p))")
            lines[2] = fit("PATCH \(p.shortName)")
            lines[3] = fit("#\(p.id)")
        } else {
            lines[0] = fit("ENGINE --")
            lines[1] = fit("BANK  --")
            lines[2] = fit("PATCH (none)")
            lines[3] = fit("pick a sound")
        }

        lines[4] = fit("NOTES")
        let notes = activeNotes.sorted().map(Self.noteName).joined(separator: " ")
        if notes.isEmpty {
            lines[5] = fit("(none)")
        } else {
            // May spill to row 6 if many notes.
            let wrapped = wrap(notes, width: oledCols, maxLines: 2)
            lines[5] = fit(wrapped[0])
            if wrapped.count > 1 {
                lines[6] = fit(wrapped[1])
            }
        }

        let msg = oledUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !msg.isEmpty {
            // Prefer bottom row(s) for classroom text.
            let msgLines = wrap(msg, width: oledCols, maxLines: 2)
            if lines[6].isEmpty {
                lines[6] = fit(msgLines[0])
                if msgLines.count > 1 { lines[7] = fit(msgLines[1]) }
            } else {
                lines[7] = fit(msgLines[0])
            }
        } else if lines[7].isEmpty {
            lines[7] = fit(isConnected ? "AMYboard" : "")
        }
        return lines
    }

    private func bankLabel(for preset: SoundPreset) -> String {
        switch preset.family {
        case .juno:
            return JunoMemoryAddress(patchIndex: preset.id).displayCode
        case .dx7:
            let a = DX7MemoryAddress(patchIndex: preset.id - 128)
            return "\(a.bankLabel)-\(a.voice)"
        }
    }

    private func fit(_ s: String) -> String {
        String(s.prefix(oledCols))
    }

    private func wrap(_ s: String, width: Int, maxLines: Int) -> [String] {
        var out: [String] = []
        var rest = s
        while !rest.isEmpty && out.count < maxLines {
            if rest.count <= width {
                out.append(rest)
                break
            }
            out.append(String(rest.prefix(width)))
            rest = String(rest.dropFirst(width))
        }
        if out.isEmpty { out = [""] }
        return out
    }

    static func noteName(_ note: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let n = Int(note)
        return "\(names[n % 12])\(n / 12 - 1)"
    }

    /// Escape user/status text for a Python single-quoted string.
    private func pyQuote(_ s: String) -> String {
        var out = ""
        for ch in s {
            guard let u = ch.unicodeScalars.first else { continue }
            let v = u.value
            // Printable ASCII only (OLED font is 8×8 ASCII).
            guard v >= 32 && v < 127 else { continue }
            if ch == "'" || ch == "\\" { continue }
            out.append(ch)
            if out.count >= oledCols { break }
        }
        return out
    }

    /// Run one Python statement on the board via control SysEx `zP…Z`.
    private func runPython(_ code: String) {
        // Keep well under typical SysEx / board line limits.
        let trimmed = code.count > 240 ? String(code.prefix(240)) : code
        sendSysExPayload(Array("zP\(trimmed)Z".utf8))
    }

    // MARK: - Low-level MIDI

    private func sendSysExPayload(_ payload: [UInt8]) {
        var packet = [UInt8]()
        packet.append(0xF0)
        packet.append(contentsOf: mfr)
        packet.append(contentsOf: payload)
        packet.append(0xF7)
        send(packet)
    }

    private func send(_ bytes: [UInt8]) {
        guard destEndpoint != 0, outputPort != 0 else { return }

        let bufSize = 512
        let raw = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { raw.deallocate() }
        raw.withMemoryRebound(to: MIDIPacketList.self, capacity: 1) { listPtr in
            let packet = MIDIPacketListInit(listPtr)
            _ = MIDIPacketListAdd(listPtr, bufSize, packet, 0, bytes.count, bytes)
            let status = MIDISend(outputPort, destEndpoint, listPtr)
            if status != noErr {
                lastError = "MIDI send failed (error \(status))."
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
