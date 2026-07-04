#!/bin/sh
# Colobot (fork) installer - https://pt12lol.github.io/colobot/
#
# Usage (see the website for a switch-driven command builder):
#   curl -sSf https://pt12lol.github.io/colobot/install.sh | sh
#   curl -sSf https://pt12lol.github.io/colobot/install.sh | sh -s -- --source
#
# Flags:
#   --source        build from source instead of downloading a prebuilt package
#   --system        install for all users (/opt + /usr/local/bin, uses sudo)
#   --no-music      skip the (large) music pack
#   --tag <tag>     install a specific release tag (default: latest)
#   --help          show this help
#
# Design: sudo is used only when unavoidable (apt for build deps, or a
# system-wide install). The default user install touches nothing outside $HOME.

set -eu

REPO="pt12lol/colobot"
APP="colobot-fork"
SOURCE_BRANCH="mine"

MODE="prebuilt"     # prebuilt | source
SCOPE="user"        # user | system
MUSIC="1"
TAG="latest"
UNINSTALL="0"
FORCE="0"
VERSION_FILE=".fork-version"   # stamped inside PREFIX to detect install/update

print_help() {
    cat <<'EOF'
Colobot (fork) installer - https://pt12lol.github.io/colobot/

  --source        build from source instead of downloading a prebuilt package
  --system        install for all users (/opt + /usr/local/bin, uses sudo)
  --no-music      skip the (large) music pack
  --tag <tag>     install a specific release tag (default: latest)
  --force         reinstall even if already up to date
  --uninstall     remove a previous installation
  --help          show this help
EOF
}

# ---- args --------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --source)    MODE="source" ;;
        --system)    SCOPE="system" ;;
        --no-music)  MUSIC="0" ;;
        --tag)       shift; TAG="${1:-latest}" ;;
        --force)     FORCE="1" ;;
        --uninstall) UNINSTALL="1" ;;
        --help|-h)   print_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

say()  { printf '\033[1;36m::\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$1" >&2; exit 1; }

# ---- run a command as root only when needed ---------------------------------
as_root() {
    if [ "$(id -u)" = "0" ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        die "This step needs root but 'sudo' was not found. Re-run as root or install sudo."
    fi
}

# ---- detect distro -----------------------------------------------------------
detect_distro() {
    [ -r /etc/os-release ] || die "Cannot read /etc/os-release - unsupported system."
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}:${VERSION_ID:-}" in
        ubuntu:22.04) echo "ubuntu-22.04" ;;
        debian:*)
            # Trixie may report "13" or "trixie" depending on the release stage
            case "${VERSION_CODENAME:-}${VERSION_ID:-}" in
                *trixie*|*13*) echo "debian-trixie" ;;
                *) echo "" ;;
            esac ;;
        *) echo "" ;;
    esac
}

arch_ok() { [ "$(uname -m)" = "x86_64" ]; }

# ---- paths -------------------------------------------------------------------
if [ "$SCOPE" = "system" ]; then
    PREFIX="/opt/${APP}"
    BINDIR="/usr/local/bin"
    APPSDIR="/usr/share/applications"
    ICONDIR="/usr/share/icons/hicolor/scalable/apps"
    RUN="as_root"
else
    PREFIX="${HOME}/.local/share/${APP}"
    BINDIR="${HOME}/.local/bin"
    APPSDIR="${HOME}/.local/share/applications"
    ICONDIR="${HOME}/.local/share/icons/hicolor/scalable/apps"
    RUN=""   # plain, no privilege escalation
fi
SAVEDIR="${HOME}/.local/share/${APP}-saves"   # OUTSIDE prefix, survives reinstall/update

# run helper that respects SCOPE
priv() { if [ -n "$RUN" ]; then $RUN "$@"; else "$@"; fi; }

# Only ever wipe a path that actually looks like our install dir.
wipe_prefix() {
    case "$PREFIX" in
        */colobot-fork) priv rm -rf "$PREFIX" ;;
        *) die "Refusing to remove unexpected path: '$PREFIX'" ;;
    esac
}

uninstall() {
    say "Removing ${APP} from ${PREFIX}"
    wipe_prefix
    priv rm -f "${BINDIR}/${APP}" "${APPSDIR}/${APP}.desktop" "${ICONDIR}/${APP}.svg"
    say "Uninstalled. (Saves in ${SAVEDIR} were left untouched.)"
}

