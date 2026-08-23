#!/usr/bin/env bash
# Home-AI Service Script
# Bundles update processes for the host (server) and management (client).

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
FLAKE_HOST="home-ai-server" # Hostname matching flake.nix

# Ensure userspace bin is in PATH for SteamOS distrobox installations
export PATH="$HOME/.local/bin:$PATH"

function print_help() {
    echo "=========================================="
    echo " Home-AI Service Script"
    echo "=========================================="
    echo "HOST LEVEL (Executed on the NixOS Server):"
    echo "  $0 host update all       - Pull git changes, update NixOS & Docker"
    echo "  $0 host update system    - Pull git changes & update NixOS"
    echo "  $0 host update services  - Pull git changes & update Docker"
    echo "  $0 host autoupdate       - Interactive setup for host cronjobs"
    echo ""
    echo "MANAGEMENT LEVEL (Executed on Workstation/Steam Deck):"
    echo "  $0 manage bump           - Updates flake.lock and pushes to git"
    echo "=========================================="
}

# ==========================================
# HOST LEVEL
# ==========================================

function check_sudo() {
    # Check if we have root privileges or passwordless sudo
    if [ "$EUID" -ne 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            echo "[-] Error: System updates/cron setup require root privileges."
            echo "    Please run this script as 'root' or ensure your user"
            echo "    has passwordless 'sudo' configured."
            exit 1
        fi
    fi
}

function host_update_system() {
    echo "[+] Updating NixOS System (Pull-Only GitOps)..."
    cd "$SCRIPT_DIR"
    
    echo "[+] Pulling latest changes from Git repository..."
    git pull || echo "[-] Git pull failed, continuing anyway..."
    
    check_sudo
    sudo nixos-rebuild switch --flake .#${FLAKE_HOST}
    echo "[+] NixOS System update finished."
}

function host_update_services() {
    echo "[+] Updating Docker Services..."
    cd "$SCRIPT_DIR"
    
    echo "[+] Pulling latest changes from Git repository..."
    git pull || echo "[-] Git pull failed, continuing anyway..."
    
    if [ -d "$SCRIPT_DIR/docker" ]; then
        cd "$SCRIPT_DIR/docker"
        docker compose pull
        docker compose up -d
        echo "[+] Docker Services update finished."
    else
        echo "[-] Error: Docker directory '$SCRIPT_DIR/docker' not found."
    fi
}

function host_autoupdate() {
    check_sudo
    echo "=========================================="
    echo " Auto-Update Setup (Host Cron)"
    echo "=========================================="
    echo "What should be updated automatically on this host?"
    echo "1) All (System + Services)"
    echo "2) System only (NixOS)"
    echo "3) Services only (Docker)"
    read -p "Selection (1-3): " choice
    
    local cmd_arg=""
    case $choice in
        1) cmd_arg="host update all" ;;
        2) cmd_arg="host update system" ;;
        3) cmd_arg="host update services" ;;
        *) echo "Invalid selection."; exit 1 ;;
    esac

    echo ""
    echo "How often should the update run?"
    echo "1) Daily (at 04:00 AM)"
    echo "2) Weekly (Sunday at 04:00 AM)"
    echo "3) Custom cron expression"
    read -p "Selection (1-3): " schedule
    
    local cron_expr=""
    case $schedule in
        1) cron_expr="0 4 * * *" ;;
        2) cron_expr="0 4 * * 0" ;;
        3) read -p "Enter cron expression (e.g. '0 3 * * 1'): " cron_expr ;;
        *) echo "Invalid selection."; exit 1 ;;
    esac
    
    sudo mkdir -p /var/log/home-ai
    sudo touch /var/log/home-ai/autoupdate.log
    sudo chmod 666 /var/log/home-ai/autoupdate.log

    local cron_cmd="$cron_expr cd $SCRIPT_DIR && ./service.sh $cmd_arg >> /var/log/home-ai/autoupdate.log 2>&1"
    
    (crontab -l 2>/dev/null | grep -v "service.sh host update") | crontab -
    (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
    
    echo ""
    echo "[+] Host auto-update scheduled in crontab!"
    echo "    Schedule: $cron_expr"
    echo "    Command:  ./service.sh $cmd_arg"
}


# ==========================================
# MANAGEMENT LEVEL
# ==========================================

function install_distrobox() {
    echo "[+] Distrobox not found. Do you want to install it locally?"
    echo "    (Installs to ~/.local/bin without requiring sudo)"
    read -p "Install Distrobox? (y/N): " install_choice
    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
        echo "[+] Downloading and installing Distrobox..."
        curl -s https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix ~/.local
        export PATH="$HOME/.local/bin:$PATH"
        
        # We need Podman or Docker to run Distrobox. SteamOS usually has podman preinstalled.
        if ! command -v podman &> /dev/null && ! command -v docker &> /dev/null; then
            echo "[-] Warning: Podman or Docker is not installed on your system."
            echo "    Distrobox requires a container engine. On SteamOS, you might need to"
            echo "    install Podman or enable it. Please verify your container engine setup."
        fi
    else
        echo "[-] Setup aborted. Neither Nix nor Distrobox available."
        exit 1
    fi
}

function manage_bump() {
    echo "=========================================="
    echo " Management: Bump flake.lock"
    echo "=========================================="
    cd "$SCRIPT_DIR"
    
    # 1. Check for tools (Nix natively or distrobox)
    if command -v nix &> /dev/null; then
        echo "[+] Native 'nix' command found. Executing update..."
        nix flake update
        
    else
        if ! command -v distrobox &> /dev/null; then
            install_distrobox
        fi
        
        echo "[+] 'distrobox' found. Using containerized Nix environment..."
        
        # Check if container exists, create if not
        if ! distrobox list | grep -q "nix-env"; then
            echo "[+] Initializing 'nix-env' distrobox container..."
            distrobox create --name nix-env --image docker.io/nixos/nix:latest -Y
        fi
        
        echo "[+] Starting update inside the container..."
        distrobox enter nix-env -- nix flake update
    fi

    # 2. Check for changes and commit
    if git diff --name-only | grep -q "flake.lock"; then
        echo "[+] flake.lock has been updated. Committing..."
        git add flake.lock
        git commit -m "chore(flake): bump dependencies"
        
        echo "[+] Pushing changes to remote repository..."
        if git push; then
            echo "[+] Success! The host server will apply the update during its next cycle."
        else
            echo "[-] Push failed. Please run 'git push' manually."
        fi
    else
        echo "[+] flake.lock is already up to date. No changes pushed."
    fi
}

# ==========================================
# MAIN ROUTING
# ==========================================

case "$1" in
    host)
        case "$2" in
            update)
                case "$3" in
                    all) host_update_system; host_update_services ;;
                    system) host_update_system ;;
                    services) host_update_services ;;
                    *) print_help ;;
                esac
                ;;
            autoupdate) host_autoupdate ;;
            *) print_help ;;
        esac
        ;;
    manage)
        case "$2" in
            bump) manage_bump ;;
            *) print_help ;;
        esac
        ;;
    *)
        print_help
        ;;
esac
