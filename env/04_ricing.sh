#!/bin/bash
# ==========================================
# 4. RICING: TEMAS E CONFIGURAÇÕES VISUAIS (TUI via Gum)
# ==========================================

install_lazyvim() {
  if [ ! -d "$TARGET_HOME/.config/nvim/.git" ]; then
    log_info "Configurando Neovim (LazyVim)..."
    # Usamos sudo -u para garantir que os arquivos pertençam ao TARGET_USER
    ui_spin "Baixando e aplicando template LazyVim..." \
      sudo -H -u "$TARGET_USER" bash -c '
            mv ~/.config/nvim ~/.config/nvim.bak 2>/dev/null || true
            mv ~/.local/share/nvim ~/.local/share/nvim.bak 2>/dev/null || true
            git clone -q https://github.com/LazyVim/starter ~/.config/nvim
            rm -rf ~/.config/nvim/.git
        '
    log_success "LazyVim configurado!"
  else
    ui_style --foreground 245 "⏭️  LazyVim já configurado. Pulando..."
  fi
}

install_themes_and_cursors() {
  log_info "Instalando tema GTK Orchis e cursor Bibata..."
  if [ "$PM" = "pacman" ]; then
    aur_install bibata-cursor-theme orchis-theme
  else
    ui_spin "Baixando temas do GitHub e extraindo..." \
      sudo -H -u "$TARGET_USER" bash -c '
            mkdir -p ~/.icons ~/.themes
            if [ ! -d "$HOME/.icons/Bibata-Modern-Classic" ]; then
                wget -qO /tmp/Bibata.tar.gz "https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata.tar.gz"
                tar -xzf /tmp/Bibata.tar.gz -C ~/.icons/
            fi
            if [ ! -d "$HOME/.themes/Orchis-Dark" ]; then
                git clone -q https://github.com/vinceliuice/Orchis-theme.git /tmp/orchis
                /tmp/orchis/install.sh -t all -m -d ~/.themes >/dev/null 2>&1
            fi
        '
    log_success "Tema Orchis e Cursor Bibata instalados."
  fi
}

install_oh_my_zsh() {
  if [ ! -d "$TARGET_HOME/.oh-my-zsh" ]; then
    log_info "Instalando Oh My Zsh..."
    ui_spin "Baixando framework Oh My Zsh..." \
      sudo -H -u "$TARGET_USER" bash -c '
            export RUNZSH=no
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        '
    log_success "Oh My Zsh instalado!"
  else
    ui_style --foreground 245 "⏭️  Oh My Zsh já instalado. Pulando..."
  fi
}

