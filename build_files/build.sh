#!/bin/bash
# ergon image build: runs once inside the Containerfile on top of ublue-os/base-main.
set -ouex pipefail

### Packages (Fedora repos unless noted)

# Desktop: niri + Noctalia shell, greetd login, portals, Xwayland for X11 apps
DESKTOP=(
	niri
	noctalia
	xwayland-satellite
	greetd
	xdg-desktop-portal-gnome # screencasting (niri implements Mutter's ScreenCast API)
	xdg-desktop-portal-gtk
	xdg-desktop-portal-kde # Qt/KDE file chooser
	wl-clipboard
	power-profiles-daemon
	redhat-menus # /etc/xdg/menus/applications.menu: KDE apps need it for "Open with" outside Plasma
)

# Qt / KDE applications
APPS=(
	kitty
	dolphin
	kio-extras
	kdegraphics-thumbnailers
	ffmpegthumbs
	kate
	kwrite
	ark
	gwenview
	vlc
	kcalc
	btop
	kde-partitionmanager
	kf6-kwallet
	kwalletmanager5
	pam-kwallet # unlocks the wallet at greetd login (/etc/pam.d/greetd already references it)
	corectrl
	qt6ct
	kvantum
	plasma-breeze-qt6
	breeze-icon-theme
	papirus-icon-theme # Papirus-Dark is the default icon theme (inherits breeze-dark)
	papirus-icon-theme-dark
)

# Gaming. steam comes from negativo17's fedora-multimedia repo (already configured in base-main).
GAMING=(
	steam
	steam-devices
	gamescope
	gamemode
	mangohud
)

# Containers: podman itself is in base-main; these are the front ends for dev environments.
CONTAINERS=(
	distrobox
	toolbox
	podman-compose
)

# Basics a desktop-less base doesn't guarantee.
TOOLS=(
	git
	xdg-user-dirs
	fastfetch
)

FONTS=(
	google-noto-sans-fonts
	google-noto-color-emoji-fonts
	jetbrains-mono-fonts-all
)

# gnome-keyring is only a weak dependency of niri/noctalia; KWallet is the secret service here,
# and two providers would race for org.freedesktop.secrets.
dnf5 -y install --enablerepo=fedora-multimedia --exclude=gnome-keyring \
	"${DESKTOP[@]}" "${APPS[@]}" "${GAMING[@]}" "${CONTAINERS[@]}" "${TOOLS[@]}" "${FONTS[@]}"

### From Terra (Fedora 44+): the Noctalia greeter and Starship (neither is in Fedora), nothing else.
# Installed in its own transaction, restricted to those packages so Terra can't
# replace Fedora packages; the Terra repo definitions are removed again afterwards.
dnf5 -y install --nogpgcheck \
	--repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" \
	terra-release terra-gpg-keys
dnf5 -y install --setopt="terra.includepkgs=noctalia-greeter*,starship" noctalia-greeter starship
dnf5 -y remove terra-release terra-gpg-keys

### Files and branding (after packages, so ours replace package defaults)
cp -avf /ctx/system_files/. /

install -Dm0644 /ctx/branding/ergon-emblem.svg /usr/share/icons/hicolor/scalable/apps/ergon.svg
install -Dm0644 /ctx/branding/ergon-emblem.svg /usr/share/pixmaps/ergon-logo.svg
# ID stays "fedora" so tools that check it keep working; the rest describes ergon.
sed -i \
	-e 's/^PRETTY_NAME=.*/PRETTY_NAME="ergon (Fedora Linux 44)"/' \
	-e 's/^LOGO=.*/LOGO=ergon/' \
	-e 's/^ANSI_COLOR=.*/ANSI_COLOR="0;38;2;200;96;63"/' \
	-e 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="ergon"/' \
	-e 's|^HOME_URL=.*|HOME_URL="https://github.com/Gateshare/ergon"|' \
	-e 's|^DOCUMENTATION_URL=.*|DOCUMENTATION_URL="https://github.com/Gateshare/ergon#readme"|' \
	-e 's|^SUPPORT_URL=.*|SUPPORT_URL="https://github.com/Gateshare/ergon/issues"|' \
	-e 's|^BUG_REPORT_URL=.*|BUG_REPORT_URL="https://github.com/Gateshare/ergon/issues"|' \
	/usr/lib/os-release
