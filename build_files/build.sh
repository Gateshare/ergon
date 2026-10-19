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
)

# Gaming. steam comes from negativo17's fedora-multimedia repo (already configured in base-main).
GAMING=(
	steam
	steam-devices
	gamescope
	gamemode
	mangohud
)

FONTS=(
	google-noto-sans-fonts
	google-noto-color-emoji-fonts
	jetbrains-mono-fonts-all
)

# gnome-keyring is only a weak dependency of niri/noctalia; KWallet is the secret service here,
# and two providers would race for org.freedesktop.secrets.
dnf5 -y install --enablerepo=fedora-multimedia --exclude=gnome-keyring \
	"${DESKTOP[@]}" "${APPS[@]}" "${GAMING[@]}" "${FONTS[@]}"

### Noctalia greeter from Terra (Fedora 44+), and nothing else from Terra.
# Installed in its own transaction, restricted to the greeter package so Terra can't
# replace Fedora packages; the Terra repo definitions are removed again afterwards.
dnf5 -y install --nogpgcheck \
	--repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" \
	terra-release terra-gpg-keys
dnf5 -y install --setopt="terra.includepkgs=noctalia-greeter*" noctalia-greeter
dnf5 -y remove terra-release terra-gpg-keys

### Files and branding (after packages, so ours replace package defaults)
cp -avf /ctx/system_files/. /

install -Dm0644 /ctx/branding/ergon-emblem.svg /usr/share/icons/hicolor/scalable/apps/ergon.svg
install -Dm0644 /ctx/branding/ergon-emblem.svg /usr/share/pixmaps/ergon-logo.svg
sed -i \
	-e 's/^PRETTY_NAME=.*/PRETTY_NAME="ergon (Fedora Linux 44)"/' \
	-e 's/^LOGO=.*/LOGO=ergon/' \
	/usr/lib/os-release

### Services
systemctl enable greetd.service
systemctl enable ergon-greeter-setup.service
systemctl enable ergon-flatpaks.service
systemctl enable power-profiles-daemon.service
systemctl --global enable ergon-user-defaults.service
systemctl set-default graphical.target

### Cleanup: dnf state in /var doesn't belong in the image (bootc lint var-tmpfiles)
dnf5 clean all
rm -rf /var/lib/dnf/repos
