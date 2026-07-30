# NixOS Installation Guide (Flakes)

Diese Anleitung führt dich Schritt für Schritt durch die Installation deines Home-AI-Servers auf der MSI B450M-Hardware.

## Schritt 1: Installations-Medium vorbereiten
1. Lade dir die aktuelle **NixOS Minimal ISO** von der [offiziellen Website](https://nixos.org/download/) herunter.
2. Flashe die ISO-Datei auf einen USB-Stick (z. B. mit BalenaEtcher, Rufus oder Ventoy).

## Schritt 2: Booten & Netzwerk herstellen
1. Schließe den USB-Stick an deinen neuen Server an und boote davon.
2. Schließe ein LAN-Kabel an, um sofort eine Internetverbindung zu haben.
   *(Falls du WLAN nutzen musst, tippe `nmtui` für ein grafisches Tool zur WLAN-Einrichtung).*

## Schritt 3: Festplatte partitionieren & formatieren
Wir richten ein typisches UEFI-Layout (GPT) mit Boot- und Root-Partition ein.
1. Finde den Namen deiner Festplatte mit dem Befehl heraus:
   ```bash
   lsblk
   ```
   (Merke dir den Namen, z. B. `/dev/nvme0n1` oder `/dev/sda`)
2. Öffne das Partitionierungstool: 
   ```bash
   cfdisk /dev/deine_festplatte
   ```
3. Wähle **GPT** als Partitionstabelle.
4. Erstelle folgende Partitionen:
   - **Partition 1 (Boot):** Größe ca. `512M`. Danach im Menü auf `Type` gehen und `EFI System` auswählen.
   - **Partition 2 (Root):** Den restlichen Speicherplatz. Der `Type` bleibt auf `Linux filesystem`.
   - Wähle `Write`, tippe `yes` und bestätige mit Enter. Beende das Tool mit `Quit`.
5. Formatiere die Partitionen (Passe die Zahlen an, z.B. `nvme0n1p1` / `sda1`):
   ```bash
   mkfs.fat -F 32 -n boot /dev/deine_efi_partition
   mkfs.ext4 -L nixos /dev/deine_root_partition
   ```

## Schritt 4: Partitionen einhängen (Mounten)
```bash
mount /dev/deine_root_partition /mnt
mkdir -p /mnt/boot
mount /dev/deine_efi_partition /mnt/boot
```

## Schritt 5: Hardware-Konfiguration generieren
NixOS scannt nun deine Mainboard-Chips und Kernel-Module (GTX 1660) und speichert diese lokal ab:
```bash
nixos-generate-config --root /mnt
```

## Schritt 6: Dein Repository ins Live-System laden
Wir laden dein vorbereitetes Git-Repository herunter.
```bash
# Git aktivieren
nix-shell -p git

# Dein Repo auf die Festplatte klonen (Passe die URL an!)
git clone https://github.com/DEIN_GITHUB_NAME/home-ai-server.git /mnt/home-ai-server
cd /mnt/home-ai-server

# Platzhalter mit der echten Hardware-Konfiguration überschreiben:
cp /mnt/etc/nixos/hardware-configuration.nix ./hosts/server/hardware.nix

# WICHTIG: Die Datei muss in den Git-Index, damit Flakes sie erkennen!
git add hosts/server/hardware.nix
```

## Schritt 7: Das System installieren
Der Build-Prozess deines Systems beginnt:
```bash
nixos-install --flake .#home-ai-server
```
*Lehne dich zurück. NixOS lädt und baut nun KDE Plasma, Docker, Ollama und Co. Am Ende wirst du gebeten, ein Root-Passwort zu vergeben.*

## Schritt 8: Neustart & Nutzer-Passwort setzen
```bash
reboot
```
Entferne den USB-Stick, sobald der Bildschirm schwarz wird. Das System bootet in den KDE Login-Screen.
Da dein User `deck` noch kein Passwort hat:
1. Drücke am grafischen Login-Screen `Strg + Alt + F2` um ins Text-Terminal zu wechseln.
2. Logge dich als `root` mit dem Passwort aus Schritt 7 ein.
3. Vergib das Nutzer-Passwort: `passwd deck`
4. Drücke `Strg + Alt + F1` (oder `F7`), um zum GUI zurückzukehren und logge dich ein.

Willkommen auf deinem neuen NixOS-Server! Öffne Yakuake (mit F12) und lege los!
