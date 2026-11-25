import SwiftUI

/// Slider de volume (0 a 200%, ou −∞ a +6 dB) com medidor de nível embaixo.
struct VolumeRow: View {
    @Binding var gain: Double
    let level: Float

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: gain < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(spacing: 4) {
                Slider(value: $gain, in: 0...2)
                    .controlSize(.small)
                LevelMeter(level: level)
            }
            Button(Self.dbLabel(gain)) { gain = 1 }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
                .help("Clique para voltar a 0 dB")
        }
    }

    static func dbLabel(_ gain: Double) -> String {
        guard gain > 0.001 else { return "−∞ dB" }
        let db = 20 * log10(gain)
        return abs(db) < 0.05 ? "0 dB" : String(format: "%+.1f dB", db)
    }
}

/// Medidor de pico em escala dB (−60 a 0). Fica vermelho perto do clip.
struct LevelMeter: View {
    let level: Float

    private var normalized: CGFloat {
        guard level > 0.000_001 else { return 0 }
        let db = 20 * log10(Double(level))
        return CGFloat(min(max((db + 60) / 60, 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [.green, .green, .yellow, .red],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geo.size.width * normalized)
                    }
            }
        }
        .frame(height: 4)
        .animation(.linear(duration: 0.06), value: normalized)
    }
}

/// Uma fonte de áudio: seletor de device + volume/medidor quando há device escolhido.
struct AudioSourceRow: View {
    let title: String
    let hint: String?
    let devices: [DeviceOption]
    @Binding var selection: String?
    @Binding var gain: Double
    let level: Float
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Row(title) {
                Picker(title, selection: $selection) {
                    Text("Nenhuma").tag(String?.none)
                    ForEach(devices) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
            .disabled(locked)

            if selection != nil {
                VolumeRow(gain: $gain, level: level)
            } else if let hint {
                Text(hint).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
