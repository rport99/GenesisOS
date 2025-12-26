#!/bin/bash
set -euo pipefail
umask 022

# Locale / timezone
sed -i 's/#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
locale-gen
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Root account
usermod -s /usr/bin/bash root || true
cp -aT /etc/skel/ /root/ || true
chmod 750 /root || true
passwd -d root || true

# ---- Ensure liveuser exists ----
if ! id -u liveuser >/dev/null 2>&1; then
  useradd -m -G "adm,audio,floppy,log,network,rfkill,scanner,storage,optical,power,wheel" -s /bin/bash liveuser
fi

# Home ownership
mkdir -p /home/liveuser
chown -R liveuser:liveuser /home/liveuser

# Autologin groups
getent group autologin >/dev/null 2>&1 || groupadd -r autologin
getent group nopasswdlogin >/dev/null 2>&1 || groupadd -r nopasswdlogin
gpasswd -a liveuser autologin || true
gpasswd -a liveuser nopasswdlogin || true

# Sudo (you probably want NOPASSWD on a live ISO; keep ALL if you prefer)
if ! grep -qE '^liveuser\s' /etc/sudoers; then
  echo "liveuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# Enable services (only enable what actually exists)
for svc in thermald haveged NetworkManager sshd bluetooth lightdm cups; do
  systemctl enable "${svc}.service" 2>/dev/null || true
done
systemctl enable pacman-init.service choose-mirror.service 2>/dev/null || true
systemctl set-default graphical.target 2>/dev/null || true

# Permissions
chmod 750 /etc/sudoers.d || true
chmod 440 /etc/sudoers.d/g_wheel 2>/dev/null || true
chown -R root:root /etc/sudoers.d || true
chmod 755 / || true

# SSH allow root (live env)
sed -i 's/#\(PermitRootLogin \).\+/\1yes/' /etc/ssh/sshd_config || true

# Mirrors / journald / logind tweaks
sed -i "s/^#Server/Server/g" /etc/pacman.d/mirrorlist || true
sed -i 's/#\(Storage=\)auto/\1volatile/' /etc/systemd/journald.conf || true

sed -i 's/#\(HandleSuspendKey=\)suspend/\1ignore/' /etc/systemd/logind.conf || true
sed -i 's/#\(HandleHibernateKey=\)hibernate/\1ignore/' /etc/systemd/logind.conf || true
sed -i 's/#\(HandleLidSwitch=\)suspend/\1ignore/' /etc/systemd/logind.conf || true

# ---- NetworkManager config FIX ----
# you had a typo writing to /etc/NetworkManager.conf
mkdir -p /etc/NetworkManager
{
  echo ""
  echo "[device]"
  echo "wifi.scan-rand-mac-address=no"
} >> /etc/NetworkManager/NetworkManager.conf

# Pacman keys (live ISO)
pacman-key --init || true
pacman-key --populate || true

# Stop lightdm user from expiring
chage -E -1 lightdm 2>/dev/null || true

xdg-user-dirs-update --force || true

# Backgrounds
mkdir -p /usr/share/backgrounds/xfce
cp -af /usr/share/backgrounds/*.* /usr/share/backgrounds/xfce 2>/dev/null || true

# tmp ownership
chown -R liveuser:liveuser /tmp || true

# Plymouth
plymouth-set-default-theme stormos 2>/dev/null || true

# Boost symlink (only if both versions are relevant)
if [[ -e /usr/lib/libboost_python313.so.1.89.0 ]] && [[ ! -e /usr/lib/libboost_python313.so.1.88.0 ]]; then
  ln -svf /usr/lib/libboost_python313.so.1.89.0 /usr/lib/libboost_python313.so.1.88.0
fi

# ---- IMPORTANT: avoid EFI FAT "Disk full" ----
# Remove fallback initramfs (they bloat efiboot.img)
rm -f /boot/initramfs-*-fallback.img /boot/*fallback* 2>/dev/null || true

# ---- Installer compatibility: provide vmlinuz-linux path ----
if [[ -e /boot/vmlinuz-linux-zen ]] && [[ ! -e /boot/vmlinuz-linux ]]; then
  cp -a /boot/vmlinuz-linux-zen /boot/vmlinuz-linux
fi
if [[ -e /boot/initramfs-linux-zen.img ]] && [[ ! -e /boot/initramfs-linux.img ]]; then
  cp -a /boot/initramfs-linux-zen.img /boot/initramfs-linux.img
fi
