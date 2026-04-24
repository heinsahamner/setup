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
#
# Avisos
# - Este script APAGA o disco selecionado.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"

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

  if ! have curl; then
    return 0
  fi

  ui_style --foreground 226 "🌐 Verificando conectividade de rede..."
  for ((i = 1; i <= retries; i++)); do
    if curl -fsSL --max-time 5 https://archlinux.org/ >/dev/null 2>&1; then
      ui_style --foreground 82 "✅ Rede OK."
      return 0
    fi
    sleep "$delay"
  done

  ui_style --foreground 214 "⚠️  Rede instável. Continuação com risco de falhas em downloads."
  return 1
}

ensure_gum() {
  if have gum; then
    return 0
  fi
  printf "Gum não encontrado. Instalando...\n"
  pacman -Sy --noconfirm gum >/dev/null 2>&1 || true
}

ui_style() {
  if have gum; then gum style "$@"; else printf '%s\n' "${*: -1}"; fi
}
ui_title() {
  if have gum; then gum style --border double --margin 1 --padding "1 2" --border-foreground "$ACCENT_COLOR" "$@"; else printf '%s\n' "$*"; fi
}
ui_confirm() {
  local prompt="$1"
  if have gum; then 
    gum confirm "$prompt" || return 1
  else 
    read -r -p "$prompt [y/N] " ans && [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
  fi
}

ACCENT_COLOR="212"

usage() {
  cat <<EOF
Uso: $SCRIPT_NAME

Instalador automatizado do Arch Linux (TUI quando disponível).

Notas:
- Este script APAGA o disco selecionado.
- Requer boot em ambiente Arch (pacman, pacstrap, arch-chroot, sfdisk).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

clear
wait_for_network 10 2 || true
ensure_gum
ui_title "Archinst, por heinsahamner"
sleep 1

need_root

require_arch_tools() {
  local missing=()
  for cmd in lsblk sfdisk wipefs mkfs.vfat mkfs.ext4 mkswap swapon mount umount pacstrap genfstab arch-chroot btrfs awk sed blkid findmnt curl; do
    have "$cmd" || missing+=("$cmd")
  done
  ((${#missing[@]} == 0)) || die "Comandos ausentes no ambiente live: ${missing[*]}"
}

require_arch_tools

# ==========================================
# KEYMAP (Corrigido o crash do set -e)
# ==========================================
keymap_choice=""
ui_style --foreground "$ACCENT_COLOR" "Selecione o layout de teclado (keymap):"
if have gum; then
  keymap_choice="$(gum choose "br-abnt2" "br-latin1" "us" "us-intl" "de" "fr" "Outro..." || echo "")"
else
  read -r -p "Keymap (br-abnt2/us/...): " keymap_choice || true
fi

if [[ -z "$keymap_choice" ]]; then
  KEYMAP="us"
elif [[ "$keymap_choice" == "Outro..." ]]; then
  if have gum; then
    KEYMAP="$(gum input --placeholder "Ex: br-abnt2, us, us-intl" || echo "")"
  else
    read -r -p "Keymap: " KEYMAP || true
  fi
else
  KEYMAP="$keymap_choice"
fi

if [[ -z "$KEYMAP" ]]; then
  KEYMAP="us"
fi

if have loadkeys; then
  loadkeys "$KEYMAP" >/dev/null 2>&1 || ui_style --foreground 214 "⚠️  Keymap '$KEYMAP' não aplicado no live (talvez não exista)."
fi

# ==========================================
# SELEÇÃO DE DISCO (Suporte robusto a VMs)
# ==========================================
choose_disk() {
  ui_style --foreground "$ACCENT_COLOR" "Selecione o disco para instalação:"
  
  # Filtra puramente pela string "disk" e exclui qualquer coisa que comece com "loop"
  local disks
  disks="$(lsblk -d -n -o NAME,SIZE,TYPE | awk '$3=="disk" && $1!~/^loop/ {print $1" "$2}')"
  
  if [[ -z "$disks" ]]; then
    die "Nenhum disco detectado via lsblk."
  fi
  
  local selected
  if have gum; then
    selected="$(printf '%s\n' "$disks" | gum choose || echo "")"
    if [[ -z "$selected" ]]; then die "Nenhum disco selecionado (cancelado)."; fi
  else
    printf '%s\n' "$disks"
    read -r -p "Disco (ex: vda, sda, nvme0n1): " selected
    if [[ -z "$selected" ]]; then die "Nenhum disco selecionado."; fi
  fi
  
  local d
  d="$(awk '{print $1}' <<<"$selected")"
  d="${d#/dev/}" 
  
  if [[ ! -b "/dev/$d" ]]; then
    die "Disco inválido: /dev/$d"
  fi
  echo "$d"
}

disco="$(choose_disk)"

# Coleta de parâmetros de particionamento
ui_style --foreground "$ACCENT_COLOR" "Quantas partições deseja criar?"
if have gum; then
  num_parts="$(gum input --placeholder "Ex: 2, 3, 4..." || echo "")"
else
  read -r -p "Número de partições: " num_parts || true
fi

if [[ ! "$num_parts" =~ ^[0-9]+$ ]]; then
  die "Número de partições inválido."
fi

if (( num_parts < 1 || num_parts > 16 )); then
  die "Número de partições fora do limite (1..16)."
fi

tamanhos=()
tipos_fdisk=()
sistemas_fs=()
pontos_montagem=()

for ((i = 1; i <= num_parts; i++)); do
  clear
  ui_style --border normal --padding "0 1" --border-foreground 75 "Configurando Partição $i de $num_parts"

  ui_style --foreground "$ACCENT_COLOR" "Tamanho da partição (deixe em branco para usar o resto):"
  if have gum; then
    tam="$(gum input --placeholder "Ex: +512M, +20G" || echo "")"
  else
    read -r -p "Tamanho (ex: +512M, +20G ou vazio): " tam || true
  fi
  if [[ -n "$tam" && ! "$tam" =~ ^\+?[0-9]+[KMGTP]?$ ]]; then
    die "Tamanho inválido: $tam"
  fi
  tamanhos+=("$tam")

  ui_style --foreground "$ACCENT_COLOR" "Tipo da Partição:"
  if have gum; then
    t_input="$(gum choose "EFI" "Swap" "Linux" || echo "")"
  else
    read -r -p "Tipo (EFI/Swap/Linux): " t_input || true
  fi
  
  if [[ -z "$t_input" ]]; then
    t_input="Linux"
  fi

  case $t_input in
  "EFI") tipos_fdisk+=("1") ;;
  "Swap") tipos_fdisk+=("19") ;;
  *) tipos_fdisk+=("20") ;;
  esac

  ui_style --foreground "$ACCENT_COLOR" "Sistema de Arquivos:"
  if have gum; then
    fs_input="$(gum choose "FAT32" "SWAP" "Ext4" "Btrfs" || echo "")"
  else
    read -r -p "FS (FAT32/SWAP/Ext4/Btrfs): " fs_input || true
  fi

  if [[ -z "$fs_input" ]]; then
    fs_input="Ext4"
  fi

  case $fs_input in
  "FAT32") fs_code="1" ;;
  "SWAP") fs_code="2" ;;
  "Ext4") fs_code="3" ;;
  "Btrfs") fs_code="4" ;;
  *) die "Sistema de arquivos inválido: $fs_input" ;;
  esac
  sistemas_fs+=("$fs_code")

  if [[ "$fs_code" == "2" ]]; then
    pontos_montagem+=("swap")
  else
    ui_style --foreground "$ACCENT_COLOR" "Ponto de montagem (ex: /, /boot, /home):"
    if have gum; then
      p_mont="$(gum input --placeholder "Ponto de montagem" || echo "")"
    else
      read -r -p "Ponto de montagem: " p_mont || true
    fi
    if [[ -z "$p_mont" ]]; then
      die "Ponto de montagem não fornecido."
    fi
    if [[ "$p_mont" != /* ]]; then
      die "Ponto de montagem deve começar com '/': $p_mont"
    fi
    pontos_montagem+=("$p_mont")
  fi
done

clear
ui_title "Configurações do Sistema"

ui_style --foreground "$ACCENT_COLOR" "Qual a marca da sua CPU?"
if have gum; then
  marca_input="$(gum choose "Intel" "AMD" "Nenhuma/VM" || echo "")"
else
  read -r -p "CPU (Intel/AMD/Nenhuma): " marca_input || true
fi
case "$marca_input" in
"Intel") ucode="intel-ucode" ;;
"AMD") ucode="amd-ucode" ;;
*) ucode="" ;;
esac

ui_style --foreground "$ACCENT_COLOR" "Qual kernel deseja instalar?"
if have gum; then
  kernel_choice="$(gum choose "linux (padrão)" "linux-lts" "linux-zen" || echo "")"
else
  read -r -p "Kernel (linux/linux-lts/linux-zen): " kernel_choice || true
fi

if [[ -z "$kernel_choice" ]]; then
  kernel_choice="linux (padrão)"
fi

case "$kernel_choice" in
  "linux (padrão)")
    KERNEL_PKG="linux"; KERNEL_HEADERS_PKG="linux-headers"; KERNEL_BASENAME="linux" ;;
  "linux-lts"|"lts"|"LTS")
    KERNEL_PKG="linux-lts"; KERNEL_HEADERS_PKG="linux-lts-headers"; KERNEL_BASENAME="linux-lts" ;;
  "linux-zen"|"zen"|"ZEN")
    KERNEL_PKG="linux-zen"; KERNEL_HEADERS_PKG="linux-zen-headers"; KERNEL_BASENAME="linux-zen" ;;
  *) die "Kernel inválido: $kernel_choice" ;;
esac

ui_style --foreground "$ACCENT_COLOR" "Qual deseja que seja seu hostname?"
if have gum; then
  hostname="$(gum input --placeholder "Ex: arch-pc" || echo "")"
else
  read -r -p "Hostname: " hostname || true
fi
if [[ ! "$hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]; then
  die "Hostname inválido."
fi

ui_style --foreground "$ACCENT_COLOR" "Defina a senha do ROOT:"
if have gum; then
  senha_root="$(gum input --password --placeholder "Senha Root" || echo "")"
else
  read -r -s -p "Senha root: " senha_root; echo
fi
if [[ -z "$senha_root" ]]; then
  die "Senha root não pode ser vazia."
fi

ui_style --foreground "$ACCENT_COLOR" "Forneça o nome para o seu usuário comum:"
if have gum; then
  usuario="$(gum input --placeholder "Nome de Usuário" || echo "")"
else
  read -r -p "Usuário: " usuario || true
fi
if [[ ! "$usuario" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  die "Nome de usuário inválido."
fi

ui_style --foreground "$ACCENT_COLOR" "Forneça a senha para o usuário $usuario:"
if have gum; then
  senha_usuario="$(gum input --password --placeholder "Senha do Usuário" || echo "")"
else
  read -r -s -p "Senha do usuário: " senha_usuario; echo
fi
if [[ -z "$senha_usuario" ]]; then
  die "Senha do usuário não pode ser vazia."
fi

ui_style --foreground "$ACCENT_COLOR" "Qual desktop deseja instalar?"
if have gum; then
  desktop_choice="$(gum choose "GNOME" "KDE Plasma" "XFCE" "i3" "Nenhum (somente CLI)" || echo "")"
else
  read -r -p "Desktop (GNOME/KDE/XFCE/i3/Nenhum): " desktop_choice || true
fi

ui_style --foreground "$ACCENT_COLOR" "Qual bootloader deseja instalar?"
if have gum; then
  bootloader_choice="$(gum choose "GRUB" "systemd-boot" "Limine" || echo "")"
else
  read -r -p "Bootloader (GRUB/systemd-boot/Limine): " bootloader_choice || true
fi

if [[ -z "$bootloader_choice" ]]; then
  bootloader_choice="systemd-boot"
fi

ui_style --foreground "$ACCENT_COLOR" "Quais drivers deseja instalar?"
if have gum; then
  driver_choice="$(gum choose "Intel/AMD (Mesa)" "NVIDIA (proprietário)" "NVIDIA (open kernel module)" "VM/VirtualBox" "Nenhum" || echo "")"
else
  read -r -p "Drivers (Mesa/NVIDIA/NVIDIA-open/VM/Nenhum): " driver_choice || true
fi

DRIVER_PKGS=""
case "$driver_choice" in
  "Intel/AMD (Mesa)"|"Mesa") DRIVER_PKGS="mesa vulkan-radeon vulkan-intel libva-mesa-driver" ;;
  "NVIDIA (proprietário)"|"NVIDIA") DRIVER_PKGS="nvidia nvidia-utils nvidia-settings" ;;
  "NVIDIA (open kernel module)"|"NVIDIA-open"|"open") DRIVER_PKGS="nvidia-open nvidia-utils nvidia-settings" ;;
  "VM/VirtualBox"|"VM") DRIVER_PKGS="virtualbox-guest-utils" ;;
  *) DRIVER_PKGS="" ;;
esac

BOOTLOADER_PKGS=""
BOOTLOADER_KIND=""
case "$bootloader_choice" in
  "GRUB") BOOTLOADER_KIND="grub"; BOOTLOADER_PKGS="grub efibootmgr" ;;
  "systemd-boot") BOOTLOADER_KIND="systemd-boot"; BOOTLOADER_PKGS="efibootmgr" ;;
  "Limine") BOOTLOADER_KIND="limine"; BOOTLOADER_PKGS="limine efibootmgr" ;;
  *) die "Bootloader inválido." ;;
esac

DESKTOP_PKGS=""
DM_SERVICE=""
case "$desktop_choice" in
  "GNOME") DESKTOP_PKGS="gnome gnome-extra"; DM_SERVICE="gdm.service" ;;
  "KDE Plasma") DESKTOP_PKGS="plasma kde-applications sddm"; DM_SERVICE="sddm.service" ;;
  "XFCE") DESKTOP_PKGS="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"; DM_SERVICE="lightdm.service" ;;
  "i3") DESKTOP_PKGS="xorg-server xorg-xinit i3-wm i3status i3lock dmenu alacritty"; DM_SERVICE="" ;;
  *) DESKTOP_PKGS=""; DM_SERVICE="" ;;
esac

validate_layout() {
  local has_root=0
  local has_efi=0
  local has_boot=0
  local mp
  for mp in "${pontos_montagem[@]}"; do
    [[ "$mp" == "/" ]] && has_root=1
    [[ "$mp" == "/boot" ]] && has_boot=1
  done
  for ((i = 0; i < num_parts; i++)); do
    if [[ "${tipos_fdisk[i]}" == "1" && "${sistemas_fs[i]}" == "1" ]]; then
      has_efi=1
    fi
  done
  (( has_root == 1 )) || die "Você precisa definir uma partição com ponto de montagem '/'."
  (( has_efi == 1 )) || die "Você precisa de uma partição EFI (tipo EFI + FAT32)."
  (( has_boot == 1 )) || die "Para boot UEFI, monte a partição EFI em '/boot'."
}

validate_layout

clear
ui_style --foreground 220 "Parâmetros coletados. Confirme para aplicar as alterações no disco."
if ! ui_confirm "Confirmar o particionamento de /dev/$disco e formatar AGORA?"; then
  ui_style --foreground 196 "Instalação cancelada."
  exit 0
fi

clear
if have gum; then gum spin --spinner dot --title "[1/5] Limpando assinaturas do disco..." -- sleep 1; else sleep 1; fi
wipefs -a "/dev/$disco" >/dev/null 2>&1

sfdisk_script=$'label: gpt\n'
for ((i = 0; i < num_parts; i++)); do
  case ${tipos_fdisk[i]} in
  1) type_uuid="C12A7328-F81F-11D2-BA4B-00A0C93EC93B" ;;
  19) type_uuid="0657FD6D-A4AB-43C4-84E5-0933C84B4F4F" ;;
  20) type_uuid="0FC63DAF-8483-4772-8E79-3D69D8477DE4" ;;
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
  gum spin --spinner line --title "Particionando disco..." -- sh -c "printf '%s' \"\$0\" | sfdisk \"/dev/$disco\"" "$sfdisk_script" >/dev/null 2>&1
else
  printf '%s' "$sfdisk_script" | sfdisk "/dev/$disco" >/dev/null 2>&1
fi

ui_style --foreground "$ACCENT_COLOR" "[2/5] Formatando e Montando em /mnt..."

get_part_path() {
  local n=$1
  if [[ "$disco" =~ [0-9]$ ]]; then
    echo "/dev/${disco}p${n}"
  else
    echo "/dev/${disco}${n}"
  fi
}

mkdir -p /mnt

has_mountpoint() {
  local needle="$1"
  local mp
  for mp in "${pontos_montagem[@]}"; do
    [[ "$mp" == "$needle" ]] && return 0
  done
  return 1
}

BTRFS_MOUNT_OPTS="noatime,compress=zstd,ssd,space_cache=v2,discard=async"
ROOT_FS_CODE=""
ROOT_PART=""
ROOT_IS_BTRFS="0"

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
      1) mkfs.vfat -F 32 "$part" ;;
      2) mkswap "$part" && swapon "$part" ;;
      3) mkfs.ext4 -F "$part" ;;
      4) mkfs.btrfs -f "$part" ;;
    esac
  fi

  if [[ "${pontos_montagem[i]}" == "/" ]]; then
    ROOT_FS_CODE="${sistemas_fs[i]}"
    ROOT_PART="$part"
    if [[ "${sistemas_fs[i]}" == "4" ]]; then
      ROOT_IS_BTRFS="1"
      mount "$part" /mnt
      btrfs subvolume create /mnt/@ >/dev/null
      if ! has_mountpoint "/home"; then
        btrfs subvolume create /mnt/@home >/dev/null
      fi
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

ui_style --foreground 46 "Estrutura pronta em /mnt!"
lsblk "/dev/$disco"
if have gum; then gum spin --spinner points --title "Analisando estrutura..." -- sleep 2; else sleep 2; fi

if [[ ! -d /mnt/boot ]]; then
  mkdir -p /mnt/boot
fi

if ! mountpoint -q /mnt/boot; then
  die "A partição EFI precisa estar montada em /boot (ponto /boot)."
fi

ui_style --foreground "$ACCENT_COLOR" "[3/5] Iniciando o pacstrap. Isso pode demorar um pouco..."
sleep 2

pacotes=(base base-devel git sudo "$KERNEL_PKG" "$KERNEL_HEADERS_PKG" linux-firmware dosfstools mtools networkmanager nano neovim reflector rsync doas wget curl)
for fs in "${sistemas_fs[@]}"; do
  [[ "$fs" == "4" ]] && pacotes+=(btrfs-progs)
done
[[ -n "$ucode" ]] && pacotes+=("$ucode")

if [[ -n "$DRIVER_PKGS" ]]; then
  # shellcheck disable=SC2206
  pacotes+=($DRIVER_PKGS)
fi

if [[ -n "$BOOTLOADER_PKGS" ]]; then
  # shellcheck disable=SC2206
  pacotes+=($BOOTLOADER_PKGS)
fi

pacstrap -K /mnt "${pacotes[@]}"

if have gum; then gum spin --spinner dot --title "Gerando fstab..." -- sh -c "genfstab -U /mnt >> /mnt/etc/fstab"; else genfstab -U /mnt >> /mnt/etc/fstab; fi

ui_style --foreground "$ACCENT_COLOR" "[4/5] Entrando na Matrix (arch-chroot) para configurações finais..."
sleep 3

arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail
sleep 1
echo -e "\e[35m-> Configurando fuso horário...\e[0m"
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc

echo -e "\e[35m-> Configurando layout de teclado (vconsole)...\e[0m"
cat > /etc/vconsole.conf <<VCON
KEYMAP=$KEYMAP
VCON

echo -e "\e[35m-> Configurando idioma...\e[0m"
grep -q "^pt_BR.UTF-8 UTF-8$" /etc/locale.gen || echo "pt_BR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen > /dev/null
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf

echo -e "\e[35m-> Aplicando hostname e usuários...\e[0m"
echo "$hostname" > /etc/hostname
echo "root:$senha_root" | chpasswd
id -u "$usuario" >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash "$usuario"
echo "$usuario:$senha_usuario" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

echo -e "\e[35m-> Habilitando a rede...\e[0m"
systemctl enable NetworkManager > /dev/null 2>&1

echo -e "\e[35m-> Instalando bootloader...\e[0m"
ROOT_DEV=\$(findmnt -no SOURCE /)
ROOT_UUID=\$(blkid -s UUID -o value "\$ROOT_DEV")
ROOT_FSTYPE=\$(findmnt -no FSTYPE /)
VMLINUX="/vmlinuz-$KERNEL_BASENAME"
INITRAMFS="/initramfs-$KERNEL_BASENAME.img"
KERNEL_PARAMS="root=UUID=\$ROOT_UUID rw"
if [[ "$ROOT_IS_BTRFS" == "1" ]]; then
  KERNEL_PARAMS="\$KERNEL_PARAMS rootflags=subvol=@"
fi

case "$BOOTLOADER_KIND" in
  grub)
    echo -e "\e[35m-> Instalando o GRUB...\e[0m"
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB > /dev/null
    grub-mkconfig -o /boot/grub/grub.cfg > /dev/null
    ;;
  systemd-boot)
    echo -e "\e[35m-> Instalando o systemd-boot...\e[0m"
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
      if [[ -f /boot/intel-ucode.img ]]; then
        echo "initrd  /intel-ucode.img"
      elif [[ -f /boot/amd-ucode.img ]]; then
        echo "initrd  /amd-ucode.img"
      fi
      echo "initrd  \$INITRAMFS"
      echo "options \$KERNEL_PARAMS"
    } > /boot/loader/entries/arch.conf
    ;;
  limine)
    echo -e "\e[35m-> Instalando o Limine (UEFI)...\e[0m"
    mkdir -p /boot/EFI/BOOT
    LIMINE_EFI=""
    for p in /usr/share/limine/BOOTX64.EFI /usr/share/limine/limine-uefi/BOOTX64.EFI /usr/lib/limine/BOOTX64.EFI; do
      if [[ -f "\$p" ]]; then
        LIMINE_EFI="\$p"
        break
      fi
    done
    if [[ -z "\$LIMINE_EFI" ]]; then
      echo "Não encontrei o BOOTX64.EFI do Limine no sistema." >&2
      exit 1
    fi
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
    ;;
esac

if [[ -n "$DESKTOP_PKGS" ]]; then
  echo -e "\e[35m-> Instalando Desktop: $desktop_choice...\e[0m"
  pacman -S --noconfirm --needed $DESKTOP_PKGS
  if [[ -n "$DM_SERVICE" ]]; then
    systemctl enable "$DM_SERVICE" > /dev/null 2>&1
  fi
else
  echo -e "\e[35m-> Desktop: nenhum (somente CLI).\e[0m"
fi

echo -e "\e[35m-> Provisionamento do ambiente (env/)...\e[0m"
ENV_BASE_URL="https://raw.githubusercontent.com/heinsahamner/setup/refs/heads/main/env"
ENV_DIR="/opt/heinsahamner-setup/env"

mkdir -p "\$ENV_DIR"
for f in 00_install.sh 01_env_utils.sh 02_aur_engine.sh 03_packages.sh 04_ricing.sh; do
  echo "-> Baixando env/\$f..."
  curl -fsSL -o "\$ENV_DIR/\$f" "\$ENV_BASE_URL/\$f"
  chmod +x "\$ENV_DIR/\$f" || true
done

export SUDO_USER="$usuario"

echo -e "\e[35m-> Executando env/00_install.sh (root, alvo: \$SUDO_USER)...\e[0m"
bash "\$ENV_DIR/00_install.sh"

ln -sf "\$ENV_DIR/00_install.sh" /env-setup.sh
EOF

if have gum; then gum spin --spinner dot --title "[5/5] Finalizando e desmontando..." -- umount -R /mnt; else umount -R /mnt; fi

clear
ui_style \
  --border double \
  --padding "1 2" \
  --margin 1 \
  --foreground 46 \
  --border-foreground 46 \
  "[Sucesso] A instalação do Arch Linux está concluída!"

ui_style "Após reiniciar, rode /env-setup.sh para finalizar a instalação."
ui_style "Digite 'reboot' para iniciar o seu novo sistema."
