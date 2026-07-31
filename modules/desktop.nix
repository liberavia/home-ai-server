{ config, pkgs, ... }:

{
  # X11 & Wayland / SDDM & Plasma 6
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };
  console.keyMap = "de";

  # Sound mit Pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # HP Drucker & Scanner (CUPS & SANE)
  services.printing = {
    enable = true;
    drivers = [ pkgs.hplipWithPlugin ];
  };
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.hplipWithPlugin ];
  };
  
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Gaming
  programs.steam.enable = true;

  # Flatpak Support
  services.flatpak.enable = true;

  # Pakete & Dev-Tools
  environment.systemPackages = with pkgs; [
    git
    nodejs_22 # Für npm und ggf. agy CLI
    kdePackages.yakuake

    # Grafik & Kreativ
    gimp
    inkscape
    libreoffice-fresh
    
    # Gamedev
    godot_4
  ];
}