install_zsh_plugins() {
  log_info "Sincronizando plugins Zsh..."
  ui_spin "Clonando P10k, Autosuggestions e Syntax-Highlighting..." \
    sudo -H -u "$TARGET_USER" bash -c '
        ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
        [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ] && git clone -q --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
        [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && git clone -q https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
        [ ! -d "$ZSH_CUSTOM/plugins/fast-syntax-highlighting" ] && git clone -q https://github.com/zdharma-continuum/fast-syntax-highlighting "$ZSH_CUSTOM/plugins/fast-syntax-highlighting"
    '
  log_success "Plugins Zsh prontos."
}

install_fonts() {
  log_info "Verificando fontes MesloLGS NF..."
  ui_spin "Baixando fontes e atualizando cache (fc-cache)..." \
    sudo -H -u "$TARGET_USER" bash -c '
        mkdir -p "$HOME/.local/share/fonts"
        cd "$HOME/.local/share/fonts"
        fonts=("Regular" "Bold" "Italic" "Bold%20Italic")
        for f in "${fonts[@]}"; do
            file="MesloLGS NF ${f//%20/ }.ttf"
            [ ! -f "$file" ] && curl -sL -o "$file" "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20$f.ttf"
        done
        fc-cache -f >/dev/null 2>&1
    '
  log_success "Fontes configuradas."
}

setup_kitty() {
  log_info "Configurando terminal Kitty (Catppuccin Neon)..."
  sudo -H -u "$TARGET_USER" bash -c '
        mkdir -p ~/.config/kitty
        cat > ~/.config/kitty/kitty.conf <<EOF
font_family MesloLGS NF
font_size 16
window_padding_width 0
hide_window_decorations yes
background_opacity 0.90
dynamic_background_opacity yes

# Catppuccin Mocha modificado Neon
foreground #F0F8FF
background #000000
selection_background #585b70
color0 #2b2448
color1 #ff1f7a
color2 #00ff72
color3 #fff700
color4 #1e90ff
color5 #ff3cff
color6 #00f7f7
color7 #d4bfff
copy_on_select yes
EOF
    '
  log_success "Kitty configurado."
}

install_extra_terminals() {
  # Terminais extras são opcionais; este helper tenta instalar sem quebrar o fluxo.
  local pkgs=("$@")
  local p
  for p in "${pkgs[@]}"; do
    if is_pkg_installed "$p"; then
      ui_style --foreground 245 "⏭️  Já instalado: $p"
    else
      ui_style --foreground 212 "➜ Instalando: $p"
      pm_install "$p" || log_warn "Falha ao instalar $p (pode não existir no repositório dessa distro)."
    fi
  done
}

setup_kitty_extra_themes() {
  # Mantém o kitty.conf atual intacto (padrão) e só disponibiliza temas extras.
  log_info "Instalando temas extras para Kitty (sem alterar o padrão)..."
  sudo -H -u "$TARGET_USER" bash -c '
        mkdir -p ~/.config/kitty/themes
        cat > ~/.config/kitty/themes/catppuccin-mocha.conf <<EOF
# Catppuccin Mocha (padrão) - tema alternativo
foreground              #cdd6f4
background              #1e1e2e
selection_foreground    #1e1e2e
selection_background    #f5e0dc
color0                  #45475a
color1                  #f38ba8
color2                  #a6e3a1
color3                  #f9e2af
color4                  #89b4fa
color5                  #f5c2e7
color6                  #94e2d5
color7                  #bac2de
color8                  #585b70
color9                  #f38ba8
color10                 #a6e3a1
color11                 #f9e2af
color12                 #89b4fa
color13                 #f5c2e7
color14                 #94e2d5
color15                 #a6adc8
EOF
    '
  log_success "Tema extra do Kitty disponível em ~/.config/kitty/themes/"
}

setup_alacritty() {
  # Cria um alacritty.toml com import de tema. (Alacritty recente prefere TOML)
  local theme_id="${1:-neon}"
  local theme_file=""
  case "$theme_id" in
    neon) theme_file="neon.toml" ;;
    gruvbox) theme_file="gruvbox-dark.toml" ;;
    *) theme_file="neon.toml" ;;
  esac

  log_info "Configurando Alacritty (tema: $theme_id)..."
  sudo -H -u "$TARGET_USER" bash -c "
        set -e
        mkdir -p \"\$HOME/.config/alacritty/themes\"

        cat > \"\$HOME/.config/alacritty/themes/neon.toml\" <<'EOF'
[colors.primary]
background = \"#000000\"
foreground = \"#F0F8FF\"

[colors.selection]
background = \"#585b70\"
text = \"#000000\"

[colors.normal]
black   = \"#2b2448\"
red     = \"#ff1f7a\"
green   = \"#00ff72\"
yellow  = \"#fff700\"
blue    = \"#1e90ff\"
magenta = \"#ff3cff\"
cyan    = \"#00f7f7\"
white   = \"#d4bfff\"
EOF

        cat > \"\$HOME/.config/alacritty/themes/gruvbox-dark.toml\" <<'EOF'
[colors.primary]
background = \"#282828\"
foreground = \"#ebdbb2\"

[colors.normal]
black   = \"#282828\"
red     = \"#cc241d\"
green   = \"#98971a\"
yellow  = \"#d79921\"
blue    = \"#458588\"
magenta = \"#b16286\"
cyan    = \"#689d6a\"
white   = \"#a89984\"

