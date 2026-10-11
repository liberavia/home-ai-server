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
    echo "  $0 host stage            - Pull git changes, stage NixOS into bootloader"
    echo "                             & pre-pull Docker images (NO reboot, NO disruption)"
    echo "  $0 host auto-run         - Background GitOps runner (checks remote, stages if new commit,"
    echo "                             notifies KDE desktop & bot/webhook)"
    echo "  $0 host status           - Check update state, pending reboot flag & generations"
    echo "  $0 host update all       - Pull git changes, apply immediately (switch NixOS & up Docker)"
    echo "  $0 host update system    - Pull git changes & switch NixOS immediately"
    echo "  $0 host update services  - Pull git changes & update Docker immediately"
    echo "  $0 host autoupdate       - Info on systemd auto-upgrade timer & logs"
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

function host_notify_kde() {
    local title="$1"
    local message="$2"
    local urgency="${3:-critical}"
    
    local user_bus="/run/user/1000/bus"
    if [ -S "$user_bus" ]; then
        echo "[+] Sending KDE desktop notification..."
        sudo -u deck DBUS_SESSION_BUS_ADDRESS="unix:path=$user_bus" \
            notify-send -u "$urgency" -i system-software-update "$title" "$message" 2>/dev/null || true
    fi
}

function host_notify_bot() {
    local payload="$1"
    local webhook_url="http://localhost:5678/webhook/system-update"
    if curl -s -m 2 http://localhost:5678 &>/dev/null; then
        echo "[+] Sending notification to n8n webhook..."
        curl -s -m 5 -X POST -H "Content-Type: application/json" -d "$payload" "$webhook_url" &>/dev/null || true
    fi
}

function host_write_status() {
    local status="$1"
    local details="$2"
    local timestamp
    timestamp=$(date -Iseconds)
    
    mkdir -p /var/log/home-ai
    
    if [ "$status" == "reboot_required" ]; then
        touch /run/reboot-required
    elif [ "$status" == "up_to_date" ]; then
        rm -f /run/reboot-required
    fi
    
    cat <<EOF > /var/log/home-ai/update-status.json
{
  "status": "$status",
  "timestamp": "$timestamp",
  "details": "$details",
  "reboot_required": $([ "$status" == "reboot_required" ] && echo "true" || echo "false")
}
EOF
    chmod 644 /var/log/home-ai/update-status.json 2>/dev/null || true
}

function host_status() {
    echo "=========================================="
    echo " Home-AI Server Update Status"
    echo "=========================================="
    if [ -f /run/reboot-required ]; then
        echo "[!] Status: REBOOT REQUIRED (New generation staged in bootloader)"
    else
        echo "[+] Status: No reboot pending"
    fi
    
    if [ -f /var/log/home-ai/update-status.json ]; then
        echo ""
        echo "Last update log (/var/log/home-ai/update-status.json):"
        cat /var/log/home-ai/update-status.json
        echo ""
    fi
    
    cd "$SCRIPT_DIR"
    echo "Git Status:"
    echo "  Current commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown') - $(git log -1 --pretty=%s 2>/dev/null || echo '')"
    if git ls-remote origin main &>/dev/null; then
        local remote_commit
        remote_commit=$(git ls-remote origin main | awk '{print $1}')
        local local_commit
        local_commit=$(git rev-parse HEAD 2>/dev/null || echo '')
        if [ "$remote_commit" != "$local_commit" ]; then
            echo "  [!] Remote origin/main has newer commits!"
        else
            echo "  [+] Local is in sync with origin/main."
        fi
    fi
    echo "=========================================="
}

function host_stage_update() {
    echo "[+] Staging Home-AI Update (Non-disruptive background build)..."
    check_disk_space 5 /
    cd "$SCRIPT_DIR"
    
    echo "[+] Pulling latest changes from Git repository..."
    git pull || echo "[-] Git pull failed, continuing anyway..."
    
    check_sudo
    echo "[+] Building and staging NixOS system into bootloader (nixos-rebuild boot)..."
    sudo nixos-rebuild boot --flake .#${FLAKE_HOST}
    
    if [ -d "$SCRIPT_DIR/docker" ]; then
        echo "[+] Pre-pulling Docker service images in background..."
        cd "$SCRIPT_DIR/docker"
        docker compose pull || echo "[-] Docker pull warning, continuing..."
    fi
    
    local commit_msg
    commit_msg=$(git log -1 --pretty=%s 2>/dev/null || echo "Update")
    
    host_write_status "reboot_required" "NixOS generation staged and Docker images pulled. Commit: $commit_msg"
    
    host_notify_kde "Home-AI: Update bereit" "Ein System-Update wurde im Hintergrund vorbereitet. Bitte starte das System bei Gelegenheit neu." "critical"
    
    host_notify_bot "{\"event\":\"update_staged\",\"reboot_required\":true,\"commit\":\"$commit_msg\",\"timestamp\":\"$(date -Iseconds)\"}"
    
    echo ""
    echo "[+] SUCCESS: Update successfully staged!"
    echo "    - NixOS bootloader updated."
    echo "    - Docker images cached."
    echo "    - /run/reboot-required created."
    echo "    - KDE desktop and Bot notified."
    echo "    Your active applications are uninterrupted. Please reboot when convenient."
}

function host_auto_run() {
    echo "=========================================="
    echo " Home-AI GitOps Auto-Update Check: $(date)"
    echo "=========================================="
    cd "$SCRIPT_DIR"
    
    echo "[+] Checking for remote updates on origin/main..."
    if ! git fetch origin main --quiet; then
        echo "[-] Network unreachable or git fetch failed. Skipping cycle."
        exit 0
    fi
    
    local local_rev
    local remote_rev
    local_rev=$(git rev-parse HEAD 2>/dev/null || echo "local")
    remote_rev=$(git rev-parse origin/main 2>/dev/null || echo "remote")
    
    if [ "$local_rev" == "$remote_rev" ]; then
        echo "[+] System is already up to date with origin/main. Nothing to do."
        exit 0
    fi
    
    echo "[+] New commits detected on origin/main ($local_rev -> $remote_rev)."
    echo "[+] Proceeding with staging update..."
    host_stage_update
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
    echo " Auto-Update Info (NixOS Systemd Timer)"
    echo "=========================================="
    echo "Auto-update is natively managed via the NixOS module (modules/auto-upgrade.nix)."
    echo ""
    echo "Checking systemd timer status:"
    systemctl status home-ai-autoupdate.timer || true
    echo ""
    echo "To test the background runner immediately:"
    echo "  sudo systemctl start home-ai-autoupdate.service"
    echo ""
    echo "To follow recent auto-update logs:"
    echo "  journalctl -u home-ai-autoupdate.service -e"
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
            stage) host_stage_update ;;
            auto-run) host_auto_run ;;
            status) host_status ;;
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
