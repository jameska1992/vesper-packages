#!/bin/bash
# Builds the vesper pacman repository into OUT (default: out/):
#
#   1. vesper-keyring (keyring/), the key pacman checks the repository with
#   2. the AUR packages in aur.list, each at its pinned commit
#   3. VesperOS's own packages (own.list), when VESPER_SOURCES_TOKEN lets
#      their private repositories be fetched
#
# then signs every package and the database with the key in GNUPGHOME
# ($VESPER_SIGNING_KEY, a fingerprint, by default VesperOS's).
#
# Runs as a normal user that may run pacman through sudo (makepkg installs
# build dependencies, and each built package is installed so later ones can
# depend on it): in a throwaway Arch container (the GitHub workflow), not on
# a machine you use.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
out=$(realpath -m "${1:-$root/out}")
work="$root/work"
key="${VESPER_SIGNING_KEY:-F740EB85DB99F91239E815733ADC77FF3251C907}"
export PKGDEST="$out" SRCDEST="$work/sources" BUILDDIR="$work/build"

rm -rf "$out" "$work"
mkdir -p "$out" "$work/sources" "$work/build"

gpg --batch --list-secret-keys "$key" >/dev/null ||
	{ echo "build.sh: no secret key $key in GNUPGHOME" >&2; exit 1; }

# makepkg in a copy of DIR (it writes into the PKGBUILD's directory), then
# install what it built.
build() {
	local dir=$1 copy="$work/pkgbuilds/$(basename "$1")"
	rm -rf "$copy"
	mkdir -p "$work/pkgbuilds"
	cp -a "$dir" "$copy"
	echo "==> $(basename "$dir")"
	(cd "$copy" && makepkg --syncdeps --noconfirm --cleanbuild --force)
	local pkgs=() f
	while read -r f; do
		# Not the debug packages (not needed by anything, not published).
		[[ -f "$f" && "$f" != *-debug-* ]] && pkgs+=("$f")
	done < <(cd "$copy" && makepkg --packagelist)
	sudo pacman -U --noconfirm --needed "${pkgs[@]}"
}

list() { grep -v '^[[:space:]]*\(#\|$\)' "$1"; }

# 1. The keyring.
build "$root/keyring"

# 2. The AUR packages, pinned.
while read -r name commit; do
	git clone -q "https://aur.archlinux.org/$name.git" "$work/aur/$name"
	git -C "$work/aur/$name" -c advice.detachedHead=false checkout -q "$commit"
	build "$work/aur/$name"
done < <(list "$root/aur.list")

# 3. VesperOS's own packages.
if [ -n "${VESPER_SOURCES_TOKEN:-}" ]; then
	export VESPER_SRC="git+https://x-access-token:${VESPER_SOURCES_TOKEN}@github.com/jameska1992"
	git clone -q "https://x-access-token:${VESPER_SOURCES_TOKEN}@github.com/jameska1992/vesperos.git" \
		"$work/vesperos"
	while read -r name; do
		build "$work/vesperos/packages/$name"
	done < <(list "$root/own.list")
else
	echo "==> No VESPER_SOURCES_TOKEN: VesperOS's own packages are left out"
fi

# Sign the packages and the database.
cd "$out"
rm -f ./*-debug-*.pkg.tar.zst
for f in ./*.pkg.tar.zst; do
	case "$f" in *:*)
		# GitHub renames ':' in release files, and pacman would then miss them.
		echo "build.sh: $f has a ':' (an epoch): it can't be published as a GitHub release file" >&2
		exit 1;;
	esac
	gpg --batch --yes --detach-sign --no-armor --local-user "$key" "$f"
done
repo-add --quiet --sign --key "$key" vesper.db.tar.zst ./*.pkg.tar.zst
# Releases hold files, not links: real copies where pacman expects them.
for f in vesper.db vesper.db.sig vesper.files vesper.files.sig; do
	[ -L "$f" ] && cp --remove-destination "$(readlink "$f")" "$f"
done
echo "==> $out:"
ls -1 "$out"
