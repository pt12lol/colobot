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

# ---- args --------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --source)   MODE="source" ;;
        --system)   SCOPE="system" ;;
        --no-music) MUSIC="0" ;;
        --tag)      shift; TAG="${1:-latest}" ;;
        --help|-h)  sed -n '2,20p' "$0" 2>/dev/null || true; exit 0 ;;
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
SAVEDIR="${HOME}/.local/share/${APP}/saves"

# run helper that respects SCOPE
priv() { if [ -n "$RUN" ]; then $RUN "$@"; else "$@"; fi; }

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
    else
        wget -O "${tmp}/pkg.tar.gz" "$url" || die "Download failed: ${url}"
    fi

    say "Installing to ${PREFIX}"
    priv rm -rf "$PREFIX"
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
    priv rm -rf "$PREFIX"
    priv cmake --install "${tmp}/build"

    install_launcher
}

# ---- go ----------------------------------------------------------------------
say "Colobot (fork) installer - mode: ${MODE}, scope: ${SCOPE}, music: ${MUSIC}"
if [ "$MODE" = "source" ]; then
    install_source
else
    install_prebuilt
fi

echo
say "Done. Launch it from your applications menu, or run: ${APP}"
case ":${PATH}:" in
    *":${BINDIR}:"*) : ;;
    *) [ "$SCOPE" = "user" ] && warn "Add ${BINDIR} to your PATH to run '${APP}' from a terminal." ;;
esac