# Offer to copy saves from an existing (e.g. apt) Colobot into the fork's
# save dir. Only when the fork has none yet. Prompt reads /dev/tty because
# under `curl | sh` stdin is the script; defaults to yes.
maybe_import_saves() {
    orig="${XDG_DATA_HOME:-$HOME/.local/share}/colobot"
    [ -d "$orig" ] || return 0
    [ -d "$SAVEDIR" ] && [ -n "$(ls -A "$SAVEDIR" 2>/dev/null)" ] && return 0

    ans="y"
    if [ -r /dev/tty ]; then
        printf '\033[1;36m??\033[0m Found existing Colobot saves in %s. Copy them into the fork? [Y/n] ' "$orig" > /dev/tty
        read ans < /dev/tty || ans="y"
    fi
    case "${ans:-y}" in
        [Nn]*) say "Keeping the fork's saves separate." ;;
        *)
            mkdir -p "$SAVEDIR"
            if cp -r "$orig/." "$SAVEDIR/" 2>/dev/null; then
                say "Saves copied. (If a level looks locked, the save format may differ between versions.)"
            else
                warn "Could not copy saves from ${orig}."
            fi ;;
    esac
}

# Latest release tag from the GitHub API (no jq dependency).
latest_tag() {
    api="https://api.github.com/repos/${REPO}/releases/latest"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$api" 2>/dev/null
    else
        wget -qO- "$api" 2>/dev/null
    fi | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
}

# Version we are about to install: a tag for prebuilt, "source" for a source build.
target_version() {
    if [ "$MODE" = "source" ]; then echo "source"; return; fi
    if [ "$TAG" = "latest" ]; then
        t="$(latest_tag)"; echo "${t:-latest}"
    else
        echo "$TAG"
    fi
}

# ---- launcher + desktop entry (shared by both modes) ------------------------
install_launcher() {
    say "Creating launcher '${APP}' and menu entry"
    priv mkdir -p "$BINDIR" "$APPSDIR" "$ICONDIR"
    mkdir -p "$SAVEDIR"

    launcher="$(mktemp)"
    cat > "$launcher" <<EOF
#!/bin/sh
# Colobot (fork) launcher - relocatable, points the binary at its bundled data.
DIR="${PREFIX}"
export LD_LIBRARY_PATH="\$DIR/lib/colobot:\${LD_LIBRARY_PATH:-}"
exec "\$DIR/games/colobot" -datadir "\$DIR/share/games/colobot" -savedir "${SAVEDIR}" "\$@"
EOF
    priv install -Dm755 "$launcher" "${BINDIR}/${APP}"
    rm -f "$launcher"

    if [ -f "${PREFIX}/share/icons/${APP}.svg" ]; then
        priv install -Dm644 "${PREFIX}/share/icons/${APP}.svg" "${ICONDIR}/${APP}.svg"
    fi

    desktop="$(mktemp)"
    cat > "$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Colobot (fork)
Comment=Colobot with in-editor IntelliSense and F12 jump-to-docs
Exec=${APP}
Icon=${APP}
Terminal=false
Categories=Game;Education;
EOF
    priv install -Dm644 "$desktop" "${APPSDIR}/${APP}.desktop"
    rm -f "$desktop"
}