cat >>/usr/lib/os-release <<'OSRELEASE'
VARIANT="ergon"
VARIANT_ID=ergon
OSRELEASE
install -Dm0644 /ctx/branding/fastfetch/logo.txt /usr/share/ergon/fastfetch-logo.txt
install -Dm0644 -t /usr/share/backgrounds/ergon /ctx/branding/wallpapers/*.jpg

# Boot splash: Fedora's bgrt theme shows the firmware logo plus fedora-logos' watermark.
# The ergon theme reuses the spinner images with the ergon emblem as the watermark.
plymouth_theme=/usr/share/plymouth/themes/ergon
cp -a /usr/share/plymouth/themes/spinner/*.png "$plymouth_theme/"
install -m0644 /ctx/branding/plymouth/watermark.png "$plymouth_theme/watermark.png"
plymouth-set-default-theme ergon

# Icons: Papirus with its folders in the ergon terracotta. Same approach as papirus-folders
# (github.com/PapirusDevelopmentTeam/papirus-folders): point folder-*.svg / user-*.svg at a
# colour variant. We take the deeporange variant and recolour it to the logo's colours.
papirus=/usr/share/icons/Papirus
for f in "$papirus"/{22x22,24x24,32x32,48x48,64x64}/places/{folder,user}-deeporange{-*,}.svg; do
	[[ -f $f && ! -L $f ]] || continue
	sed -i -e 's/#e95420/#c8603f/gI' -e 's/#eb6637/#d8704c/gI' -e 's/#522413/#4f2618/gI' "$f"
	ln -sf "${f##*/}" "${f/-deeporange/}"
done

# Cursor: Bibata Modern Classic (not packaged in Fedora). /usr/share/icons/default/index.theme
# (from system_files) makes it the default everywhere, including the greeter.
bibata_version=v2.0.7
bibata_sha256=7d3495864e5bbef02f5e77de760b2905903b63c71495a78ef6306d19a3b556d8
curl -fsSLo /tmp/bibata.tar.xz \
	"https://github.com/ful1e5/Bibata_Cursor/releases/download/$bibata_version/Bibata-Modern-Classic.tar.xz"
echo "$bibata_sha256  /tmp/bibata.tar.xz" | sha256sum -c -
tar -xJf /tmp/bibata.tar.xz -C /usr/share/icons
rm /tmp/bibata.tar.xz

# GTK icon/cursor/font defaults (system_files/etc/dconf/db/distro.d)
dconf update

### Services
systemctl enable greetd.service
systemctl enable ergon-greeter-setup.service
systemctl enable ergon-flatpaks.service
systemctl enable power-profiles-daemon.service
systemctl --global enable ergon-user-defaults.service
systemctl set-default graphical.target

### Initramfs: Plymouth runs from the initramfs, so rebuild it to pick up the ergon theme.
kernels=(/usr/lib/modules/*)
[[ ${#kernels[@]} -eq 1 ]] || { echo "expected one kernel, found: ${kernels[*]}" >&2; exit 1; }
kver=$(basename "${kernels[0]}")
DRACUT_NO_XATTR=1 dracut --no-hostonly --kver "$kver" --reproducible --add ostree -f "/usr/lib/modules/$kver/initramfs.img"
chmod 0600 "/usr/lib/modules/$kver/initramfs.img"

### Cleanup: dnf state in /var doesn't belong in the image (bootc lint var-tmpfiles)
dnf5 clean all
rm -rf /var/lib/dnf/repos
