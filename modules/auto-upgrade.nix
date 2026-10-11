{ config, pkgs, lib, ... }:

let
  # Mögliche Pfade des Git-Repositories auf dem Host
  defaultRepoPath = "/home/deck/Development/home-ai-server";
in
{
  # Werkzeuge für Benachrichtigungen und Statusabfragen bereitstellen
  environment.systemPackages = with pkgs; [
    libnotify # Für notify-send auf den Desktop
    jq        # Für JSON-Verarbeitung im Statusfile
    curl      # Für Webhook-Aufrufe an n8n
  ];

  # Git Dubious Ownership für Root-Zugriff auf das User-Repo verhindern
  programs.git = {
    enable = true;
    config = {
      safe.directory = "*";
    };
  };

  # Log-Verzeichnis für Home-AI vorbereiten
  systemd.tmpfiles.rules = [
    "d /var/log/home-ai 0755 root root -"
  ];

  # -------------------------------------------------------------
  # Systemd Auto-Update Service (Pull-Only GitOps)
  # -------------------------------------------------------------
  systemd.services.home-ai-autoupdate = {
    description = "Home-AI Server GitOps Auto-Update Service (Background Staging)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    path = with pkgs; [
      git
      nix
      nixos-rebuild
      docker
      docker-compose
      libnotify
      curl
      jq
      coreutils
      gnugrep
      gawk
      bash
      procps
      util-linux
      openssh
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "home-ai-autoupdate-runner" ''
        set -e
        REPO_DIR=""
        for candidate in "${defaultRepoPath}" "/home/deck/home-ai-server" "/etc/nixos"; do
          if [ -d "$candidate/.git" ] && [ -f "$candidate/service.sh" ]; then
            REPO_DIR="$candidate"
            break
          fi
        done

        if [ -z "$REPO_DIR" ]; then
          echo "[-] Error: home-ai-server repository not found in expected locations." >&2
          exit 1
        fi

        echo "[+] Found repository at $REPO_DIR"
        cd "$REPO_DIR"
        exec ./service.sh host auto-run
      '';
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };

  # -------------------------------------------------------------
  # Systemd Auto-Update Timer (Täglich um 04:00 Uhr mit Random Delay)
  # -------------------------------------------------------------
  systemd.timers.home-ai-autoupdate = {
    description = "Timer for Home-AI Server GitOps Auto-Update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };
}
