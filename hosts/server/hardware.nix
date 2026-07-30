# Placeholder: Hardware-Konfiguration
# Wird nach Ausführung von `nixos-generate-config` auf der B450M-Hardware oder 
# während des NixOS-Installations-Skripts mit den echten Werten gefüllt.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  # Hier folgen später Dateisysteme (fileSystems."/") und Bootloader-Hardware-Spezifika.
}
