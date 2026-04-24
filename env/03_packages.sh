#!/bin/bash
# ==========================================
# env/03_packages.sh — instaladores de pacotes e ferramentas
#
# Escopo
# - Instala pacotes base (detectados via env/01_env_utils.sh)
# - Instala ferramentas opcionais (VS Code, Ventoy, NVM, yt-dlp, Flatpak/Flathub, spotify-launcher)
# - Provisiona serviços quando aplicável (ex.: bluetooth)
# - Mantém idempotência: tenta evitar reinstalações e falhas fatais em itens opcionais
# ==========================================

install_base_packages() {
    log_info "Verificando e instalando pacotes base..."
    
    local installed_count=0
    for pkg in "${PKGS[@]}"; do
        if ! is_pkg_installed "$pkg"; then
            ui_style --foreground 212 "➜ Instalando: $pkg"
            pm_install "$pkg"
            ((installed_count++))
        fi
    done

    if [ "$installed_count" -eq 0 ]; then
        ui_style --foreground 245 "✅ Todos os pacotes base já estavam instalados."
    else
        log_success "$installed_count novos pacotes base instalados."
    fi
}

install_vscode() {
    if command -v code >/dev/null 2>&1; then 
        ui_style --foreground 245 "⏭️  VS Code já instalado. Pulando..."
        return
    fi
    
    log_info "Preparando instalação do VS Code..."
    
    if [ "$PM" = "pacman" ]; then
        aur_install visual-studio-code-bin
    elif [ "$PM" = "apt" ]; then
        ui_spin "Configurando repositórios da Microsoft (APT)..." bash -c '
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >/tmp/packages.microsoft.tmp.gpg
            install -D -o root -g root -m 644 /tmp/packages.microsoft.tmp.gpg /etc/apt/keyrings/packages.microsoft.gpg
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | tee /etc/apt/sources.list.d/vscode.list >/dev/null
            rm -f /tmp/packages.microsoft.tmp.gpg
            apt-get update -y
        '
        ui_style --foreground 212 "➜ Baixando e instalando pacote..."
        apt-get install -y code
        log_success "VS Code instalado."
        
    elif [ "$PM" = "dnf" ]; then
        ui_spin "Configurando repositórios da Microsoft (DNF)..." bash -c '
            rpm --import https://packages.microsoft.com/keys/microsoft.asc
            echo -e "[code]\nname=VS Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | tee /etc/yum.repos.d/vscode.repo >/dev/null
        '
        ui_style --foreground 212 "➜ Baixando e instalando pacote..."
        dnf install -y code
        log_success "VS Code instalado."
    fi
}

