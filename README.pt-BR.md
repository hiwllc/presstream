<div align="center">

# 🎛️ PressStream

**Gravador de tela leve para macOS, feito para DJs e produtores musicais.**

Grave o Ableton Live ou o Rekordbox com a sua câmera e a sua mix, sem engasgar um M1 de 8 GB.

[English](README.md) · [Arquitetura](docs/ARCHITECTURE.md) · [Como contribuir](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)

</div>

---

## Por quê

Gravadores genéricos fazem muito trabalho que você não precisa. Quando a DAW ou o software de DJ
já está usando boa parte da máquina, cada cópia extra de um frame pesa. O PressStream mantém todo
o caminho do vídeo na GPU e no chip de mídia, deixando a CPU livre para a música.

## Recursos

| | |
|---|---|
| 🖥️ **Fonte** | Tela inteira **ou uma janela só** (ex.: só o Ableton, sem barra de menus nem Dock) |
| 🎚️ **Áudio** | Até 3 faixas separadas: **Música** (controladora / interface / device virtual), **Microfone** e **Som do Mac** |
| 🔊 **Níveis** | Volume por faixa (−∞ a +6 dB) com medidor, ajustável **durante a gravação** |
| 📷 **Câmera** | **Bolinha** (flutuante, custo zero) ou **Lateral** ocupando 1/4 do vídeo, à esquerda ou à direita, com zoom ao vivo |
| 📐 **Formato** | *Ajustar à fonte* (sem faixas pretas) ou *16:9* fixo (pronto para stream) |
| 🎞️ **Qualidade** | 720p / 1080p / 1440p, 30 / 60 fps, H.264 ou HEVC por hardware |
| 🛟 **Segurança** | `.mov` fragmentado: se algo travar, o que já foi gravado continua tocando |
| 🙈 **Vídeo limpo** | O painel do PressStream nunca aparece na gravação |

## Requisitos

- macOS 13 Ventura ou mais novo (recomendado 14+)
- Apple Silicon (Macs Intel funcionam, mas não são o foco)
- Xcode ou as Command Line Tools (`xcode-select --install`)

## Começando

```bash
git clone https://github.com/<seu-usuario>/pressstream.git
cd pressstream
make run
```

| Comando | O que faz |
|---|---|
| `make build` | Compila e monta `build/PressStream.app` |
| `make run` | Compila e abre o app |
| `make clean` | Apaga os arquivos de build |

As gravações vão para `~/Movies/PressStream`.

### Permissões

1. **Gravação de Tela:** libere o PressStream em *Ajustes → Privacidade e Segurança → Gravação de Tela* e **reabra o app**.
2. **Câmera / Microfone:** pedidos ao ligar a câmera ou escolher uma entrada de áudio.

> Com um certificado *Apple Development* (Xcode → Settings → Accounts), o script assina com ele e a
> permissão de tela continua valendo entre builds. Sem certificado, a assinatura é ad-hoc e o macOS
> pode pedir a permissão de novo a cada build.

## Dicas para DJs

### Gravando o Rekordbox (ou qualquer app com saída num device virtual)

1. No Rekordbox, mande o master para o seu device virtual / agregado.
2. No PressStream, escolha esse device em **Música**.
3. Escolha o seu microfone de verdade em **Microfone**: cada um vira uma faixa com volume próprio.
4. Desligue o **Som do Mac** se o Rekordbox for o único som que importa, para não duplicar.

> O PressStream grava os **2 primeiros canais** de cada entrada. Se o seu device agregado coloca o
> microfone nos canais 1–2, escolha em **Música** o device virtual em si (ex.: BlackHole / Loopback)
> em vez do agregado.

### Mantendo o software de DJ liso num Mac de 8 GB

- **30 fps** corta pela metade o trabalho de captura, composição e codificação.
- Prefira gravar **Janela**: menos pixels que a tela inteira.
- A câmera **Bolinha** não custa nada; a **Lateral** adiciona uma composição na GPU (com prioridade baixa).
- **H.264** é um pouco mais leve que HEVC no chip de mídia do M1.
- Feche navegadores e outros apps pesados de GPU durante a gravação.

### Usando o iPhone como câmera (Câmera de Continuidade)

O iPhone costuma ter imagem bem melhor que uma webcam 1080p, principalmente em pouca luz, e o
microfone dele também é bom. O PressStream já suporta.

**Requisitos:** iPhone XR ou mais novo com iOS 16+ (recomendado iOS 17+), macOS 13+, mesmo
Apple ID nos dois, Wi-Fi e Bluetooth ligados e *Ajustes → Geral → AirPlay e Continuidade →
Câmera de Continuidade* ativado no iPhone.

1. Coloque o iPhone num suporte, **com a tela travada** e a câmera traseira virada pra você. Ele precisa ficar parado.
2. Escolha o iPhone na lista de câmeras (ex.: "Câmera do iPhone de Wallace"). A lista atualiza sozinha quando ele conecta.
3. Se quiser, escolha o microfone do iPhone em **Microfone**.

Dicas:

- **Imagem tremendo?** A estabilização óptica do iPhone amplia vibrações pequenas, e cada toque na
  controladora passa pela mesa. Use um tripé apoiado no chão ou um braço preso em outro móvel, ou
  pelo menos um apoio emborrachado embaixo do suporte.
- **Desligue o Center Stage** (*Central de Controle → Efeitos de Vídeo*). Ele fica reenquadrando
  quando você se mexe, o que parece tremedeira no layout Lateral.
- **Use cabo** (USB-C / Lightning) em sessões longas: vídeo mais estável e o iPhone carrega.
- **Com o iPhone em pé**, a imagem vertical encaixa no layout Lateral quase sem corte.
- Modo Retrato e Luz de Estúdio rodam no próprio iPhone: não custam nada pro Mac.

### Várias faixas de áudio

O `.mov` tem uma faixa de áudio por fonte, nesta ordem: **Música → Microfone → Som do Mac**.
O QuickTime toca todas juntas; DaVinci Resolve, Final Cut e Premiere importam como faixas separadas.

## Roadmap

- [ ] Stream ao vivo (RTMP / SRT) reaproveitando o mesmo vídeo codificado do arquivo
- [ ] Atalho global para gravar/parar
- [ ] Escolher quais canais da entrada gravar (interfaces multicanal / devices agregados)
- [ ] Ajuste horizontal do enquadramento da câmera lateral
- [ ] Tamanhos e formatos da bolinha
- [ ] Modo barra de menus e ícone do app
- [ ] Releases assinadas e notarizadas

## Licença

[MIT](LICENSE)
