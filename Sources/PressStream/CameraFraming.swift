import Foundation

/// Enquadramento da câmera lateral, ajustável durante a gravação.
/// Escrito pela UI (main) e lido pelo compositor (sampleQueue).
final class CameraFraming {
    private let lock = NSLock()
    private var _zoom: Double = 0.4

    /// 0 = imagem inteira (com fundo desfocado), 1 = preenche a faixa (corte máximo).
    var zoom: Double {
        get { lock.lock(); defer { lock.unlock() }; return _zoom }
        set { lock.lock(); _zoom = min(max(newValue, 0), 1); lock.unlock() }
    }
}
