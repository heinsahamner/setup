#!/bin/bash
# ==========================================
# env/02_aur_engine.sh — integração com AUR (Arch)
#
# Responsabilidades
# - Criar usuário temporário de build (`aur_builder`) com permissões para compilar pacotes
# - Instalar o helper `yay` quando ausente
# - Expor `aur_install` como wrapper de instalação via AUR
#
# Observações
# - Este módulo é aplicável apenas quando `PM=pacman`.
# ==========================================

# Cria um usuário temporário dedicado à compilação (AUR)
setup_aur_builder() {
  if ! id "aur_builder" &>/dev/null; then
    log_info "Preparando ambiente seguro para o AUR..."

    # Criação do usuário + sudoers dedicado
    ui_spin "Criando usuário temporário 'aur_builder'..." bash -c "
            useradd -m -G wheel aur_builder
            echo 'aur_builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/aur_builder
            chmod 0440 /etc/sudoers.d/aur_builder
        "
    log_success "Usuário 'aur_builder' configurado com sucesso."
  fi
}

# Instala o yay via makepkg usando o usuário construtor
install_yay() {
  # Dependências de compilação
  ui_spin "Verificando dependências de compilação..." \
    pacman -S --needed --noconfirm base-devel git sudo

  if ! command -v yay >/dev/null 2>&1; then
    log_info "Yay não encontrado. Iniciando instalação..."

    rm -rf /tmp/yay-install 2>/dev/null || true

    # Clone do PKGBUILD do yay
    ui_spin "Clonando repositório do yay..." \
      git clone -q https://aur.archlinux.org/yay.git /tmp/yay-install

    chown -R aur_builder:aur_builder /tmp/yay-install

    # A compilação pode levar tempo; manter a saída visível.
    ui_style --foreground 212 "➜ Compilando e instalando yay..."
    sudo -H -u aur_builder bash -c 'cd /tmp/yay-install && makepkg -si --noconfirm'

    rm -rf /tmp/yay-install
    log_success "Yay instalado com sucesso!"
  else
    log_success "Motor Yay já está instalado e pronto para uso."
  fi
}

# Wrapper de instalação via AUR (yay)
aur_install() {
  if command -v yay >/dev/null 2>&1; then
    # Instalação via usuário construtor (evita build como root)
    ui_style --foreground 226 "📦 [AUR] Instalando pacote(s): $*"
    sudo -H -u aur_builder bash -c "yay -S --needed --noconfirm $*"
  else
    log_warn "Motor Yay não encontrado. Pulando a instalação de: $*"
  fi
}

cleanup_aur_builder() {
  log_info "Higienizando o sistema..."

  # Remove sudoers e usuário temporário
  ui_spin "Removendo usuário construtor do AUR..." bash -c "
        rm -f /etc/sudoers.d/aur_builder
        userdel -r aur_builder 2>/dev/null || true
    "
  log_success "Usuário temporário 'aur_builder' removido. Ambiente limpo."
}
