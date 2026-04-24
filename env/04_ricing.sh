#!/bin/bash
# ==========================================
# env/04_ricing.sh — ricing e configurações do perfil do usuário
#
# Escopo
# - Editor: LazyVim
# - Shell: Oh My Zsh + plugins + .zshrc
# - Visual: temas/cursor, fontes e configurações de terminal
#
# Notas
# - As alterações são aplicadas no usuário alvo (TARGET_USER/TARGET_HOME), não no root.
# ==========================================

install_lazyvim() {
  if [ ! -d "$TARGET_HOME/.config/nvim/.git" ]; then
    log_info "Configurando Neovim (LazyVim)..."
    # Aplica no contexto do usuário alvo.
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
    export RUNZSH=no
    sudo -H -u "$TARGET_USER" bash -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
    log_success "Oh My Zsh instalado!"
  else
    ui_style --foreground 245 "⏭️  Oh My Zsh já instalado. Pulando..."
  fi
}

install_zsh_plugins() {
  local zsh_custom="$TARGET_HOME/.oh-my-zsh/custom"
  
  log_info "Verificando plugins e temas do Zsh..."
  
  [ ! -d "$zsh_custom/themes/powerlevel10k" ] && sudo -H -u "$TARGET_USER" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$zsh_custom/themes/powerlevel10k"
  [ ! -d "$zsh_custom/plugins/zsh-autosuggestions" ] && sudo -H -u "$TARGET_USER" git clone https://github.com/zsh-users/zsh-autosuggestions "$zsh_custom/plugins/zsh-autosuggestions"
  [ ! -d "$zsh_custom/plugins/fast-syntax-highlighting" ] && sudo -H -u "$TARGET_USER" git clone https://github.com/zdharma-continuum/fast-syntax-highlighting "$zsh_custom/plugins/fast-syntax-highlighting"
  
  log_success "Plugins sincronizados."
}