[colors.bright]
black   = \"#928374\"
red     = \"#fb4934\"
green   = \"#b8bb26\"
yellow  = \"#fabd2f\"
blue    = \"#83a598\"
magenta = \"#d3869b\"
cyan    = \"#8ec07c\"
white   = \"#ebdbb2\"
EOF

        # Se existir config anterior, salva backup uma vez.
        if [ -f \"\$HOME/.config/alacritty/alacritty.toml\" ] && [ ! -f \"\$HOME/.config/alacritty/alacritty.toml.bak\" ]; then
          cp -f \"\$HOME/.config/alacritty/alacritty.toml\" \"\$HOME/.config/alacritty/alacritty.toml.bak\"
        fi

        cat > \"\$HOME/.config/alacritty/alacritty.toml\" <<EOF
import = [\"~/.config/alacritty/themes/$theme_file\"]

[font]
normal = { family = \"MesloLGS NF\" }
size = 16

[window]
opacity = 0.90
padding = { x = 0, y = 0 }
EOF
    "
  log_success "Alacritty configurado."
}

setup_wezterm() {
  local theme_id="${1:-catppuccin}"
  local scheme="Catppuccin Mocha"
  case "$theme_id" in
    catppuccin) scheme="Catppuccin Mocha" ;;
    gruvbox) scheme="Gruvbox Dark" ;;
    *) scheme="Catppuccin Mocha" ;;
  esac

  log_info "Configurando WezTerm (tema: $scheme)..."
  sudo -H -u "$TARGET_USER" bash -c "
        set -e
        mkdir -p \"\$HOME/.config/wezterm\"

        # Backup único
        if [ -f \"\$HOME/.config/wezterm/wezterm.lua\" ] && [ ! -f \"\$HOME/.config/wezterm/wezterm.lua.bak\" ]; then
          cp -f \"\$HOME/.config/wezterm/wezterm.lua\" \"\$HOME/.config/wezterm/wezterm.lua.bak\"
        fi

        cat > \"\$HOME/.config/wezterm/wezterm.lua\" <<'EOF'
local wezterm = require 'wezterm'

return {
  font = wezterm.font('MesloLGS NF'),
  font_size = 16.0,
  window_padding = { left = 0, right = 0, top = 0, bottom = 0 },
  window_background_opacity = 0.90,
  enable_tab_bar = true,
  use_fancy_tab_bar = true,
  color_scheme = '__COLOR_SCHEME__',
}
EOF

        # substitui placeholder sem depender de sed -i GNU/BSD nuances
        tmpfile=\"\$HOME/.config/wezterm/wezterm.lua.tmp\"
        sed \"s/__COLOR_SCHEME__/$scheme/g\" \"\$HOME/.config/wezterm/wezterm.lua\" > \"\$tmpfile\"
        mv -f \"\$tmpfile\" \"\$HOME/.config/wezterm/wezterm.lua\"
    "
  log_success "WezTerm configurado."
}

setup_foot() {
  local theme_id="${1:-neon}"
  local theme_file=""
  case "$theme_id" in
    neon) theme_file="neon.ini" ;;
    gruvbox) theme_file="gruvbox-dark.ini" ;;
    *) theme_file="neon.ini" ;;
  esac

  log_info "Configurando Foot (tema: $theme_id)..."
  sudo -H -u "$TARGET_USER" bash -c "
        set -e
        mkdir -p \"\$HOME/.config/foot/themes\"

        cat > \"\$HOME/.config/foot/themes/neon.ini\" <<'EOF'
[colors]
foreground=F0F8FF
background=000000
selection-foreground=000000
selection-background=585b70

regular0=2b2448
regular1=ff1f7a
regular2=00ff72
regular3=fff700
regular4=1e90ff
regular5=ff3cff
regular6=00f7f7
regular7=d4bfff
EOF

        cat > \"\$HOME/.config/foot/themes/gruvbox-dark.ini\" <<'EOF'
[colors]
foreground=ebdbb2
background=282828

regular0=282828
regular1=cc241d
regular2=98971a
regular3=d79921
regular4=458588
regular5=b16286
regular6=689d6a
regular7=a89984

bright0=928374
bright1=fb4934
bright2=b8bb26
bright3=fabd2f
bright4=83a598
bright5=d3869b
bright6=8ec07c
bright7=ebdbb2
EOF

        # Backup único
        if [ -f \"\$HOME/.config/foot/foot.ini\" ] && [ ! -f \"\$HOME/.config/foot/foot.ini.bak\" ]; then
          cp -f \"\$HOME/.config/foot/foot.ini\" \"\$HOME/.config/foot/foot.ini.bak\"
        fi

        cat > \"\$HOME/.config/foot/foot.ini\" <<EOF
include=~/.config/foot/themes/$theme_file

[main]
font=MesloLGS NF:size=16
pad=0x0
term=xterm-256color
EOF
    "
  log_success "Foot configurado."
}

