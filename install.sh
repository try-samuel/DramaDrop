#!/bin/bash
set -euo pipefail

REPO="${DRAMADROP_REPO:-try-samuel/DramaDrop}"
APP_NAME="DramaDrop"
CLI_NAME="dramadrop"
INSTALL_DIR="$HOME/.local/bin"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

detect_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    if [ "$os" != "Darwin" ]; then
        error "DramaDrop currently supports macOS only."
    fi

    case "$arch" in
        arm64|aarch64)
            ASSET_SUFFIX="arm64"
            ;;
        x86_64|amd64)
            ASSET_SUFFIX="x64"
            ;;
        *)
            error "Unsupported architecture: $arch"
            ;;
    esac

    info "Detected macOS ${ASSET_SUFFIX}"
}

get_version() {
    if [ -n "${DRAMADROP_VERSION:-}" ]; then
        VERSION="$DRAMADROP_VERSION"
        info "Using requested version: $VERSION"
        return
    fi

    info "Fetching latest release..."
    VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')"

    if [ -z "$VERSION" ]; then
        error "Could not determine the latest DramaDrop release."
    fi

    info "Latest version: $VERSION"
}

install_app() {
    local asset_name download_url temp_dir

    asset_name="DramaDrop-macos-${ASSET_SUFFIX}.zip"
    download_url="https://github.com/$REPO/releases/download/$VERSION/$asset_name"

    info "Downloading $asset_name..."
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT

    curl -fsSL "$download_url" -o "$temp_dir/$asset_name" || error "Download failed. Make sure the release exists and includes $asset_name."

    info "Extracting app bundle..."
    unzip -q "$temp_dir/$asset_name" -d "$temp_dir"

    if [ ! -d "$temp_dir/$APP_NAME.app" ]; then
        error "The downloaded archive does not contain $APP_NAME.app."
    fi

    if [ -d "/Applications/$APP_NAME.app" ]; then
        warn "Removing existing installation..."
        rm -rf "/Applications/$APP_NAME.app"
    fi

    info "Installing to /Applications/$APP_NAME.app..."
    cp -R "$temp_dir/$APP_NAME.app" /Applications/

    xattr -cr "/Applications/$APP_NAME.app" 2>/dev/null || true
}

install_cli_wrapper() {
    mkdir -p "$INSTALL_DIR"

    cat > "$INSTALL_DIR/$CLI_NAME" <<'EOF'
#!/bin/bash
open -a "DramaDrop"
EOF

    chmod +x "$INSTALL_DIR/$CLI_NAME"
    info "Installed CLI launcher at $INSTALL_DIR/$CLI_NAME"
}

setup_path() {
    local rc_file shell_name

    if [[ ":$PATH:" == *":$INSTALL_DIR:"* ]]; then
        return
    fi

    warn "$INSTALL_DIR is not in your PATH."

    shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        zsh) rc_file="$HOME/.zshrc" ;;
        bash) rc_file="$HOME/.bashrc" ;;
        *) rc_file="$HOME/.profile" ;;
    esac

    if ! grep -q "$INSTALL_DIR" "$rc_file" 2>/dev/null; then
        {
            echo ""
            echo "# DramaDrop"
            echo 'export PATH="$PATH:$HOME/.local/bin"'
        } >> "$rc_file"
        info "Added $INSTALL_DIR to PATH in $rc_file"
    fi

    warn "Run 'source $rc_file' or restart your terminal before using '$CLI_NAME'."
}

main() {
    echo ""
    echo "  ╔═══════════════════════════════════╗"
    echo "  ║        DramaDrop Installer        ║"
    echo "  ╚═══════════════════════════════════╝"
    echo ""

    detect_platform
    get_version
    install_app
    install_cli_wrapper
    setup_path

    echo ""
    info "Installation complete."
    echo ""
    echo "  Launch with: ${GREEN}$CLI_NAME${NC}"
    echo ""
}

main "$@"
