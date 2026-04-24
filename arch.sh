#!/bin/bash
#
# arch.sh — Instalador automatizado do Arch Linux (UEFI)
#
# Objetivo
# - Particionar, formatar e montar o disco em /mnt
# - Instalar o sistema base via pacstrap
# - Configurar o sistema via arch-chroot (locale, vconsole, usuários, rede, bootloader)
# - Provisionar pós-setup baixando e executando os scripts em env/ a partir do repositório
#
# Requisitos
# - Execução em ambiente live do Arch Linux
# - Boot em modo UEFI (ESP montada em /boot)
# - Conectividade de rede para downloads (pacman/curl)

# Usamos 'set -uo pipefail' (sem o -e global) para gerenciar erros interativos manualmente.
# Isso impede que o script feche sozinho se você apertar 'Esc' no menu do gum.
set -uo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
ACCENT_COLOR="212"

# ==========================================
# FUNÇÕES CORE E TUI
# ==========================================

die() {
  local msg="${1:-Erro inesperado}"
  if command -v gum >/dev/null 2>&1; then
    gum style --foreground 196 --bold "❌ $msg"
  else
    printf 'ERRO: %s\n' "$msg" >&2
  fi
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Rode como root."
}

cleanup_mounts() {
  if mountpoint -q /mnt; then
    umount -R /mnt >/dev/null 2>&1 || true
  fi
  swapoff -a >/dev/null 2>&1 || true
}
trap cleanup_mounts EXIT

wait_for_network() {
  local retries="${1:-15}"
  local delay="${2:-2}"

  if ! have curl; then return 0; fi

  ui_style --foreground 226 "🌐 Verificando conectividade de rede..."
  for ((i = 1; i <= retries; i++)); do
    if curl -fsSL --max-time 5 https://archlinux.org/ >/dev/null 2>&1; then
      ui_style --foreground 82 "✅ Rede OK."
      return 0
    fi
    sleep "$delay"
  done
  ui_style --foreground 214 "⚠️ Rede instável. Risco de falhas em downloads."
  return 1
}

ensure_gum() {
  if have gum; then return 0; fi
  printf "Gum não encontrado. Instalando...\n"
  pacman -Sy --noconfirm gum >/dev/null 2>&1 || true
}