setup_terminals() {
  # Kitty permanece como padrão e é sempre configurado via setup_kitty (intacto).
  setup_kitty
  setup_kitty_extra_themes

  local OPT_ALACRITTY="Alacritty"
  local OPT_WEZTERM="WezTerm"
  local OPT_FOOT="Foot"
  local choices=""

  if have_gum; then
    ui_style --foreground 226 "Selecione terminais extras para configurar (Kitty já é o padrão):"
    choices="$(gum choose --no-limit "$OPT_ALACRITTY" "$OPT_WEZTERM" "$OPT_FOOT")" || true
  else
    choices=""
  fi

  if printf '%s\n' "$choices" | grep -Fqx "$OPT_ALACRITTY"; then
    install_extra_terminals alacritty

    local theme_choice="Neon (igual Kitty)"
    if have_gum; then
      ui_style --foreground 226 "Selecione tema do Alacritty:"
      theme_choice="$(gum choose "Neon (igual Kitty)" "Gruvbox Dark")"
    fi

    case "$theme_choice" in
      "Gruvbox Dark") setup_alacritty gruvbox ;;
      *) setup_alacritty neon ;;
    esac
  fi

  if printf '%s\n' "$choices" | grep -Fqx "$OPT_WEZTERM"; then
    install_extra_terminals wezterm

    local wez_theme_choice="Catppuccin Mocha"
    if have_gum; then
      ui_style --foreground 226 "Selecione tema do WezTerm:"
      wez_theme_choice="$(gum choose "Catppuccin Mocha" "Gruvbox Dark")"
    fi

    case "$wez_theme_choice" in
      "Gruvbox Dark") setup_wezterm gruvbox ;;
      *) setup_wezterm catppuccin ;;
    esac
  fi

  if printf '%s\n' "$choices" | grep -Fqx "$OPT_FOOT"; then
    # Em algumas distros, foot-terminfo é separado; tentamos também sem quebrar.
    install_extra_terminals foot foot-terminfo

    local foot_theme_choice="Neon (igual Kitty)"
    if have_gum; then
      ui_style --foreground 226 "Selecione tema do Foot:"
      foot_theme_choice="$(gum choose "Neon (igual Kitty)" "Gruvbox Dark")"
    fi

    case "$foot_theme_choice" in
      "Gruvbox Dark") setup_foot gruvbox ;;
      *) setup_foot neon ;;
    esac
  fi
}

setup_terminal_font() {
  # Suporte legado pro alacritty caso o usuário instale depois
  sudo -H -u "$TARGET_USER" bash -c '
        mkdir -p ~/.config/alacritty
        touch ~/.config/alacritty/alacritty.yml
        grep -q "family: MesloLGS NF" ~/.config/alacritty/alacritty.yml || echo -e "font:\n  family: MesloLGS NF" >> ~/.config/alacritty/alacritty.yml
    '
}

generate_zshrc() {
  log_info "Gerando ~/.zshrc robusto e moderno..."

  # Criamos o arquivo na pasta temporaria para injetar variaveis root-level e depois movemos pro usuario
  cat >/tmp/.zshrc_temp <<'EOF'
# =================== heinsahamner env ===================
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
export PATH="$HOME/.local/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
ZSH_THEME="powerlevel10k/powerlevel10k"

zstyle ':omz:update' frequency 13
plugins=(git colored-man-pages npm python pip z web-search fzf sudo extract copyfile copybuffer colorize zsh-autosuggestions fast-syntax-highlighting)
source $ZSH/oh-my-zsh.sh

# Melhorias de UX com ferramentas modernas
eval "$(zoxide init zsh)"
alias cd="z"
alias ls="eza --icons --group-directories-first"
alias ll="eza -lh --icons --group-directories-first --git"
alias cat="bat --style=plain"
alias find="fd"

alias pereça="sudo shutdown now"
alias renasça="sudo reboot"
alias I="btop"
alias df="duf"

alias editzsh="nano ~/.zshrc"
alias updzsh="source ~/.zshrc"
alias kitcon="nano ~/.config/kitty/kitty.conf"
alias venv="python3 -m venv .venv && source .venv/bin/activate"

EOF

  # Adiciona comandos dinâmicos dependentes da Distro
  cat >>/tmp/.zshrc_temp <<EOF
alias upd="${ZSH_UPD}"
alias rem="${ZSH_REM}"
alias search="${ZSH_SEARCH}"
inst() { ${ZSH_INST_FUNC} }
EOF

  cat >>/tmp/.zshrc_temp <<'EOF'
ytm() { yt-dlp -x --audio-format mp3 --audio-quality 0 --embed-thumbnail --add-metadata -o "%(title)s.%(ext)s" "$@"; }
ytv() { yt-dlp -f "bv*+ba/b" --merge-output-format mp4 -o "%(title)s.%(ext)s" "$@"; }
mkd() { mkdir -p "$1" && cd "$1"; }

ftext() {
    rg --line-number --column --color=always "$1" | fzf --ansi --preview 'bat --style=numbers --color=always --highlight-line {2} {1}'
}

# Inicializações Finais
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF

  # Move para o diretório do alvo e ajusta posse
  mv /tmp/.zshrc_temp "$TARGET_HOME/.zshrc"
  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.zshrc"

  # Destaca a criação do arquivo principal de configuração
  ui_style \
    --foreground 82 --border-foreground 82 --border rounded \
    --margin "1 0" --padding "0 1" \
    "🎉 ZSHRC Gerado com Sucesso" \
    "Aliases da distro, Zoxide, Eza e plugins injetados no perfil de $TARGET_USER!"
}
