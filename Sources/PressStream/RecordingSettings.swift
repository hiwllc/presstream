import AVFoundation
import CoreGraphics

enum VideoCodec: String, CaseIterable, Identifiable {
    case h264 = "H.264"
    case hevc = "HEVC"

    var id: String { rawValue }
    var avCodec: AVVideoCodecType { self == .h264 ? .h264 : .hevc }
}

enum OutputResolution: Int, CaseIterable, Identifiable {
    case p720 = 720
    case p1080 = 1080
    case p1440 = 1440

    var id: Int { rawValue }
    var label: String { "\(rawValue)p" }
}

/// Formato do vídeo no modo câmera lateral.
enum CanvasShape: String, CaseIterable, Identifiable {
    case fitSource = "Ajustar à fonte"  // fonte na altura toda, câmera = 1/4 da largura final
    case widescreen = "16:9"            // formato fixo (melhor para stream), pode sobrar faixa preta
    var id: String { rawValue }
}

/// Lado da faixa da câmera no modo lateral.
enum CameraSide: String, CaseIterable, Identifiable {
    case left = "Esquerda"
    case right = "Direita"
    var id: String { rawValue }
}

/// Onde cada coisa fica no vídeo final (coordenadas de pixel, origem embaixo à esquerda).
struct CanvasLayout {
    let canvas: CGSize
    let content: CGRect
    let camera: CGRect?
}

struct RecordingSettings {
    var resolution: OutputResolution = .p1080
    var fps: Int = 60
    var codec: VideoCodec = .h264
    var captureSystemAudio = true
    var micUID: String?
    var musicUID: String?
    var showsCursor = true

    /// Bitrate em bits/s, calibrado para conteúdo de tela (texto pequeno + waveforms).
    var videoBitrate: Int {
        let base: Double
        switch resolution {
        case .p720: base = 8_000_000
        case .p1080: base = 16_000_000
        case .p1440: base = 26_000_000
        }
        let fpsFactor = fps >= 60 ? 1.0 : 0.65
        let codecFactor = codec == .hevc ? 0.7 : 1.0
        return Int(base * fpsFactor * codecFactor)
    }

    /// Caixa 16:9 da resolução escolhida (ex.: 1920×1080).
    var box: CGSize {
        let height = Double(resolution.rawValue)
        return CGSize(width: Double(Int(height * 16 / 9) & ~1), height: height)
    }

    /// Faixas de áudio que esta gravação vai ter.
    var audioTracks: [AudioTrack] {
        var tracks: [AudioTrack] = []
        if musicUID != nil { tracks.append(.music) }
        if micUID != nil { tracks.append(.mic) }
        if captureSystemAudio { tracks.append(.system) }
        return tracks
    }

    /// Bitrate ajustado à área real do vídeo (um canvas mais largo recebe mais bits).
    func bitrate(for size: CGSize) -> Int {
        let ratio = (size.width * size.height) / max(box.width * box.height, 1)
        return Int(Double(videoBitrate) * min(max(Double(ratio), 0.5), 1.5))
    }

    /// - sourcePixels: tamanho real (em pixels) da tela ou janela capturada.
    /// - sideCamera: modo lateral, câmera ocupando 1/4 da largura à direita.
    func layout(sourcePixels: CGSize, sideCamera: Bool, shape: CanvasShape = .fitSource,
                side: CameraSide = .right) -> CanvasLayout {
        if sideCamera && shape == .fitSource && sourcePixels.width > 0 && sourcePixels.height > 0 {
            // A fonte ocupa a altura toda (sem barras); a câmera vira 1/3 da largura da fonte,
            // ou seja, 1/4 do vídeo final. Limite de 4096 px de largura do H.264.
            var height = Double(resolution.rawValue)
            func widths(_ h: Double) -> (Double, Double) {
                let content = Double(Int(sourcePixels.width * h / sourcePixels.height) & ~1)
                return (content, Double(Int(content / 3) & ~1))
            }
            var (contentWidth, stripWidth) = widths(height)
            if contentWidth + stripWidth > 4096 {
                height = Double(Int(height * 4096 / (contentWidth + stripWidth)) & ~1)
                (contentWidth, stripWidth) = widths(height)
            }
            let left = side == .left
            return CanvasLayout(canvas: CGSize(width: contentWidth + stripWidth, height: height),
                                content: CGRect(x: left ? stripWidth : 0, y: 0, width: contentWidth, height: height),
                                camera: CGRect(x: left ? 0 : contentWidth, y: 0, width: stripWidth, height: height))
        }
        if sideCamera {
            let canvas = box
            let stripWidth = CGFloat(Int(canvas.width / 4) & ~1)
            let area = CGSize(width: canvas.width - stripWidth, height: canvas.height)
            let fitted = Self.fit(sourcePixels, in: area, allowUpscale: true)
            let left = side == .left
            let areaX: CGFloat = left ? stripWidth : 0
            let origin = CGPoint(x: areaX + ((area.width - fitted.width) / 2).rounded(.down),
                                 y: ((area.height - fitted.height) / 2).rounded(.down))
            return CanvasLayout(canvas: canvas,
                                content: CGRect(origin: origin, size: fitted),
                                camera: CGRect(x: left ? 0 : area.width, y: 0, width: stripWidth, height: canvas.height))
        }
        // Sem composição: o vídeo tem exatamente o tamanho da fonte (sem ampliar).
        let fitted = Self.fit(sourcePixels, in: box, allowUpscale: false)
        return CanvasLayout(canvas: fitted, content: CGRect(origin: .zero, size: fitted), camera: nil)
    }

    private static func fit(_ source: CGSize, in box: CGSize, allowUpscale: Bool) -> CGSize {
        guard source.width > 0, source.height > 0 else { return box }
        var scale = min(box.width / source.width, box.height / source.height)
        if !allowUpscale { scale = min(scale, 1) }
        return CGSize(width: CGFloat(Int(source.width * scale) & ~1),
                      height: CGFloat(Int(source.height * scale) & ~1))
    }
}
