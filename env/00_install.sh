#!/bin/bash
# ===============================================================
# env/00_install.sh — Orquestrador do provisionamento do ambiente
#
# Responsabilidades
# - Detectar gerenciador de pacotes e usuário alvo (TARGET_USER/TARGET_HOME)
# - Executar módulos de instalação (base, AUR, extras, ricing) de forma idempotente
# - Preferir TUI via gum quando disponível e com TTY; caso contrário usar fallback
#
# Requisitos
# - Execução como root (sudo)
# ===============================================================
# set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Módulos (utils primeiro para UI/logs e fallback do gum)
source "$SCRIPT_DIR/01_env_utils.sh"
ensure_gum || true

# Pré-condição: root
if [ "$EUID" -ne 0 ]; then
  ui_style \
    --foreground 196 --border-foreground 196 --border double \
    --margin "1 2" --padding "1 2" \
    "❌ ERRO CRÍTICO" "Este script precisa ser executado como root (sudo)."
  exit 1
fi

source "$SCRIPT_DIR/02_aur_engine.sh"
source "$SCRIPT_DIR/03_packages.sh"
source "$SCRIPT_DIR/04_ricing.sh"

# Identificação / cabeçalho
clear
ui_style \
  --foreground 212 --border-foreground 212 --border double \
  --align center --width 60 --margin "1 2" --padding "1 2" \
  "🚀 Heinsahamner Env Setup" "Instalação Robusta e Automatizada"

ui_style --foreground 82 "⚙️ Detectando ambiente..."
detect_package_manager
detect_target_user
ui_style --foreground 75 "✅ Gerenciador: $PM | Usuário alvo: $TARGET_USER"
echo ""

# Seleção de etapas (interativo quando possível)
OPT_BASE="1. 📦 Pacotes Base e Atualização"
OPT_AUR="2. 🛠️  Motor AUR (Apenas Arch)"
OPT_EXTRA="3. 🧰 Ferramentas Extras (VSCode/Ventoy/NVM)"
OPT_RICE="4. 🎨 Ricing e Configurações (ZSH/LazyVim/Kitty)"

ui_style --foreground 226 "Selecione as etapas que deseja executar:"
echo -e "Use [Espaço] para marcar/desmarcar e [Enter] para confirmar.\n"

if have_gum; then
  CHOICES=$(gum choose --no-limit \
    --selected="$OPT_BASE,$OPT_AUR,$OPT_EXTRA,$OPT_RICE" \
    "$OPT_BASE" "$OPT_AUR" "$OPT_EXTRA" "$OPT_RICE")
else
  # Fallback sem TUI: executa todas as etapas
  CHOICES="$OPT_BASE"$'\n'"$OPT_AUR"$'\n'"$OPT_EXTRA"$'\n'"$OPT_RICE"
fi

# Caso nenhuma etapa seja selecionada, encerra sem erro
if [ -z "$CHOICES" ]; then
  ui_style --foreground 196 "Nenhuma etapa selecionada. Operação cancelada."
  exit 0
fi

# Confirmação final (somente em modo interativo)
if have_gum; then
  gum confirm "Iniciar a instalação com os módulos selecionados?" || exit 0
fi
clear

# Execução por etapa

# Etapa 1: atualização + pacotes base
if printf '%s\n' "$CHOICES" | grep -Fqx "$OPT_BASE"; then
  ui_style --background 62 --foreground 232 --bold --padding "0 1" --margin "1 0" " PASSO 1: Atualização e Pacotes Base "
  ui_style --foreground 39 "➜ Atualizando repositórios ($PM)..."
  pm_update || true

  ui_style --foreground 39 "➜ Instalando pacotes essenciais..."
  install_base_packages
fi

# Etapa 2: motor AUR (somente Arch/pacman)
if printf '%s\n' "$CHOICES" | grep -Fqx "$OPT_AUR"; then
  ui_style --background 208 --foreground 232 --bold --padding "0 1" --margin "1 0" " PASSO 2: Setup Motor AUR "
  if [ "$PM" = "pacman" ]; then
    setup_aur_builder
    install_yay
  else
    ui_style --foreground 226 "⚠️ O sistema não usa pacman. Ignorando setup do AUR."
  fi
fi

# Etapa 3: ferramentas extras
if printf '%s\n' "$CHOICES" | grep -Fqx "$OPT_EXTRA"; then
  ui_style --background 35 --foreground 232 --bold --padding "0 1" --margin "1 0" " PASSO 3: Ferramentas Extras "
  install_vscode
  install_ventoy
  install_nvm
  install_ytdlp
  install_flatpak
  install_flatpaks
  install_spotify_launcher
  install_bluetooth
  install_obs_pacman
fi

# Etapa 4: ricing e configurações
if printf '%s\n' "$CHOICES" | grep -Fqx "$OPT_RICE"; then
  ui_style --background 129 --foreground 232 --bold --padding "0 1" --margin "1 0" " PASSO 4: Ricing e Configurações "
  install_lazyvim
  install_themes_and_cursors
  install_oh_my_zsh
  install_zsh_plugins
  install_fonts
  setup_terminals
  generate_zshrc
fi

# Finalização / limpeza
ui_style --background 240 --foreground 232 --bold --padding "0 1" --margin "1 0" " 🧹 FINALIZANDO: Ajustes e Limpeza "

if [ "$PM" = "pacman" ] && printf '%s\n' "$CHOICES" | grep -Fqx "$OPT_AUR"; then
  cleanup_aur_builder || true
fi

# Acerta permissões caso tenham sido criadas pelo root
ui_style --foreground 245 "➜ Ajustando permissões de arquivos para $TARGET_USER..."
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME" 2>/dev/null || true

# Tela de Sucesso renderizada em Markdown
if have_gum; then
  gum format "
# 🎉 Concluído com Sucesso!

A instalação do ambiente **heinsahamner** foi finalizada para o usuário **$TARGET_USER**.

### 💡 Próximos passos:
1. Reinicie seu terminal ou execute \`zsh\` para carregar o novo shell.
2. O visualizador **NeoVim (LazyVim)**, **Kitty** e **Zoxide** já estão prontos para uso!

*Obrigado por usar o instalador!*
"
else
  printf '%s\n' "Concluído com sucesso para o usuário $TARGET_USER."
fi