# ---- prebuilt mode -----------------------------------------------------------
install_prebuilt() {
    arch_ok || die "Prebuilt packages are x86_64 only. Try: ... | sh -s -- --source"
    distro="$(detect_distro)"
    [ -n "$distro" ] || die "No prebuilt package for this distro. Try: ... | sh -s -- --source"

    suffix=""
    [ "$MUSIC" = "0" ] && suffix="-nomusic"
    asset="${APP}-${distro}-x86_64${suffix}.tar.gz"
    if [ "$TAG" = "latest" ]; then
        url="https://github.com/${REPO}/releases/latest/download/${asset}"
    else
        url="https://github.com/${REPO}/releases/download/${TAG}/${asset}"
    fi

    say "Downloading ${asset}"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    if command -v curl >/dev/null 2>&1; then
        curl -fSL "$url" -o "${tmp}/pkg.tar.gz" || die "Download failed: ${url}"
        curl -fsSL "${url}.sha256" -o "${tmp}/pkg.sha256" 2>/dev/null || true
    else
        wget -O "${tmp}/pkg.tar.gz" "$url" || die "Download failed: ${url}"
        wget -qO "${tmp}/pkg.sha256" "${url}.sha256" 2>/dev/null || true
    fi

    # Verify integrity against the published checksum (best-effort).
    if [ -s "${tmp}/pkg.sha256" ] && command -v sha256sum >/dev/null 2>&1; then
        expected="$(cut -d' ' -f1 "${tmp}/pkg.sha256")"
        actual="$(sha256sum "${tmp}/pkg.tar.gz" | cut -d' ' -f1)"
        [ "$expected" = "$actual" ] || die "Checksum mismatch - refusing to install."
        say "Checksum OK"
    else
        warn "Skipping checksum verification (no .sha256 or sha256sum)."
    fi

    say "Installing to ${PREFIX}"
    wipe_prefix
    priv mkdir -p "$PREFIX"
    # Tarball root is the prefix tree (games/, lib/, share/) - strip the top dir.
    priv tar -xzf "${tmp}/pkg.tar.gz" -C "$PREFIX" --strip-components=1

    install_launcher
}

# ---- source mode -------------------------------------------------------------
DEPS="build-essential cmake git \
libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev \
libsndfile1-dev libvorbis-dev libogg-dev libpng-dev \
libglew-dev libopenal-dev \
libboost-dev libboost-system-dev libboost-filesystem-dev libboost-regex-dev \
libphysfs-dev gettext po4a vorbis-tools"

install_source() {
    say "Installing build dependencies (needs sudo/apt)"
    if command -v apt-get >/dev/null 2>&1; then
        as_root apt-get update
        # shellcheck disable=SC2086
        as_root apt-get install -y $DEPS
    else
        warn "No apt-get found - install these yourself: $DEPS"
    fi

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    say "Cloning ${REPO} (branch ${SOURCE_BRANCH})"
    git clone --depth 1 --branch "$SOURCE_BRANCH" --recurse-submodules \
        "https://github.com/${REPO}.git" "${tmp}/src" || die "git clone failed"

    say "Building (this takes a while)"
    music_flag="-DMUSIC=ON"
    [ "$MUSIC" = "0" ] && music_flag="-DMUSIC=OFF"
    cmake -S "${tmp}/src" -B "${tmp}/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        $music_flag
    cmake --build "${tmp}/build" -j"$(nproc 2>/dev/null || echo 2)"

    say "Installing to ${PREFIX}"
    wipe_prefix
    priv cmake --install "${tmp}/build"

    install_launcher
}

# ---- go ----------------------------------------------------------------------
if [ "$UNINSTALL" = "1" ]; then
    say "Colobot (fork) uninstaller (scope: ${SCOPE})"
    uninstall
    exit 0
fi

TARGET="$(target_version)"
INSTALLED=""
[ -f "${PREFIX}/${VERSION_FILE}" ] && INSTALLED="$(cat "${PREFIX}/${VERSION_FILE}" 2>/dev/null)"

if [ -n "$INSTALLED" ] && [ "$MODE" != "source" ] && [ "$INSTALLED" = "$TARGET" ] && [ "$FORCE" != "1" ]; then
    say "Colobot (fork) ${INSTALLED} is already up to date. Use --force to reinstall."
    exit 0
fi

if [ -n "$INSTALLED" ]; then
    say "Updating Colobot (fork): ${INSTALLED} -> ${TARGET} (scope: ${SCOPE})"
else
    say "Installing Colobot (fork) ${TARGET} (mode: ${MODE}, scope: ${SCOPE}, music: ${MUSIC})"
fi

if [ "$MODE" = "source" ]; then
    install_source
else
    install_prebuilt
fi

printf '%s\n' "$TARGET" | priv tee "${PREFIX}/${VERSION_FILE}" >/dev/null 2>&1 || true

maybe_import_saves

echo
say "Done. Launch it from your applications menu, or run: ${APP}"
case ":${PATH}:" in
    *":${BINDIR}:"*) : ;;
    *) [ "$SCOPE" = "user" ] && warn "Add ${BINDIR} to your PATH to run '${APP}' from a terminal." ;;
esac
