#!/usr/bin/env bash
# Home-AI Service Script
# Bundles update processes for the host (server) and management (client).

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
FLAKE_HOST="home-ai-server" # Hostname matching flake.nix



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
    echo "  $0 manage bump           - Updates flake.lock (manually commit & push)"
    echo "  $0 manage bump --push    - Updates flake.lock, auto-commits & pushes to git"
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

function check_disk_space() {
    local min_gb=$1
    local partition=$2
    local free_space_kb=$(df -k "$partition" | awk 'NR==2 {print $4}')
    local free_space_gb=$((free_space_kb / 1024 / 1024))
    
    if [ "$free_space_gb" -lt "$min_gb" ]; then
        echo "[-] ERROR: Low disk space! Only ${free_space_gb}GB available on $partition."
        echo "    Require at least ${min_gb}GB to safely process updates."
        exit 1
    fi
    echo "[+] Disk space check passed: ${free_space_gb}GB available on $partition."
}

function host_update_system() {
    echo "[+] Updating NixOS System (Pull-Only GitOps)..."
    check_disk_space 5 /
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

function manage_bump() {
    local auto_push=$1
    echo "=========================================="
    echo " Management: Bump flake.lock"
    echo "=========================================="
    check_disk_space 2 .
    cd "$SCRIPT_DIR"
    
    # 1. Check for tools (Nix natively or container engine)
    local nix_flags="--extra-experimental-features \"nix-command flakes\""
    
    if command -v nix &> /dev/null; then
        echo "[+] Native 'nix' command found. Executing update..."
        eval "nix flake update $nix_flags"
        
    else
        echo "[+] Native Nix not found. Using containerized Nix environment..."
        
        local container_cmd=""
        if command -v podman &> /dev/null; then
            container_cmd="podman run --rm -v \"$SCRIPT_DIR:/workspace\" -w /workspace docker.io/nixos/nix:latest"
        elif command -v docker &> /dev/null; then
            # Use docker with current user ID to avoid writing root-owned files to the host
            container_cmd="docker run --rm --user $(id -u):$(id -g) -v \"$SCRIPT_DIR:/workspace\" -w /workspace docker.io/nixos/nix:latest"
        else
            echo "[-] Error: Neither native Nix, Podman, nor Docker are installed."
            echo "    Please install Podman on your Steam Deck to use this feature."
            exit 1
        fi
        
        echo "[+] Starting update inside a temporary container..."
        eval "$container_cmd nix flake update $nix_flags"
    fi

    # 2. Check for changes and commit
    if git diff --name-only | grep -q "flake.lock"; then
        echo "[+] flake.lock has been successfully updated!"
        
        if [ "$auto_push" == "--push" ]; then
            echo "[+] Auto-push flag provided. Committing..."
            git add flake.lock
            git commit -m "chore(flake): bump dependencies"
            
            echo "[+] Pushing changes to remote repository..."
            if git push; then
                echo "[+] Success! The host server will apply the update during its next cycle."
            else
                echo "[-] Push failed. Please run 'git push' manually."
            fi
        else
            echo "[i] Auto-push is disabled by default."
            echo "    Please review your changes and run 'git commit' and 'git push' manually."
        fi
    else
        echo "[+] flake.lock is already up to date."
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
            bump) manage_bump "$3" ;;
            *) print_help ;;
        esac
        ;;
    *)
        print_help
        ;;
esac
