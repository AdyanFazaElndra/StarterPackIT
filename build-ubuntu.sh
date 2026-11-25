#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
WORKDIR="$(pwd)/work"
CHROOT="$WORKDIR/chroot"
IMAGE="$WORKDIR/image"

# 1. Instal alat perakit ISO di server GitHub
apt-get update
apt-get install -y debootstrap squashfs-tools xorriso \
  grub-pc-bin grub-efi-amd64-bin mtools dosfstools

# 2. Unduh sistem dasar Ubuntu 24.04 LTS (Noble)
mkdir -p "$CHROOT" "$IMAGE/casper" "$IMAGE/boot/grub" "$IMAGE/.disk"
debootstrap --arch=amd64 --variant=minbase noble "$CHROOT" http://archive.ubuntu.com/ubuntu/

# 3. Salin daftar paket, wallpaper (jika ada), dan atur DNS
cp packages.txt "$CHROOT/tmp/packages.txt"
if [ -f wallpaper.jpg ]; then
  mkdir -p "$CHROOT/usr/share/backgrounds"
  cp wallpaper.jpg "$CHROOT/usr/share/backgrounds/ti-lite-wallpaper.jpg"
fi

rm -f "$CHROOT/etc/resolv.conf"
echo "nameserver 8.8.8.8" > "$CHROOT/etc/resolv.conf"

cat << 'EOF' > "$CHROOT/etc/apt/sources.list"
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
EOF

# 4. Hubungkan sistem file virtual ke chroot
mount --bind /dev "$CHROOT/dev"
mount --bind /dev/pts "$CHROOT/dev/pts"
mount -t proc proc "$CHROOT/proc"
mount -t sysfs sysfs "$CHROOT/sys"

cleanup() {
  umount -lf "$CHROOT/dev/pts" "$CHROOT/dev" "$CHROOT/proc" "$CHROOT/sys" 2>/dev/null || true
}
trap cleanup EXIT

# 5. Instalasi semua aplikasi & konfigurasi di dalam chroot
chroot "$CHROOT" /bin/bash -e << 'CHROOT_EOF'
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates gnupg curl debconf-utils \
  software-properties-common linux-generic casper systemd-sysv netplan.io

# Hindari prompt interaktif saat instalasi Wireshark
echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections

# Pasang Firefox versi .deb murni (bebas Snap)
add-apt-repository -y ppa:mozillateam/ppa
cat << 'PIN_EOF' > /etc/apt/preferences.d/mozilla-firefox
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
PIN_EOF

apt-get update
apt-get install -y firefox

# Instal seluruh aplikasi dari packages.txt
grep -vE '^\s*(#|$)' /tmp/packages.txt | xargs apt-get install -y

# Instal Visual Studio Code
curl -fL "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" -o /tmp/vscode.deb
apt-get install -y /tmp/vscode.deb

# Instal Free Download Manager (FDM)
curl -fL "https://files2.freedownloadmanager.org/6/latest/freedownloadmanager.deb" -o /tmp/fdm.deb || \
curl -fL "https://dn3.freedownloadmanager.org/6/latest/freedownloadmanager.deb" -o /tmp/fdm.deb
apt-get install -y /tmp/fdm.deb

# Matikan autostart MariaDB agar RAM 4 GB tetap lega
systemctl disable mariadb || true

# Atur Wi-Fi via NetworkManager
mkdir -p /etc/netplan
cat << 'NET_EOF' > /etc/netplan/01-network-manager-all.yaml
network:
  version: 2
  renderer: NetworkManager
NET_EOF

# Aktifkan kompresi RAM zram
mkdir -p /etc/default
cat << 'ZRAM_EOF' > /etc/default/zramswap
ALGO=lz4
PERCENT=50
ZRAM_EOF

# Pasang shortcut FDM langsung di toolbar bawah XFCE
mkdir -p /etc/skel/.config/xfce4/panel/launcher-2
mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml

FDM_DESKTOP=$(find /usr/share/applications -iname '*freedownloadmanager*' -o -iname '*fdm*' | head -n 1 || true)
if [ -n "$FDM_DESKTOP" ]; then
  cp "$FDM_DESKTOP" /etc/skel/.config/xfce4/panel/launcher-2/freedownloadmanager.desktop
else
  cat << 'FDM_EOF' > /etc/skel/.config/xfce4/panel/launcher-2/freedownloadmanager.desktop
[Desktop Entry]
Name=Free Download Manager
Exec=/opt/freedownloadmanager/fdm %U
Icon=/opt/freedownloadmanager/icon.png
Type=Application
Categories=Network;FileTransfer;
FDM_EOF
fi
chmod +x /etc/skel/.config/xfce4/panel/launcher-2/freedownloadmanager.desktop