install_fonts() {
  log_info "Baixando fontes MesloLGS NF..."
  local font_dir="$TARGET_HOME/.local/share/fonts"
  sudo -H -u "$TARGET_USER" bash -c "
    mkdir -p \"$font_dir\"
    cd \"$font_dir\"
    fonts=(\"Regular\" \"Bold\" \"Italic\" \"Bold%20Italic\")
    for f in \"\${fonts[@]}\"; do
      file_name=\"MesloLGS NF \${f//%20/ }.ttf\"
      if [ ! -f \"\$file_name\" ]; then
        curl -L -o \"\$file_name\" \"https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20\$f.ttf\"
      fi
    done
    fc-cache -f -v
  "
  log_success "Fontes instaladas e cache atualizado."
}

setup_kitty() {
  log_info "Configurando terminal Kitty (Neon/Cyberpunk)..."
  sudo -H -u "$TARGET_USER" bash -c '
    mkdir -p ~/.config/kitty
    cat > ~/.config/kitty/kitty.conf << '"'"'EOF'"'"'
#    __ ___ __  __
#   / //_(_) /_/ /___ __
#  / ,< / / __/ __/ // /
# /_/|_|_/\__/\__/\_, /
#                /___/
#
# Configuration
font_family                 MesloLGS NF
font_size                   16
bold_font                   auto
italic_font                 auto
bold_italic_font            auto
remember_window_size        yes
cursor_blink_interval       0.5
cursor_stop_blinking_after  1
scrollback_lines            2000
wheel_scroll_min_lines      1
enable_audio_bell           no
window_padding_width        0
hide_window_decorations     yes
confirm_os_window_close     0
selection_foreground        none
selection_background        none
cursor_trail 1

# ==========================================
# JANELA E DECORAÇÃO (Integração GNOME)
# ==========================================

# Forçar a renderização correta em X11
linux_display_server x11

# Melhora a nitidez da fonte em modo de compatibilidade
force_ltr no
disable_ligatures never

# Sincronização vertical (evita que a tela "rasgue" ao dar scroll)
sync_to_monitor yes
shell_integration enabled

# ==========================================
# TRANSPARÊNCIA (Otimizada para Blur my Shell)
# ==========================================
background_opacity 0.90
dynamic_background_opacity yes

# ==========================================
# CORES: CATPPUCCIN MOCHA (Modificado) NEON
# ==========================================
foreground              #F0F8FF
background              #000000
selection_foreground    #cdd6f4
selection_background    #585b70

# URL underline color
url_color               #f5e0dc

# Cores do Kitty - Neon / Cyberpunk
color0  #2b2448   # fundo escuro profundo
color1  #ff1f7a   # rosa neon intenso
color2  #00ff72   # verde elétrico
color3  #fff700   # amarelo neon
color4  #1e90ff   # azul neon vibrante
color5  #ff3cff   # magenta neon
color6  #00f7f7   # turquesa elétrico
color7  #d4bfff   # lilás brilhante

color8  #3f3175   # tom médio escuro
color9  #ff1f7a   # rosa neon
color10 #00ff72  # verde elétrico
color11 #fff700  # amarelo neon
color12 #1e90ff  # azul neon
color13 #ff3cff  # magenta neon
color14 #00f7f7  # turquesa elétrico
color15 #b0a0ff  # lilás brilhante

# ==========================================
# COMPORTAMENTO
# ==========================================

# Copiar ao selecionar com o mouse
copy_on_select yes
EOF
  '
  log_success "Kitty configurado."
}

install_extra_terminals() {
  # Terminais extras são opcionais; falhas não devem interromper o ricing.
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
  # Mantém o kitty.conf padrão intacto e disponibiliza temas extras via arquivos separados.
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
  # Gera alacritty.toml e temas locais (formato TOML).
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

        # Preserva configuração existente (backup único).
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

        # Preserva configuração existente (backup único).
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

        # Substitui placeholder sem depender de sed -i.
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

        # Preserva configuração existente (backup único).
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
  # Kitty é o terminal padrão e é sempre configurado via setup_kitty (sem alterações no tema atual).
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
    # Em algumas distros, foot-terminfo é um pacote separado.
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
  # Compatibilidade: cria/atualiza um alacritty.yml mínimo (legado).
  sudo -H -u "$TARGET_USER" bash -c '
        mkdir -p ~/.config/alacritty
        touch ~/.config/alacritty/alacritty.yml
        grep -q "family: MesloLGS NF" ~/.config/alacritty/alacritty.yml || echo -e "font:\n  family: MesloLGS NF" >> ~/.config/alacritty/alacritty.yml
    '
}

generate_zshrc() {
  log_info "Gerando ~/.zshrc completo..."

  cat > "$TARGET_HOME/.zshrc" << 'EOF'
# =================== heinsahamner env ===================
# Powerlevel10k Instant Prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Variáveis Globais
export ZSH="$HOME/.oh-my-zsh"
export PATH="$HOME/.local/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
ZSH_THEME="powerlevel10k/powerlevel10k"
HYPHEN_INSENSITIVE="true"

# Configurações do OMZ
zstyle ':omz:plugin:colored-man-pages' line-color 'green'
zstyle ':omz:update' frequency 13

# Plugins
plugins=(
  git colored-man-pages npm node python pip z web-search fzf sudo extract 
  dirhistory copyfile copybuffer colorize zsh-autosuggestions fast-syntax-highlighting
)
source $ZSH/oh-my-zsh.sh

# =================== Aliases ===================
# Navegação
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias -- -="cd -"
alias cdc="cd ~/Codes"
alias cdd="cd ~/Downloads"
alias cdi="cd ~/Imagens"
alias cdconf="cd ~/.config"
alias cdp="cd ~/Pagis"
alias cdm="cd ~/Músicas"
alias cdv="cd ~/Vídeos"

# Listagem (eza)
alias ls="eza --icons --group-directories-first"
alias ll="eza -lh --icons --group-directories-first --git"
alias la="eza -aH --icons --group-directories-first"
alias lt="eza --tree --level=2 --icons"
alias l="ls"

# Sistema e Pacotes
alias pereça="sudo shutdown now"
alias renasça="sudo reboot"
alias durma="systemctl suspend"
alias I="fastfetch"
alias df="duf"
alias usage="du -sh * | sort -h"

# Desenvolvimento e Utils
alias editzsh="nano ~/.zshrc"
alias updzsh="source ~/.zshrc"
alias kitcon="nano ~/.config/kitty/kitty.conf"
alias h="history"
alias py="python3"
alias venv="python3 -m venv .venv && source .venv/bin/activate"

EOF

  cat >> "$TARGET_HOME/.zshrc" << EOF
alias upd="${ZSH_UPD}"
alias rem="${ZSH_REM}"
alias search="${ZSH_SEARCH}"

inst() {
    $ZSH_INST_FUNC
}
EOF

  cat >> "$TARGET_HOME/.zshrc" << 'EOF'

# =================== Funções ===================
ytm() { yt-dlp -x --audio-format mp3 --audio-quality 0 --embed-thumbnail --add-metadata -o "%(title)s.%(ext)s" "$@"; }
ytv() { yt-dlp -f "bv*+ba/b" -S "res,ext:mp4:m4a" --merge-output-format mp4 -o "%(title)s.%(ext)s" "$@"; }
mkd() { mkdir -p "$1" && cd "$1"; }
bak() { cp "$1" "$1.bak"; }

ftext() { 
    rg --line-number --column --no-heading --color=always --smart-case "$1" | \
    fzf --ansi --preview 'preview={}; file=$(echo $preview | cut -d: -f1); line=$(echo $preview | cut -d: -f2); bat --style=numbers --color=always --highlight-line $line $file'
}
fo() { 
    local file
    file=$(fzf --preview 'bat --style=numbers --color=always --line-range :500 {}')
    [ -n "$file" ] && ${EDITOR:-nano} "$file"
}
fkill() { 
    local pid
    pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
    [ -n "$pid" ] && echo "$pid" | xargs kill -"${1:-9}"
}

ex() { 
    if [ -f "$1" ]; then 
        case "$1" in 
            *.tar.bz2) tar xjf "$1" ;; 
            *.tar.gz) tar xzf "$1" ;; 
            *.bz2) bunzip2 "$1" ;; 
            *.rar) unrar x "$1" ;; 
            *.gz) gunzip "$1" ;; 
            *.tar) tar xf "$1" ;; 
            *.tbz2) tar xjf "$1" ;; 
            *.tgz) tar xzf "$1" ;; 
            *.zip) unzip "$1" ;; 
            *.Z) uncompress "$1" ;; 
            *.7z) 7z x "$1" ;; 
            *) echo "'$1' não pode ser extraído via ex()" ;; 
        esac
    else 
        echo "'$1' não é um arquivo válido"
    fi
}

# =================== Inits Extras ===================
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF

  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.zshrc"
  log_success ".zshrc configurado!"
}
