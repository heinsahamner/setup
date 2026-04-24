# Pagis Base Setup Scripts

Este diretório contém um conjunto de scripts para **instalar e configurar um Arch Linux do zero** (via ambiente live) e depois **provisionar o ambiente do usuário** (pacotes, ferramentas e ricing) no sistema já instalado.

## Visão geral

- **`arch.sh`**: instalador interativo do Arch (TUI com `gum` quando disponível).
  - Particiona/forma/monta o disco em `/mnt` (suporta **Btrfs com subvolumes**).
  - Executa `pacstrap`, gera `fstab` e configura o sistema via `arch-chroot`.
  - Permite escolher **kernel**, **drivers**, **desktop** e **bootloader** (GRUB / systemd-boot / Limine).
  - Ao final baixa um script de pós-setup para `/env-setup.sh` dentro do sistema instalado.

- **`env/00_install.sh`**: orquestrador do pós-setup do ambiente (TUI com `gum` + fallback).
  - Atualiza repositórios e instala pacotes base.
  - (Arch) Configura motor AUR (`yay`) com usuário temporário.
  - Instala ferramentas extras (VS Code, Ventoy, NVM, yt-dlp, **Flatpak + Flatpaks**, `spotify-launcher` no pacman).
  - Aplica ricing (LazyVim, temas/cursor, Oh My Zsh, plugins, fontes, Kitty, `.zshrc`).

- **`env/01_env_utils.sh`**: utilitários (detecção de distro/PM, logs, fallback do `gum`, helpers).
- **`env/02_aur_engine.sh`**: instalação/uso do `yay` e gerenciamento do usuário `aur_builder`.
- **`env/03_packages.sh`**: instaladores de ferramentas (inclui Flatpak/Flathub e menu de Flatpaks).
- **`env/04_ricing.sh`**: tema/terminal/zsh/lazyvim/fonts e geração de configs.

## Uso recomendado

### 1) Instalação do sistema (ambiente live do Arch)

Execute como root:

```bash
chmod +x arch.sh
sudo ./arch.sh
```

> Atenção: o `arch.sh` **apaga o disco selecionado**.

### 2) Pós-setup do ambiente (no sistema instalado)

Depois do primeiro boot, rode:

```bash
sudo /env-setup.sh
```

Ou, se você estiver usando diretamente os scripts locais:

```bash
cd setup
sudo ./env/00_install.sh
```

## Avisos importantes

- **Perigo de perda de dados**: `arch.sh` particiona e formata o disco escolhido.
- **Root**: a maior parte dos passos precisa de `sudo/root`.
- **Rede**: vários passos baixam pacotes e arquivos da internet (pacman/flatpak/curl/git).

