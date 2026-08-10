import SwiftUI
import AppKit

/// Simple one-octave-ish piano for click/drag playing.
struct KeyboardView: View {
    @ObservedObject var midi: AMYboardMIDI
    var baseNote: UInt8 = 60 // middle C

    /// White keys relative offsets in the octave, then we show 1.5 octaves.
    private let whiteOffsets: [UInt8] = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19]
    private let blackOffsets: [(offset: UInt8, afterWhiteIndex: Int)] = [
        (1, 0), (3, 1), // C# D#
        (6, 3), (8, 4), (10, 5), // F# G# A#
        (13, 7), (15, 8), // C# D# (next octave)
        (18, 10) // F#
    ]

    var body: some View {
        GeometryReader { geo in
            let whiteCount = CGFloat(whiteOffsets.count)
            let whiteW = geo.size.width / whiteCount
            let whiteH = geo.size.height
            let blackW = whiteW * 0.58
            let blackH = whiteH * 0.58

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(Array(whiteOffsets.enumerated()), id: \.offset) { _, off in
                        let note = baseNote + off
                        KeyView(
                            isBlack: false,
                            isActive: midi.activeNotes.contains(note),
                            width: whiteW,
                            height: whiteH
                        )
                        .gesture(noteGesture(note: note))
                    }
                }

                ForEach(Array(blackOffsets.enumerated()), id: \.offset) { _, item in
                    let note = baseNote + item.offset
                    let x = CGFloat(item.afterWhiteIndex + 1) * whiteW - blackW / 2
                    KeyView(
                        isBlack: true,
                        isActive: midi.activeNotes.contains(note),
                        width: blackW,
                        height: blackH
                    )
                    .offset(x: x)
                    .gesture(noteGesture(note: note))
                }
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func noteGesture(note: UInt8) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !midi.activeNotes.contains(note) {
                    midi.noteOn(note)
                }
            }
            .onEnded { _ in
                midi.noteOff(note)
            }
    }
}

private struct KeyView: View {
    let isBlack: Bool
    let isActive: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: isBlack ? 4 : 6, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: isBlack ? 4 : 6, style: .continuous)
                    .stroke(Color.black.opacity(isBlack ? 0.4 : 0.15), lineWidth: 1)
            )
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(isBlack ? 0.35 : 0.08), radius: isActive ? 0 : 2, y: isActive ? 0 : 1)
            .offset(y: isActive ? 1 : 0)
    }

    private var fill: Color {
        if isActive {
            return Color.accentColor.opacity(isBlack ? 0.9 : 0.75)
        }
        return isBlack ? Color.black.opacity(0.88) : Color.white
    }
}

/// Computer-keyboard → MIDI note map (ASDF row like a piano).
enum ComputerKeys {
    static func note(for event: NSEvent) -> UInt8? {
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              let ch = chars.first else { return nil }
        let table: [Character: UInt8] = [
            "a": 60, "w": 61, "s": 62, "e": 63, "d": 64,
            "f": 65, "t": 66, "g": 67, "y": 68, "h": 69,
            "u": 70, "j": 71, "k": 72,
            "o": 73, "l": 74, "p": 75, ";": 76, "'": 77
        ]
        return table[ch]
    }
}
