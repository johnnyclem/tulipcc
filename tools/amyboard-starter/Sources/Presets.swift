import Foundation

/// Which hardware face the app is showing.
enum SynthInstrument: String, CaseIterable, Identifiable {
    case juno = "JUNO"
    case dx7 = "DX-7"

    var id: String { rawValue }

    var fullName: String {
        switch self {
        case .juno: return "JUNO-6"
        case .dx7: return "DX7"
        }
    }

    var tagline: String {
        switch self {
        case .juno: return "Roland-style analog · 128 patches"
        case .dx7: return "Yamaha FM · 128 patches"
        }
    }
}

/// One factory preset.
struct SoundPreset: Identifiable, Hashable {
    let id: Int          // AMY patch number (0–127 Juno, 128–255 DX7)
    let name: String
    let family: SynthInstrument

    var bankMSB: UInt8 { UInt8(id / 128) }
    var program: UInt8 { UInt8(id % 128) }
    var familyLabel: String { family.rawValue }

    /// Clean display name (trim factory padding).
    var shortName: String {
        name.trimmingCharacters(in: .whitespaces)
    }
}

enum PresetLibrary {
    static let juno: [SoundPreset] = PatchBanks.juno.enumerated().map { i, name in
        SoundPreset(id: i, name: name, family: .juno)
    }

    static let dx7: [SoundPreset] = PatchBanks.dx7.enumerated().map { i, name in
        SoundPreset(id: 128 + i, name: name, family: .dx7)
    }

    static func presets(for instrument: SynthInstrument) -> [SoundPreset] {
        switch instrument {
        case .juno: return juno
        case .dx7: return dx7
        }
    }

    static func preset(id: Int) -> SoundPreset? {
        if id < 128 { return juno[safe: id] }
        if id < 256 { return dx7[safe: id - 128] }
        return nil
    }
}

// MARK: - JUNO memory map (A11–A88, B11–B88)

/// Roland-style memory: group A/B × bank 1–8 × patch 1–8 = 128.
struct JunoMemoryAddress: Equatable {
    var groupIsB: Bool   // false = A, true = B
    var bank: Int        // 1…8
    var patch: Int       // 1…8

    static let home = JunoMemoryAddress(groupIsB: false, bank: 1, patch: 1)

    var patchIndex: Int {
        (groupIsB ? 64 : 0) + (bank - 1) * 8 + (patch - 1)
    }

    var displayCode: String {
        // e.g. A11, B68 — matches factory naming vibe
        let g = groupIsB ? "B" : "A"
        return "\(g)\(bank)\(patch)"
    }

    var ledText: String {
        // Two-char LED like JU-06A "6A"
        "\(bank)\(groupIsB ? "B" : "A")"
    }

    init(groupIsB: Bool, bank: Int, patch: Int) {
        self.groupIsB = groupIsB
        self.bank = min(8, max(1, bank))
        self.patch = min(8, max(1, patch))
    }

    init(patchIndex: Int) {
        let i = min(127, max(0, patchIndex))
        groupIsB = i >= 64
        let local = i % 64
        bank = local / 8 + 1
        patch = local % 8 + 1
    }
}

// MARK: - DX7 memory map (4 banks × 32 voices)

struct DX7MemoryAddress: Equatable {
    var bank: Int   // 1…4
    var voice: Int  // 1…32

    static let home = DX7MemoryAddress(bank: 1, voice: 11) // E.PIANO 1 = index 10

    /// Index into 0…127 DX7 bank (AMY patch = 128 + patchIndex).
    var patchIndex: Int {
        (bank - 1) * 32 + (voice - 1)
    }

    var amyPatch: Int { 128 + patchIndex }

    var lcdLine: String {
        String(format: "INT%02d  %s", voice, bankLabel)
    }

    var bankLabel: String {
        ["I", "II", "III", "IV"][bank - 1]
    }

    init(bank: Int, voice: Int) {
        self.bank = min(4, max(1, bank))
        self.voice = min(32, max(1, voice))
    }

    init(patchIndex: Int) {
        let i = min(127, max(0, patchIndex))
        bank = i / 32 + 1
        voice = i % 32 + 1
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