cat << 'PANEL_EOF' > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="36"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu"/>
    <property name="plugin-2" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="freedownloadmanager.desktop"/>
      </property>
    </property>
    <property name="plugin-3" type="string" value="tasklist"/>
    <property name="plugin-4" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-5" type="string" value="systray"/>
    <property name="plugin-6" type="string" value="pulseaudio"/>
    <property name="plugin-7" type="string" value="clock"/>
    <property name="plugin-8" type="string" value="actions"/>
  </property>
</channel>
PANEL_EOF

# Terapkan wallpaper custom (jika wallpaper.jpg diunggah)
if [ -f /usr/share/backgrounds/ti-lite-wallpaper.jpg ]; then
  mkdir -p /etc/lightdm/lightdm-gtk-greeter.conf.d
  cat << 'LDM_EOF' > /etc/lightdm/lightdm-gtk-greeter.conf.d/99-ti-lite.conf
[greeter]
background=/usr/share/backgrounds/ti-lite-wallpaper.jpg
LDM_EOF

  cat << 'WALL_EOF' > /usr/local/bin/set-ti-wallpaper.sh
#!/bin/bash
sleep 2
WALLPAPER="/usr/share/backgrounds/ti-lite-wallpaper.jpg"
for prop in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep "last-image"); do
  xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER"
done
for mon in $(xrandr --query 2>/dev/null | awk '/ connected/{print $1}'); do
  xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitor${mon}/workspace0/last-image" -n -t string -s "$WALLPAPER"
  xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitor${mon}/workspace0/image-style" -n -t int -s 5
done
rm -f "$HOME/.config/autostart/set-wallpaper.desktop"
WALL_EOF
  chmod +x /usr/local/bin/set-ti-wallpaper.sh

  mkdir -p /etc/skel/.config/autostart
  cat << 'AUTO_EOF' > /etc/skel/.config/autostart/set-wallpaper.desktop
[Desktop Entry]
Type=Application
Name=Set Default Wallpaper
Exec=/usr/local/bin/set-ti-wallpaper.sh
X-GNOME-Autostart-enabled=true
AUTO_EOF
fi

# Catatan panduan singkat di Desktop
mkdir -p /etc/skel/Desktop /etc/skel/Latihan-Coding
cat << 'DOC_EOF' > /etc/skel/Desktop/BACA_DULU.txt
Selamat datang di TI-Lite-Ubuntu 24.04 LTS!

1. Menyalakan MariaDB: sudo systemctl start mariadb
2. Mematikan MariaDB:  sudo systemctl stop mariadb
3. Shortcut FDM sudah terpasang di toolbar bawah.
DOC_EOF

update-initramfs -u
apt-get autoremove -y
apt-get clean
rm -rf /tmp/* /var/lib/apt/lists/*
CHROOT_EOF

cleanup
trap - EXIT

# 6. Salin kernel & buat manifest
cp "$(ls -1 "$CHROOT"/boot/vmlinuz-* | sort -V | tail -n 1)" "$IMAGE/casper/vmlinuz"
cp "$(ls -1 "$CHROOT"/boot/initrd.img-* | sort -V | tail -n 1)" "$IMAGE/casper/initrd"
chroot "$CHROOT" dpkg-query -W --showformat='${Package} ${Version}\n' > "$IMAGE/casper/filesystem.manifest"
printf $(du -sx --block-size=1 "$CHROOT" | cut -f1) > "$IMAGE/casper/filesystem.size"
echo "TI-Lite-Ubuntu 24.04 LTS" > "$IMAGE/.disk/info"

# 7. Kompres sistem file menjadi SquashFS
mksquashfs "$CHROOT" "$IMAGE/casper/filesystem.squashfs" -comp zstd -e boot
rm -rf "$CHROOT"

# 8. Buat menu booting GRUB (BIOS & UEFI)
cat << 'EOF' > "$IMAGE/boot/grub/grub.cfg"
set default="0"
set timeout=5

menuentry "TI-Lite-Ubuntu 24.04 LTS (Live)" {
    linux /casper/vmlinuz boot=casper quiet splash ---
    initrd /casper/initrd
}
menuentry "TI-Lite-Ubuntu 24.04 LTS (Safe Graphics)" {
    linux /casper/vmlinuz boot=casper nomodeset ---
    initrd /casper/initrd
}
EOF

# 9. Bungkus menjadi file ISO
grub-mkrescue -o TI-Lite-Ubuntu-24.04-amd64.iso "$IMAGE"
chmod 644 TI-Lite-Ubuntu-24.04-amd64.iso
rm -rf "$WORKDIR"