install_ventoy() {
    if command -v ventoy >/dev/null 2>&1 || [ -d "/opt/ventoy" ]; then 
        ui_style --foreground 245 "⏭️  Ventoy já instalado. Pulando..."
        return 
    fi
    
    log_info "Instalando Ventoy..."
    wait_for_network 8 2 || true
    
    if [ "$PM" = "pacman" ]; then
        aur_install ventoy-bin
    else
        # Download/extração são operações silenciosas; a UI apresenta progresso.
        ui_spin "Buscando última versão no GitHub, baixando e extraindo..." bash -c '
            vt_tmp=$(mktemp -d)
            latest_url=$(curl -fsSL https://api.github.com/repos/ventoy/Ventoy/releases/latest | jq -r ".assets[] | select(.browser_download_url | test(\"linux.*tar.gz$\")) | .browser_download_url" | head -n1)
            if [ -n "$latest_url" ]; then
                wget -qO "$vt_tmp/ventoy.tar.gz" "$latest_url"
                tar -xzf "$vt_tmp/ventoy.tar.gz" -C /opt/
                mv /opt/ventoy-* /opt/ventoy
                ln -sf /opt/ventoy/VentoyGUI.x86_64 /usr/local/bin/ventoy
            fi
            rm -rf "$vt_tmp"
        '
        if [ -d "/opt/ventoy" ]; then
            log_success "Ventoy instalado em /opt/ventoy"
        else
            log_error "Falha ao baixar/instalar o Ventoy do GitHub."
        fi
    fi
}

install_nvm() {
    if [ ! -d "$TARGET_HOME/.nvm" ]; then
        log_info "Instalando NVM para o usuário $TARGET_USER..."
        wait_for_network 8 2 || true
        ui_spin "Baixando e executando script do NVM..." \
            sudo -H -u "$TARGET_USER" bash -c 'curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.6/install.sh | bash'
        log_success "NVM instalado no perfil de $TARGET_USER."
    else
        ui_style --foreground 245 "⏭️  NVM já presente no perfil do usuário. Pulando..."
    fi
}

install_ytdlp() {
    if ! command -v yt-dlp >/dev/null 2>&1; then
        log_info "Instalando yt-dlp..."
        if [ "$PM" = "pacman" ]; then
            pacman -S --needed --noconfirm yt-dlp
            log_success "yt-dlp instalado."
        else
            wait_for_network 8 2 || true
            ui_spin "Instalando via pip para o usuário $TARGET_USER..." \
                sudo -H -u "$TARGET_USER" bash -c 'python3 -m pip install --user yt-dlp --break-system-packages' || \
                ui_style --foreground 214 --border-foreground 214 --border rounded --padding "0 1" \
                "⚠️ PEP 668: instalação via pip falhou; pode ser necessária ação manual."
            
            [ -x "$TARGET_HOME/.local/bin/yt-dlp" ] && log_success "yt-dlp instalado."
        fi
    else
         ui_style --foreground 245 "⏭️  yt-dlp já instalado. Pulando..."
    fi
}

install_flatpak() {
    if command -v flatpak >/dev/null 2>&1; then
        ui_style --foreground 245 "⏭️  Flatpak já instalado. Pulando..."
    else
        log_info "Instalando Flatpak..."
        pm_install flatpak
        log_success "Flatpak instalado."
    fi

    # Flathub (system-wide).
    if command -v flatpak >/dev/null 2>&1; then
        wait_for_network 8 2 || true
        if ! flatpak remote-list --system 2>/dev/null | awk '{print $1}' | grep -Fxq flathub; then
            ui_spin "Adicionando repositório Flathub (system)..." \
                flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo
            log_success "Flathub adicionado."
        else
            ui_style --foreground 245 "⏭️  Flathub já configurado. Pulando..."
        fi
    fi
}

install_flatpaks() {
    if ! command -v flatpak >/dev/null 2>&1; then
        log_warn "Flatpak não encontrado. Pulando instalação de Flatpaks."
        return
    fi

    log_info "Selecionando Flatpaks essenciais..."
    wait_for_network 8 2 || true

    # Opções de menu -> App IDs (Flathub)
    local OPT_STEAM="Steam"
    local OPT_DISCORD="Discord"
    local OPT_OBSIDIAN="Obsidian"
    local OPT_MISSION_CENTER="Mission Center"
    local OPT_LIBREOFFICE="LibreOffice"
    local OPT_OKULAR="Okular"

    local selected=""
    if have_gum; then
        selected="$(gum choose --no-limit \
            --selected="$OPT_STEAM,$OPT_DISCORD,$OPT_OBSIDIAN,$OPT_MISSION_CENTER,$OPT_LIBREOFFICE,$OPT_OKULAR" \
            "$OPT_STEAM" "$OPT_DISCORD" "$OPT_OBSIDIAN" "$OPT_MISSION_CENTER" "$OPT_LIBREOFFICE" "$OPT_OKULAR")"

        if [[ -z "$selected" ]]; then
            ui_style --foreground 245 "⏭️  Nenhum Flatpak selecionado. Pulando..."
            return
        fi
    else
        # Fallback sem TUI: instala todos
        selected="$OPT_STEAM"$'\n'"$OPT_DISCORD"$'\n'"$OPT_OBSIDIAN"$'\n'"$OPT_MISSION_CENTER"$'\n'"$OPT_LIBREOFFICE"$'\n'"$OPT_OKULAR"
    fi

    log_info "Instalando Flatpaks selecionados..."

    local apps=()
    if printf '%s\n' "$selected" | grep -Fqx "$OPT_STEAM"; then apps+=(com.valvesoftware.Steam); fi
    if printf '%s\n' "$selected" | grep -Fqx "$OPT_DISCORD"; then apps+=(com.discordapp.Discord); fi
    if printf '%s\n' "$selected" | grep -Fqx "$OPT_OBSIDIAN"; then apps+=(md.obsidian.Obsidian); fi
    if printf '%s\n' "$selected" | grep -Fqx "$OPT_MISSION_CENTER"; then apps+=(io.missioncenter.MissionCenter); fi
    if printf '%s\n' "$selected" | grep -Fqx "$OPT_LIBREOFFICE"; then apps+=(org.libreoffice.LibreOffice); fi
    if printf '%s\n' "$selected" | grep -Fqx "$OPT_OKULAR"; then apps+=(org.kde.okular); fi

    # Instalação system-wide (não depende do perfil do usuário).
    for app in "${apps[@]}"; do
        if flatpak info --system "$app" >/dev/null 2>&1; then
            ui_style --foreground 245 "⏭️  Flatpak já instalado: $app"
        else
            ui_style --foreground 212 "➜ Instalando Flatpak: $app"
            flatpak install --system -y --noninteractive flathub "$app" || log_warn "Falha ao instalar $app (verifique rede/Flathub)."
        fi
    done

    log_success "Flatpaks essenciais processados."
}

install_spotify_launcher() {
    if [ "$PM" != "pacman" ]; then
        log_warn "spotify-launcher está configurado aqui apenas para pacman/Arch. Pulando..."
        return
    fi

    if is_pkg_installed spotify-launcher; then
        ui_style --foreground 245 "⏭️  spotify-launcher já instalado. Pulando..."
        return
    fi

    log_info "Instalando spotify-launcher (pacman)..."
    pm_install spotify-launcher
    log_success "spotify-launcher instalado."
}

install_bluetooth() {
    log_info "Instalando Bluetooth..."

    if command -v systemctl >/dev/null 2>&1; then
        case "$PM" in
            pacman) pm_install bluez bluez-utils || true ;;
            apt) pm_install bluez || true ;;
            dnf) pm_install bluez bluez-tools || true ;;
            *) log_warn "Gerenciador não suportado para bluetooth. Pulando..."; return ;;
        esac

        systemctl enable --now bluetooth.service >/dev/null 2>&1 || log_warn "Não foi possível habilitar bluetooth.service automaticamente."
        log_success "Bluetooth processado."
    else
        log_warn "systemctl não encontrado. Pulando enable do Bluetooth."
    fi
}

install_obs_pacman() {
    if [ "$PM" != "pacman" ]; then
        log_warn "OBS via pacman está disponível apenas no Arch. Pulando..."
        return
    fi

    log_info "Instalando OBS Studio (pacman) + plugins..."

    # Instalação resiliente: processa pacote a pacote para reduzir falhas globais.
    local pkgs=(
        obs-studio
        obs-plugin-obs-websocket
        v4l2loopback-dkms
    )

    for p in "${pkgs[@]}"; do
        if is_pkg_installed "$p"; then
            ui_style --foreground 245 "⏭️  Já instalado: $p"
        else
            ui_style --foreground 212 "➜ Instalando: $p"
            pm_install "$p" || log_warn "Falha ao instalar $p (talvez não exista no repo habilitado)."
        fi
    done

    log_success "OBS e plugins processados."
}
