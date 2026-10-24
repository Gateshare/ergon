# ergon: bash prompt. Starship (configured in ~/.config/starship.toml) when it's installed,
# otherwise a shorter version of Fedora's bash-color-prompt.sh (which runs before this file):
#   ~/.../Entelect/data$            locally
#   richter@rampage ~/.../data$     over SSH or inside a container (distrobox/toolbox)
# Set ergon_starship_disable=1 in ~/.bashrc, before /etc/bashrc is sourced, to skip Starship.
case $- in
*i*) ;;
*) return ;;
esac
[ -n "${BASH_VERSION}" ] || return

if [ -z "${ergon_starship_disable}" ] && command -v starship >/dev/null 2>&1; then
	eval "$(starship init bash)"
elif type prompt_default_format >/dev/null 2>&1; then
	PROMPT_DIRTRIM=2                     # keep only the last two directories of the path
	PROMPT_DIR_COLOR='1;38;2;216;112;76' # bold ergon terracotta
	if [ -n "${SSH_CONNECTION}${container}" ]; then
		PROMPT_SEPARATOR=' '
	else
		unset PROMPT_USERHOST
	fi
fi
