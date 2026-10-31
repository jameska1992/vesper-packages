# vesper-packages

The pacman repository of [VesperOS](https://github.com/jameska1992/vesperos):
apps VesperOS recommends that aren't in Arch Linux's repositories or on
Flathub (built from the AUR, after reading them), and VesperOS's own
packages. Every package and the database are signed.

    [vesper]
    SigLevel = Required
    Server = https://github.com/jameska1992/vesper-packages/releases/download/repo

VesperOS adds this to `pacman.conf` once the repository is published, with
`vesper-keyring` for the key; the App Store installs from it like from any
other repository, and its Update everything keeps VesperOS itself up to
date.

## What's in it

- `vesper-keyring` (`keyring/`): the signing key, as a pacman keyring
  (`pacman-key --populate vesper`).
- The AUR packages in `aur.list`, each **pinned to the AUR commit that was
  reviewed**: a new version only goes in after reading its PKGBUILD (and
  any install script and patches) and moving the pin. Now: ES-DE
  (`emulationstation-de`) and `freeimage`, which it needs.
- VesperOS's packages (`own.list`, PKGBUILDs in the vesperos repository),
  when the build has a token for their private repositories.

## How it's built

`build.sh` builds everything into `out/`: the keyring, the pinned AUR
packages (installing each, so later ones can depend on it), and VesperOS's
packages; then signs each package and the database (`repo-add --sign`) with
the key in `GNUPGHOME`. It installs packages, so it's meant for a throwaway
Arch container, as a user that may run pacman through sudo.

The GitHub workflow (`.github/workflows/build.yml`) does that in a clean
`archlinux:base-devel` container when the lists or the build change, when
started by hand, and weekly (rebuilding against Arch's updates), then
publishes `out/` as the files of the `repo` release: new files over old
first, then old ones removed, so the repository is never half there.

Releases hold files, so the database links are real copies, and package
files with a `:` (an epoch) can't be published (GitHub renames them); the
build stops if one turns up.

## Secrets

- `VESPER_SIGNING_KEY` (required): the private signing key, armored
  (`gpg --armor --export-secret-keys F740EB85DB99F91239E815733ADC77FF3251C907`).
- `VESPER_SOURCES_TOKEN` (optional): a fine-grained GitHub token with
  read-only access to VesperOS's repositories (contents), for its own
  packages.

## The key

`F740EB85DB99F91239E815733ADC77FF3251C907`, "VesperOS Package Signing"
(ed25519, signing only, no passphrase so the build can sign unattended).
It's kept in `~/.local/share/vesperos-signing` (a GnuPG home of its own) on
the machine that made it, with its revocation certificate in
`openpgp-revocs.d/`. Back both up somewhere safe and offline: anyone with
the private key can sign packages VesperOS will install. If it's ever
exposed, publish the revocation, make a new key, and release a new
vesper-keyring (its `vesper-revoked` lists revoked keys).

## Adding an app from the AUR

1. Read the package on the AUR: its PKGBUILD, `.install` script, patches,
   and where its sources come from (official, with checksums).
2. Check its dependencies are in Arch's repositories, or add the AUR ones
   (reviewed the same way) before it in `aur.list`.
3. Add `NAME COMMIT` (the reviewed commit) with a note, and push: the
   workflow builds and publishes it.
4. Recommend it in vesper-store's `recommended.json`, with
   `"repo": "vesper"` and its name, summary, package, icon and desktop
   entry (AUR packages have no AppStream data).
