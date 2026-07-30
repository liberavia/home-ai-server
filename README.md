# Home-AI & Smart-Home Server (NixOS)

Willkommen im Konfigurations-Repository für meinen lokalen Home-AI- und Smart-Home-Server inkl. Full-Stack-Workstation. 
Das gesamte System wird von mir vollständig deklarativ über NixOS (Flakes) aufgebaut, was mir einen sauberen, reproduzierbaren GitOps-Ansatz bietet.

## Projekt-Ziele
- Ein einheitliches System, das mir sowohl als lokaler KI-/Automatisierungs-Server als auch als Desktop-Workstation dient.
- Alles deklarativ in Code gegossen – keine manuelle System-Bastelei.
- Ausführung lokaler KI-Modelle ohne Cloud-Zwang.
- Zuverlässige Smart-Home-Automatisierung mit Home Assistant und n8n.

## Software-Stack
* **OS:** NixOS (Unstable) mit Flakes
* **Desktop:** KDE Plasma 6 (inkl. Yakuake, Flatpak-Support, Steam)
* **AI-Inference:** Ollama (Nvidia CUDA beschleunigt) für Llama, Qwen & Gemma
* **Container-Infrastruktur (Docker):**
  * **Home Assistant** (Smart Home)
  * **n8n** (Automatisierung)
  * **Nextcloud** (Dateiablage, CalDAV & Workspace für Agenten)
  * **PostgreSQL** (Datenbank-Backend)
  * **Agent-Harness** (Abgesicherte Testumgebung für KI-Agenten)
* **Dev & Kreativ:** `agy` CLI, Git, Node.js, Godot 4, GIMP, Inkscape, LibreOffice

## Repository-Struktur
```text
home-ai-server/
├── flake.nix                  # Flake-Einstiegspunkt
├── SETUP_GUIDE.md             # Schritt-für-Schritt Installations-Anleitung
├── hosts/
│   └── server/
│       ├── configuration.nix  # Systemweite Basis-Einstellungen
│       └── hardware.nix       # Generierte Hardware-Konfiguration (Hardware-spezifisch)
├── modules/
│   ├── desktop.nix            # Plasma 6, Apps, Steam, Drucker, Flatpak, Dev-Tools
│   └── ai-services.nix        # Ollama (CUDA), Docker-Stack, Firewall
└── docker/
    └── docker-compose.yml     # Container-Setup (n8n, Nextcloud, HA, etc.)
```

## Installation & Setup
Eine detaillierte Schritt-für-Schritt-Anleitung zur Ersteinrichtung auf einem leeren System (mittels NixOS Minimal ISO) befindet sich im Setup-Guide:

[Hier geht es zur SETUP_GUIDE.md](SETUP_GUIDE.md)

---

## Nächste Ausbaustufen
- Reibungslose Migration der GPU von NVIDIA GTX 1660 Super auf AMD Radeon RX 6650 XT (lediglich durch Anpassung der Deklarationen in `ai-services.nix`).
- Ausbau meiner n8n-Workflows (Webhooks, Nextcloud-APIs, CalDAV), um KI-Agenten die selbstständige Interaktion mit meinen Dateien und Terminen zu ermöglichen.
