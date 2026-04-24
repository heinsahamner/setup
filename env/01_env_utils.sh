#!/bin/bash
# ==========================================
# env/01_env_utils.sh — utilitários compartilhados
#
# Fornece:
# - UI/logs (gum quando disponível e com TTY; fallback texto caso contrário)
# - Detecção de usuário alvo (TARGET_USER/TARGET_HOME)
# - Detecção de gerenciador de pacotes e comandos de install/update
# - Helpers: is_pkg_installed, wait_for_network
# ==========================================

# ---------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------
have_gum() {
  command -v gum >/dev/null 2>&1 || return 1
  # gum choose/confirm exigem TTY; em heredoc/pipe a execução deve cair no fallback.
  [ -t 0 ] && [ -t 1 ]
}

ui_style() {
  # usage: ui_style <gum_args...> -- <message>
  if have_gum; then
    gum style "$@"
  else
    # fallback simples: imprime somente o último argumento (mensagem)
    printf '%s\n' "${*: -1}"
  fi
}

ui_spin() {
  # usage: ui_spin <title> -- <command...>
  local title="$1"
  shift
  if have_gum; then
    gum spin --spinner dot --title "$title" -- "$@"
  else
    printf '%s\n' "$title"
    "$@"
  fi
}

# Instala gum quando possível.
# Observação: a execução não depende de gum; sem ele o script opera em modo texto.
ensure_gum() {
  if have_gum; then
    return 0
  fi

  if command -v pacman >/dev/null 2>&1; then
    pacman -S --needed --noconfirm gum >/dev/null 2>&1 || true
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y gum >/dev/null 2>&1 || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y gum >/dev/null 2>&1 || true
  fi
}

# Variáveis legadas (ANSI). Mantidas para compatibilidade.
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logs (UI-agnostic)
log_info() {
  ui_style --foreground 39 "🔹 $1"
}

log_success() {
  ui_style --foreground 82 "✅ $1"
}

log_warn() {
  ui_style --foreground 214 "⚠️  $1"
}

log_error() {
  ui_style --foreground 196 --bold "❌ $1"
}

# ---------------------------------------------------------------
# Rede: checagem básica com tentativas
# ---------------------------------------------------------------
wait_for_network() {
  # usage: wait_for_network [retries] [sleep_seconds]
  local retries="${1:-12}"
  local delay="${2:-2}"

  # Sem curl, não há verificação HTTPs/DNS; assume OK.
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  for ((i = 1; i <= retries; i++)); do
    # DNS + HTTPS
    if curl -fsSL --max-time 5 https://archlinux.org/ >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done

  log_warn "Rede instável/indisponível (tentativas: $retries). Instalações online podem falhar."
  return 1
}

# ---------------------------------------------------------------
# Detecção de usuário alvo
# ---------------------------------------------------------------
detect_target_user() {
  # Evita instalar dotfiles na pasta /root se o script for chamado via sudo
  if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER="$SUDO_USER"
    TARGET_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
  else
    TARGET_USER="root"
    TARGET_HOME="/root"

    # Execução como root puro implica configs em /root.
    ui_style \
      --foreground 214 --border-foreground 214 --border double \
      --margin "1 1" --padding "1 2" \
      "⚠️  ALERTA DE AMBIENTE" \
      "Executando puramente como root." \
      "As configurações de interface e ricing irão para /root."
    sleep 2
  fi
}

# ---------------------------------------------------------------
# Helpers de package manager (arrays; evita eval)
# ---------------------------------------------------------------
pm_update() { "${UPDATE_CMD[@]}"; }
pm_install() { "${INSTALL_CMD[@]}" "$@"; }

is_pkg_installed() {
  local pkg="$1"
  case "${PM:-}" in
    pacman) pacman -Qi "$pkg" >/dev/null 2>&1 ;;
    apt) dpkg -s "$pkg" >/dev/null 2>&1 ;;
    dnf) rpm -q "$pkg" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------
# Detecção do gerenciador de pacotes
# ---------------------------------------------------------------
detect_package_manager() {
  # Adicionado ferramentas modernas: btop, fd, zoxide, tldr
  local BASE_PKGS="zsh git curl wget unzip tar fzf python3 nodejs npm bat ripgrep neovim vlc gparted nemo timeshift gnome-tweaks sassc kitty btop fd-find zoxide tldr jq"

  if command -v pacman >/dev/null 2>&1; then
    PM="pacman"
    INSTALL_CMD=(pacman -S --needed --noconfirm)
    UPDATE_CMD=(pacman -Syu --noconfirm)
    PKGS=(${BASE_PKGS//python3/python} papirus-icon-theme fd) # Arch usa python e fd ao invés de fd-find
    ZSH_UPD="sudo pacman -Syu && ([ -x /usr/bin/yay ] && yay -Sua)"
    ZSH_REM="sudo pacman -Rns"
    ZSH_SEARCH="pacman -Ss"
    ZSH_INST_FUNC="if pacman -Si \"\$1\" &>/dev/null; then sudo pacman -S --needed --noconfirm \"\$1\"; elif command -v yay &>/dev/null; then yay -S --noconfirm \"\$1\"; else if command -v gum &>/dev/null; then gum style --foreground 196 \"❌ Erro: Pacote \$1 não encontrado.\"; else echo \"Erro: Pacote \$1 não encontrado.\"; fi; fi"

  elif command -v apt >/dev/null 2>&1; then
    PM="apt"
    INSTALL_CMD=(apt-get install -y)
    UPDATE_CMD=(apt-get update -y)
    PKGS=($BASE_PKGS)
    ZSH_UPD="sudo apt update && sudo apt upgrade -y"
    ZSH_REM="sudo apt autoremove --purge"
    ZSH_SEARCH="apt search"
    ZSH_INST_FUNC="sudo apt install -y \"\$1\""

  elif command -v dnf >/dev/null 2>&1; then
    PM="dnf"
    INSTALL_CMD=(dnf install -y)
    UPDATE_CMD=(dnf check-update -y)
    PKGS=($BASE_PKGS python3-pip eza duf fastfetch)
    ZSH_UPD="sudo dnf upgrade -y"
    ZSH_REM="sudo dnf autoremove"
    ZSH_SEARCH="dnf search"
    ZSH_INST_FUNC="sudo dnf install -y \"\$1\""
  else
    # Erro fatal formatado com Gum
    ui_style \
      --foreground 196 --border-foreground 196 --border double \
      --margin "1 1" --padding "1 2" \
      "❌ SISTEMA INCOMPATÍVEL" \
      "Sistema não suportado automaticamente." \
      "Este script suporta pacman, apt ou dnf."
    exit 1
  fi
}
