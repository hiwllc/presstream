import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var engine: RecorderEngine

    var body: some View {
        VStack(spacing: 12) {
            header

            HStack(spacing: 16) {
                RecordButton(phase: engine.phase) { engine.toggleRecording() }
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.format(engine.elapsed))
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(engine.phase == .recording ? 1 : 0.3))
                    Text("⌘R para gravar / parar")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            if engine.screenPermissionMissing { permissionBanner }
            if let message = engine.errorMessage { errorBanner(message) }

            sourceCard.disabled(engine.isBusy)
            audioCard
            cameraCard
            qualityCard.disabled(engine.isBusy)

            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 32)
        .padding(.bottom, 14)
        .frame(width: 400)
        .background(Backdrop())
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.2), value: engine.isBusy)
        .animation(.easeOut(duration: 0.2), value: engine.cameraMode)
        .animation(.easeOut(duration: 0.2), value: engine.sourceKind)
    }

    // MARK: - Cards

    private var sourceCard: some View {
        Card("Fonte", icon: "rectangle.on.rectangle") {
            Picker("Fonte", selection: $engine.sourceKind) {
                ForEach(SourceKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            switch engine.sourceKind {
            case .display:
                Picker("Tela", selection: $engine.selectedDisplayID) {
                    ForEach(engine.displays) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
            case .window:
                HStack(spacing: 6) {
                    Picker("Janela", selection: $engine.selectedWindowID) {
                        if engine.windows.isEmpty { Text("Nenhuma janela aberta").tag(CGWindowID?.none) }
                        ForEach(engine.windows) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    Button { Task { await engine.refreshWindows() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Atualizar lista de janelas")
                }
                Text("Só a janela entra no vídeo, sem barra de menus nem Dock. Não minimize a janela durante a gravação.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var audioCard: some View {
        Card("Áudio", icon: "waveform") {
            AudioSourceRow(title: "Música", hint: "Controladora, interface ou device virtual (ex.: DJ Aggregate)",
                           devices: engine.audioDevices, selection: $engine.selectedMusicUID,
                           gain: $engine.musicGain, level: engine.levels[.music] ?? 0,
                           locked: engine.isBusy)

            Divider().opacity(0.4)

            AudioSourceRow(title: "Microfone", hint: nil,
                           devices: engine.audioDevices, selection: $engine.selectedMicUID,
                           gain: $engine.micGain, level: engine.levels[.mic] ?? 0,
                           locked: engine.isBusy)

            Divider().opacity(0.4)

            Row("Som do Mac") {
                Toggle("", isOn: $engine.captureSystemAudio).toggleStyle(.switch).labelsHidden()
            }
            .disabled(engine.isBusy)
            if engine.captureSystemAudio {
                VolumeRow(gain: $engine.systemGain, level: engine.levels[.system] ?? 0)
            }
        }
    }

    private var cameraCard: some View {
        Card("Câmera", icon: "person.crop.square") {
            Picker("Modo", selection: $engine.cameraMode) {
                ForEach(CameraMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .disabled(engine.isBusy)

            if engine.cameraMode != .off && engine.cameras.count > 1 {
                Picker("Câmera", selection: $engine.selectedCameraUID) {
                    ForEach(engine.cameras) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .disabled(engine.isBusy)
            }

            if engine.cameraMode == .side {
                HStack(spacing: 8) {
                    Picker("Formato", selection: $engine.canvasShape) {
                        ForEach(CanvasShape.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()

                    Picker("Lado", selection: $engine.cameraSide) {
                        ForEach(CameraSide.allCases) { side in
                            Image(systemName: side == .left ? "rectangle.lefthalf.filled" : "rectangle.righthalf.filled")
                                .help(side.rawValue)
                                .tag(side)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .frame(width: 84)
                }
                .disabled(engine.isBusy)

                HStack(spacing: 8) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Slider(value: $engine.cameraZoom, in: 0...1)
                        .controlSize(.small)
                        .help("Zoom da câmera — dá para ajustar durante a gravação")
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    LayoutPreview(session: engine.cameraFeed?.session, side: engine.cameraSide,
                                  zoom: engine.cameraZoom, cameraAspect: engine.cameraFeed?.aspectRatio ?? 16.0 / 9.0)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(engine.canvasShape == .fitSource
                             ? "A fonte ocupa a altura toda, sem barras. A câmera fica com 1/4 da largura."
                             : "Formato fixo 16:9 (ideal para stream). Janelas mais largas que 4:3 ficam com faixas pretas.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let label = engine.cameraFeed?.resolutionLabel, !label.isEmpty {
                            Label("Câmera em \(label)", systemImage: "camera")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if engine.bubbleHiddenInWindowMode {
                Label("Na gravação de janela a bolinha não aparece. Use o modo Lateral.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var qualityCard: some View {
        Card("Qualidade", icon: "sparkles") {
            Picker("Resolução", selection: $engine.resolution) {
                ForEach(OutputResolution.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            HStack(spacing: 10) {
                Picker("FPS", selection: $engine.fps) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented).labelsHidden()

                Picker("Codec", selection: $engine.codec) {
                    ForEach(VideoCodec.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            Text(engine.bitrateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Partes

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("PressStream")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            Spacer()
            StatusPill(phase: engine.phase)
        }
    }

    private var permissionBanner: some View {
        Banner(color: .orange, icon: "exclamationmark.shield.fill",
               text: "Permita o PressStream em Ajustes → Privacidade → Gravação de Tela e reabra o app.") {
            HStack {
                Button("Abrir Ajustes") { engine.openScreenRecordingSettings() }
                Button("Tentar de novo") { Task { await engine.refreshDisplays() } }
            }
            .controlSize(.small)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Banner(color: .red, icon: "xmark.octagon.fill", text: message) {
            Button("OK") { engine.errorMessage = nil }.controlSize(.small)
        }
    }

    private var footer: some View {
        HStack {
            Button { engine.openOutputFolder() } label: {
                Label("Movies/PressStream", systemImage: "folder")
            }
            .buttonStyle(.plain)
            Spacer()
            if engine.lastRecordingURL != nil {
                Button { engine.revealLastRecording() } label: {
                    Label("Última gravação", systemImage: "play.rectangle")
                }
                .buttonStyle(.plain)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
}

// MARK: - Componentes

enum Theme {
    static let accent = LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.42),
                                                Color(red: 0.62, green: 0.35, blue: 1)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
    static let record = LinearGradient(colors: [Color(red: 1, green: 0.38, blue: 0.38),
                                                Color(red: 0.86, green: 0.1, blue: 0.24)],
                                       startPoint: .top, endPoint: .bottom)
}

struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09)
            RadialGradient(colors: [Color(red: 0.55, green: 0.25, blue: 0.95).opacity(0.22), .clear],
                           center: .top, startRadius: 0, endRadius: 340)
            RadialGradient(colors: [Color(red: 1, green: 0.3, blue: 0.35).opacity(0.10), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 300)
        }
        .ignoresSafeArea()
    }
}

struct RecordButton: View {
    let phase: RecorderEngine.Phase
    let action: () -> Void
    @State private var pulse = false

    private var isRecording: Bool { phase == .recording }
    private var isWorking: Bool { phase == .starting || phase == .stopping }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.22))
                    .frame(width: 100, height: 100)
                    .scaleEffect(pulse ? 1.06 : 0.9)
                    .opacity(isRecording ? 1 : 0)
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 4)
                    .frame(width: 82, height: 82)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 31, style: .continuous)
                    .fill(Theme.record)
                    .frame(width: isRecording ? 30 : 62, height: isRecording ? 30 : 62)
                    .shadow(color: .red.opacity(0.55), radius: isRecording ? 16 : 8)
                if isWorking {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 104, height: 104)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .disabled(isWorking)
        .help(isRecording ? "Parar (⌘R)" : "Gravar (⌘R)")
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phase)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct StatusPill: View {
    let phase: RecorderEngine.Phase

    private var label: String {
        switch phase {
        case .idle: return "PRONTO"
        case .starting: return "INICIANDO"
        case .recording: return "GRAVANDO"
        case .stopping: return "SALVANDO"
        }
    }

    private var color: Color { phase == .recording ? .red : (phase == .idle ? .green : .orange) }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.15)))
        .overlay(Capsule().strokeBorder(color.opacity(0.35)))
    }
}

struct Card<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
    }
}

struct Row<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            trailing
        }
    }
}

struct Banner<Actions: View>: View {
    let color: Color
    let icon: String
    let text: String
    let actions: Actions

    init(color: Color, icon: String, text: String, @ViewBuilder actions: () -> Actions) {
        self.color = color
        self.icon = icon
        self.text = text
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: icon)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.35)))
    }
}