require_arch_tools() {
  local missing=()
  for cmd in lsblk sfdisk wipefs mkfs.vfat mkfs.ext4 mkswap swapon mount umount pacstrap genfstab arch-chroot btrfs awk sed blkid findmnt curl; do
    have "$cmd" || missing+=("$cmd")
  done
  ((${#missing[@]} == 0)) || die "Comandos ausentes no ambiente live: ${missing[*]}"
}

ui_style() {
  if have gum; then gum style "$@"; else printf '%s\n' "${*: -1}"; fi
}

ui_title() {
  if have gum; then 
    gum style --border double --margin 1 --padding "1 2" --border-foreground "$ACCENT_COLOR" "$@"
  else 
    printf '\n=== %s ===\n' "$*"
  fi
}

# Wrappers blindados para input (Evita que o script morra ao cancelar)
ask_choice() {
  local prompt="$1"
  local default="$2"
  shift 2
  local result=""

  ui_style --foreground "$ACCENT_COLOR" "$prompt" >&2
  if have gum; then
    result=$(gum choose "$@" 2>/dev/null || echo "")
  else
    read -r -p "Escolha (ex: $1): " result || true
  fi
  [[ -z "$result" ]] && echo "$default" || echo "$result"
}

ask_input() {
  local prompt="$1"
  local default="$2"
  local result=""

  ui_style --foreground "$ACCENT_COLOR" "$prompt" >&2
  if have gum; then
    result=$(gum input --placeholder "Ex: $default" 2>/dev/null || echo "")
  else
    read -r -p "Digite (Padrão: $default): " result || true
  fi
  [[ -z "$result" ]] && echo "$default" || echo "$result"
}

ask_password() {
  local prompt="$1"
  local result=""

  while [[ -z "$result" ]]; do
    ui_style --foreground "$ACCENT_COLOR" "$prompt" >&2
    if have gum; then
      result=$(gum input --password --placeholder "Senha" 2>/dev/null || echo "")
    else
      read -r -s -p "Senha: " result || true
      echo >&2
    fi
  done
  echo "$result"
}

# ==========================================
# INICIALIZAÇÃO
# ==========================================

clear
wait_for_network 10 2 || true
ensure_gum
ui_title "Archinst, por heinsahamner"
sleep 1

need_root
require_arch_tools

# ==========================================
# 1. KEYMAP
# ==========================================
KEYMAP=$(ask_choice "Selecione o layout de teclado (keymap):" "us" "br-abnt2" "br-latin1" "us" "us-intl" "de" "fr" "Outro...")
if [[ "$KEYMAP" == "Outro..." ]]; then
  KEYMAP=$(ask_input "Digite o keymap (ex: es, it):" "us")
fi

if have loadkeys; then
  loadkeys "$KEYMAP" >/dev/null 2>&1 || ui_style --foreground 214 "⚠️ Keymap '$KEYMAP' não aplicado no live, mas será configurado no sistema."
fi

# ==========================================
# 2. SELEÇÃO DE DISCO (Fixo para VM/lsblk)
# ==========================================
ui_style --foreground "$ACCENT_COLOR" "Selecione o disco para instalação:"
# O '-l' garante lista (sem erros de coluna em VM). Exclui loop/CD-ROM.
DISKS_RAW=$(lsblk -d -n -l -o NAME,SIZE,TYPE | awk '$3=="disk" && $1!~/^loop/ && $1!~/^sr/ {print $1" "$2}')

[[ -z "$DISKS_RAW" ]] && die "Nenhum disco físico ou virtual detectado via lsblk."

readarray -t DISKS_ARRAY <<< "$DISKS_RAW"

SELECTED_DISK_STR=$(ask_choice "Atenção: Este disco será APAGADO:" "" "${DISKS_ARRAY[@]}")
[[ -z "$SELECTED_DISK_STR" ]] && die "Instalação cancelada (nenhum disco selecionado)."

disco=$(awk '{print $1}' <<< "$SELECTED_DISK_STR")
[[ -b "/dev/$disco" ]] || die "Disco inválido: /dev/$disco"

# ==========================================
# 3. PARTICIONAMENTO
# ==========================================
num_parts=""
while [[ ! "$num_parts" =~ ^[0-9]+$ ]] || (( num_parts < 1 || num_parts > 16 )); do
  num_parts=$(ask_input "Quantas partições deseja criar? (1 a 16)" "3")
done

tamanhos=()
tipos_fdisk=()
sistemas_fs=()
pontos_montagem=()

for ((i = 1; i <= num_parts; i++)); do
  clear
  ui_style --border normal --padding "0 1" --border-foreground 75 "Configurando Partição $i de $num_parts"

  tam=$(ask_input "Tamanho (ex: +512M, +20G). Vazio para usar o resto:" "")
  if [[ -n "$tam" && ! "$tam" =~ ^\+?[0-9]+[KMGTP]?$ ]]; then
    die "Tamanho inválido: $tam"
  fi
  tamanhos+=("$tam")

  t_input=$(ask_choice "Tipo da Partição:" "Linux" "EFI" "Swap" "Linux")
  case $t_input in
    "EFI") tipos_fdisk+=("1") ;;
    "Swap") tipos_fdisk+=("19") ;;
    *) tipos_fdisk+=("20") ;;
  esac

  fs_input=$(ask_choice "Sistema de Arquivos:" "Ext4" "FAT32" "SWAP" "Ext4" "Btrfs")
  case $fs_input in
    "FAT32") fs_code="1" ;;
    "SWAP") fs_code="2" ;;
    "Ext4") fs_code="3" ;;
    "Btrfs") fs_code="4" ;;
  esac
  sistemas_fs+=("$fs_code")

  if [[ "$fs_code" == "2" ]]; then
    pontos_montagem+=("swap")
  else
    p_mont=""
    while [[ "$p_mont" != /* ]]; do
      p_mont=$(ask_input "Ponto de montagem (Obrigatório começar com /, ex: /boot, /):" "/")
    done
    pontos_montagem+=("$p_mont")
  fi
done

# Validação Layout
has_root=0; has_efi=0; has_boot=0
for mp in "${pontos_montagem[@]}"; do
  [[ "$mp" == "/" ]] && has_root=1
  [[ "$mp" == "/boot" ]] && has_boot=1
done
for ((i = 0; i < num_parts; i++)); do
  [[ "${tipos_fdisk[i]}" == "1" && "${sistemas_fs[i]}" == "1" ]] && has_efi=1
done

(( has_root == 1 )) || die "Partição com ponto de montagem '/' ausente."
(( has_efi == 1 )) || die "Partição EFI (Tipo EFI + FAT32) ausente."
(( has_boot == 1 )) || die "A partição EFI precisa ser montada em '/boot'."

# ==========================================
# 4. CONFIGURAÇÕES DO SISTEMA
# ==========================================
clear
ui_title "Configurações do Sistema"

marca_cpu=$(ask_choice "Qual a marca da sua CPU?" "Nenhuma/VM" "Intel" "AMD" "Nenhuma/VM")
case "$marca_cpu" in
  "Intel") ucode="intel-ucode" ;;
  "AMD") ucode="amd-ucode" ;;
  *) ucode="" ;;
esac

kernel_choice=$(ask_choice "Qual kernel deseja instalar?" "linux" "linux (padrão)" "linux-lts" "linux-zen")
case "$kernel_choice" in
  "linux-lts") KERNEL_PKG="linux-lts"; KERNEL_HEADERS_PKG="linux-lts-headers"; KERNEL_BASENAME="linux-lts" ;;
  "linux-zen") KERNEL_PKG="linux-zen"; KERNEL_HEADERS_PKG="linux-zen-headers"; KERNEL_BASENAME="linux-zen" ;;
  *) KERNEL_PKG="linux"; KERNEL_HEADERS_PKG="linux-headers"; KERNEL_BASENAME="linux" ;;
esac

hostname=""
while [[ ! "$hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]; do
  hostname=$(ask_input "Hostname:" "arch-pc")
done

senha_root=$(ask_password "Defina a senha do ROOT:")

usuario=""
while [[ ! "$usuario" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; do
  usuario=$(ask_input "Nome do usuário comum:" "arch")
done

senha_usuario=$(ask_password "Defina a senha para o usuário $usuario:")

desktop_choice=$(ask_choice "Desktop:" "Nenhum" "GNOME" "KDE Plasma" "XFCE" "i3" "Nenhum (somente CLI)")
bootloader_choice=$(ask_choice "Bootloader:" "systemd-boot" "GRUB" "systemd-boot" "Limine")
driver_choice=$(ask_choice "Drivers de Vídeo:" "Nenhum" "Intel/AMD (Mesa)" "NVIDIA (proprietário)" "NVIDIA (open kernel module)" "VM/VirtualBox" "Nenhum")

DRIVER_PKGS=""
case "$driver_choice" in
  "Intel/AMD (Mesa)") DRIVER_PKGS="mesa vulkan-radeon vulkan-intel libva-mesa-driver" ;;
  "NVIDIA (proprietário)") DRIVER_PKGS="nvidia nvidia-utils nvidia-settings" ;;
  "NVIDIA (open kernel module)") DRIVER_PKGS="nvidia-open nvidia-utils nvidia-settings" ;;
  "VM/VirtualBox") DRIVER_PKGS="virtualbox-guest-utils" ;;
esac

BOOTLOADER_PKGS=""
BOOTLOADER_KIND=""
case "$bootloader_choice" in
  "GRUB") BOOTLOADER_KIND="grub"; BOOTLOADER_PKGS="grub efibootmgr" ;;
  "systemd-boot") BOOTLOADER_KIND="systemd-boot"; BOOTLOADER_PKGS="efibootmgr" ;;
  "Limine") BOOTLOADER_KIND="limine"; BOOTLOADER_PKGS="limine efibootmgr" ;;
esac

DESKTOP_PKGS=""; DM_SERVICE=""
case "$desktop_choice" in
  "GNOME") DESKTOP_PKGS="gnome gnome-extra"; DM_SERVICE="gdm.service" ;;
  "KDE Plasma") DESKTOP_PKGS="plasma kde-applications sddm"; DM_SERVICE="sddm.service" ;;
  "XFCE") DESKTOP_PKGS="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"; DM_SERVICE="lightdm.service" ;;
  "i3") DESKTOP_PKGS="xorg-server xorg-xinit i3-wm i3status i3lock dmenu alacritty"; DM_SERVICE="" ;;
esac

# ==========================================
# 5. APLICAÇÃO E FORMATAÇÃO
# ==========================================
clear
ui_style --foreground 220 "Parâmetros coletados. Confirme para aplicar as alterações."
if have gum; then
  gum confirm "Confirmar particionamento de /dev/$disco e formatar AGORA?" || die "Cancelado."
else
  read -r -p "Proceder? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || die "Cancelado."
fi

clear
if have gum; then gum spin --spinner dot --title "[1/5] Limpando disco..." -- sleep 1; else sleep 1; fi
wipefs -a "/dev/$disco" >/dev/null 2>&1

sfdisk_script=$'label: gpt\n'
for ((i = 0; i < num_parts; i++)); do
  case ${tipos_fdisk[i]} in
    1) type_uuid="C12A7328-F81F-11D2-BA4B-00A0C93EC93B" ;;
    19) type_uuid="0657FD6D-A4AB-43C4-84E5-0933C84B4F4F" ;;
    *) type_uuid="0FC63DAF-8483-4772-8E79-3D69D8477DE4" ;;
  esac
  tam="${tamanhos[i]}"
  if [[ -z "$tam" ]]; then
    sfdisk_script+=$"type=$type_uuid\n"
  else
    tam="${tam#+}"
    sfdisk_script+=$"size=$tam, type=$type_uuid\n"
  fi
done

if have gum; then
  gum spin --spinner line --title "Particionando..." -- sh -c "echo \"\$0\" | sfdisk \"/dev/$disco\"" "$sfdisk_script" >/dev/null 2>&1
else
  echo "$sfdisk_script" | sfdisk "/dev/$disco" >/dev/null 2>&1
fi

ui_style --foreground "$ACCENT_COLOR" "[2/5] Formatando e Montando..."

get_part_path() {
  local n=$1
  if [[ "$disco" =~ [0-9]$ ]]; then echo "/dev/${disco}p${n}"; else echo "/dev/${disco}${n}"; fi
}

mkdir -p /mnt
BTRFS_MOUNT_OPTS="noatime,compress=zstd,ssd,space_cache=v2,discard=async"
ROOT_IS_BTRFS="0"

has_mountpoint() {
  for mp in "${pontos_montagem[@]}"; do [[ "$mp" == "$1" ]] && return 0; done; return 1
}

for ((i = 0; i < num_parts; i++)); do
  part=$(get_part_path $((i + 1)))

  if have gum; then
    gum spin --spinner minidot --title "Formatando $part..." -- sh -c "
      case ${sistemas_fs[i]} in
        1) mkfs.vfat -F 32 \"$part\" ;;
        2) mkswap \"$part\" && swapon \"$part\" ;;
        3) mkfs.ext4 -F \"$part\" ;;
        4) mkfs.btrfs -f \"$part\" ;;
      esac"
  else
    case ${sistemas_fs[i]} in
      1) mkfs.vfat -F 32 "$part" >/dev/null ;;
      2) mkswap "$part" && swapon "$part" ;;
      3) mkfs.ext4 -F "$part" >/dev/null ;;
      4) mkfs.btrfs -f "$part" >/dev/null ;;
    esac
  fi

  if [[ "${pontos_montagem[i]}" == "/" ]]; then
    if [[ "${sistemas_fs[i]}" == "4" ]]; then
      ROOT_IS_BTRFS="1"
      mount "$part" /mnt
      btrfs subvolume create /mnt/@ >/dev/null
      has_mountpoint "/home" || btrfs subvolume create /mnt/@home >/dev/null
      btrfs subvolume create /mnt/@snapshots >/dev/null
      btrfs subvolume create /mnt/@log >/dev/null
      btrfs subvolume create /mnt/@cache >/dev/null
      umount /mnt

      mount -o "$BTRFS_MOUNT_OPTS,subvol=@" "$part" /mnt
      mkdir -p /mnt/.snapshots /mnt/var/log /mnt/var/cache
      mount -o "$BTRFS_MOUNT_OPTS,subvol=@snapshots" "$part" /mnt/.snapshots
      mount -o "$BTRFS_MOUNT_OPTS,subvol=@log" "$part" /mnt/var/log
      mount -o "$BTRFS_MOUNT_OPTS,subvol=@cache" "$part" /mnt/var/cache
      if ! has_mountpoint "/home"; then
        mkdir -p /mnt/home
        mount -o "$BTRFS_MOUNT_OPTS,subvol=@home" "$part" /mnt/home
      fi
    else
      mount "$part" /mnt
    fi
  fi
done

for ((i = 0; i < num_parts; i++)); do
  ponto="${pontos_montagem[i]}"
  part=$(get_part_path $((i + 1)))
  if [[ "$ponto" != "/" && "$ponto" != "swap" && -n "$ponto" ]]; then
    mkdir -p "/mnt${ponto}"
    mount "$part" "/mnt${ponto}"
  fi
done

ui_style --foreground 46 "Estrutura montada!"
lsblk "/dev/$disco"
sleep 2

# ==========================================
# 6. INSTALAÇÃO BASE
# ==========================================
ui_style --foreground "$ACCENT_COLOR" "[3/5] Instalando pacotes base via pacstrap..."

pacotes=(base base-devel git sudo "$KERNEL_PKG" "$KERNEL_HEADERS_PKG" linux-firmware dosfstools mtools networkmanager nano neovim reflector rsync doas wget curl)
[[ "$ROOT_IS_BTRFS" == "1" ]] && pacotes+=(btrfs-progs)
[[ -n "$ucode" ]] && pacotes+=("$ucode")
[[ -n "$DRIVER_PKGS" ]] && pacotes+=($DRIVER_PKGS)
[[ -n "$BOOTLOADER_PKGS" ]] && pacotes+=($BOOTLOADER_PKGS)

pacstrap -K /mnt "${pacotes[@]}"

if have gum; then 
  gum spin --spinner dot --title "Gerando fstab..." -- sh -c "genfstab -U /mnt >> /mnt/etc/fstab"
else 
  genfstab -U /mnt >> /mnt/etc/fstab
fi

# ==========================================
# 7. CHROOT CONFIG
# ==========================================
ui_style --foreground "$ACCENT_COLOR" "[4/5] Configurando sistema (arch-chroot)..."
sleep 2

arch-chroot /mnt /bin/bash <<EOF
set -uo pipefail

echo -e "\e[35m-> Configurando fuso horário...\e[0m"
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc

echo -e "\e[35m-> Configurando teclado e idioma...\e[0m"
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
grep -q "^pt_BR.UTF-8 UTF-8$" /etc/locale.gen || echo "pt_BR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen > /dev/null
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf

echo -e "\e[35m-> Aplicando hostname e usuários...\e[0m"
echo "$hostname" > /etc/hostname
echo "root:$senha_root" | chpasswd
useradd -m -G wheel -s /bin/bash "$usuario"
echo "$usuario:$senha_usuario" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

systemctl enable NetworkManager > /dev/null 2>&1

echo -e "\e[35m-> Instalando bootloader...\e[0m"
ROOT_DEV=\$(findmnt -no SOURCE /)
ROOT_UUID=\$(blkid -s UUID -o value "\$ROOT_DEV")
VMLINUX="/vmlinuz-$KERNEL_BASENAME"
INITRAMFS="/initramfs-$KERNEL_BASENAME.img"

KERNEL_PARAMS="root=UUID=\$ROOT_UUID rw"
if [[ "$ROOT_IS_BTRFS" == "1" ]]; then
  KERNEL_PARAMS="\$KERNEL_PARAMS rootflags=subvol=@"
fi

case "$BOOTLOADER_KIND" in
  grub)
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB > /dev/null
    grub-mkconfig -o /boot/grub/grub.cfg > /dev/null
    ;;
  systemd-boot)
    bootctl --path=/boot install > /dev/null
    mkdir -p /boot/loader/entries
    cat > /boot/loader/loader.conf <<LOADER
default arch.conf
timeout 3
console-mode max
editor no
LOADER
    {
      echo "title   Arch Linux ($KERNEL_BASENAME)"
      echo "linux   \$VMLINUX"
      [[ -f /boot/intel-ucode.img ]] && echo "initrd  /intel-ucode.img"
      [[ -f /boot/amd-ucode.img ]] && echo "initrd  /amd-ucode.img"
      echo "initrd  \$INITRAMFS"
      echo "options \$KERNEL_PARAMS"
    } > /boot/loader/entries/arch.conf
    ;;
  limine)
    mkdir -p /boot/EFI/BOOT
    LIMINE_EFI=""
    for p in /usr/share/limine/BOOTX64.EFI /usr/share/limine/limine-uefi/BOOTX64.EFI /usr/lib/limine/BOOTX64.EFI; do
      [[ -f "\$p" ]] && LIMINE_EFI="\$p" && break
    done
    if [[ -n "\$LIMINE_EFI" ]]; then
      cp -f "\$LIMINE_EFI" /boot/EFI/BOOT/BOOTX64.EFI
      cat > /boot/limine.conf <<LIMINE
TIMEOUT=3
DEFAULT_ENTRY=Arch

:Arch
    PROTOCOL=linux
    KERNEL_PATH=boot:///\${VMLINUX#/}
    MODULE_PATH=boot:///\${INITRAMFS#/}
    CMDLINE=\$KERNEL_PARAMS
LIMINE
      if [[ -f /boot/intel-ucode.img ]]; then
        sed -i "s|^    MODULE_PATH=boot:///\${INITRAMFS#/}\$|    MODULE_PATH=boot:///intel-ucode.img\\n    MODULE_PATH=boot:///\${INITRAMFS#/}|" /boot/limine.conf
      elif [[ -f /boot/amd-ucode.img ]]; then
        sed -i "s|^    MODULE_PATH=boot:///\${INITRAMFS#/}\$|    MODULE_PATH=boot:///amd-ucode.img\\n    MODULE_PATH=boot:///\${INITRAMFS#/}|" /boot/limine.conf
      fi
    else
      echo "Aviso: Binário Limine EFI não encontrado." >&2
    fi
    ;;
esac

if [[ -n "$DESKTOP_PKGS" ]]; then
  echo -e "\e[35m-> Instalando Desktop...\e[0m"
  pacman -S --noconfirm --needed $DESKTOP_PKGS > /dev/null
  [[ -n "$DM_SERVICE" ]] && systemctl enable "$DM_SERVICE" > /dev/null 2>&1
fi

echo -e "\e[35m-> Provisionamento (env/)...\e[0m"
ENV_BASE_URL="https://raw.githubusercontent.com/heinsahamner/setup/refs/heads/main/env"
ENV_DIR="/opt/heinsahamner-setup/env"
mkdir -p "\$ENV_DIR"

for f in 00_install.sh 01_env_utils.sh 02_aur_engine.sh 03_packages.sh 04_ricing.sh; do
  curl -fsSL -o "\$ENV_DIR/\$f" "\$ENV_BASE_URL/\$f" || true
  chmod +x "\$ENV_DIR/\$f" || true
done

export SUDO_USER="$usuario"
if [[ -f "\$ENV_DIR/00_install.sh" ]]; then
  bash "\$ENV_DIR/00_install.sh" || true
  ln -sf "\$ENV_DIR/00_install.sh" /env-setup.sh
fi
EOF

if have gum; then gum spin --spinner dot --title "[5/5] Finalizando..." -- umount -R /mnt; else umount -R /mnt; fi

clear
ui_style --border double --padding "1 2" --margin 1 --foreground 46 --border-foreground 46 "[Sucesso] A instalação do Arch Linux foi concluída!"
ui_style "Digite 'reboot' para iniciar o seu novo sistema."
