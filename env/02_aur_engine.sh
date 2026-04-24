#!/bin/bash
# ==========================================
# 2. MOTOR DO AUR (Solução Definitiva Root/Makepkg via Gum)
# ==========================================

# Cria um usuário de sistema apenas para compilar pacotes do AUR
setup_aur_builder() {
  if ! id "aur_builder" &>/dev/null; then
    log_info "Preparando ambiente seguro para o AUR..."

    # Usa um spinner do gum para esconder a criação do usuário
    ui_spin "Criando usuário temporário 'aur_builder'..." bash -c "
            useradd -m -G wheel aur_builder
            echo 'aur_builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/aur_builder
            chmod 0440 /etc/sudoers.d/aur_builder
        "
    log_success "Usuário 'aur_builder' configurado com sucesso."
  fi
}

# Instala o yay usando o usuário construtor
install_yay() {
  # Esconde a instalação das dependências base (caso já estejam instaladas)
  ui_spin "Verificando dependências de compilação..." \
    pacman -S --needed --noconfirm base-devel git sudo

  if ! command -v yay >/dev/null 2>&1; then
    log_info "Yay não encontrado. Iniciando instalação..."

    rm -rf /tmp/yay-install 2>/dev/null || true

    # Clone silencioso com spinner
    ui_spin "Clonando repositório do yay..." \
      git clone -q https://aur.archlinux.org/yay.git /tmp/yay-install

    chown -R aur_builder:aur_builder /tmp/yay-install

    # Aqui NÃO usamos spinner porque compilar (makepkg) gera logs importantes
    # e pode demorar. O usuário precisa ver que o sistema não travou.
    gum style --foreground 212 "➜ Compilando e instalando yay (isso pode demorar um pouco)..."
    sudo -H -u aur_builder bash -c 'cd /tmp/yay-install && makepkg -si --noconfirm'

    rm -rf /tmp/yay-install
    log_success "Yay instalado com sucesso!"
  else
    log_success "Motor Yay já está instalado e pronto para uso."
  fi
}

# Wrapper universal: Sempre que precisar instalar um pacote do AUR no script
aur_install() {
  if command -v yay >/dev/null 2>&1; then
    # Destaca visualmente pacotes sendo instalados via AUR
    ui_style --foreground 226 "📦 [AUR] Instalando pacote(s): $*"
    sudo -H -u aur_builder bash -c "yay -S --needed --noconfirm $*"
  else
    log_warn "Motor Yay não encontrado. Pulando a instalação de: $*"
  fi
}

cleanup_aur_builder() {
  log_info "Higienizando o sistema..."

  # Usa um spinner para esconder a deleção do usuário temporário
  ui_spin "Removendo usuário construtor do AUR..." bash -c "
        rm -f /etc/sudoers.d/aur_builder
        userdel -r aur_builder 2>/dev/null || true
    "
  log_success "Usuário temporário 'aur_builder' removido. Ambiente limpo."
}
