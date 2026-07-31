{ config, pkgs, ... }:

{
  # --- GPU & Grafiktreiber ---
  # Aktuell: NVIDIA GTX 1660 Super
  services.xserver.videoDrivers = [ "nvidia" ];
  
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = false; 
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # TODO für spätere Migration auf AMD RX 6650 XT:
  # services.xserver.videoDrivers = [ "amdgpu" ];
  # environment.variables.HSA_OVERRIDE_GFX_VERSION = "10.3.0";
  # hardware.nvidia.* komplett entfernen!


  # --- KI / Ollama ---
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda; # Nach GPU-Tausch auf pkgs.ollama-rocm ändern
  };


  # --- Docker & Container ---
  virtualisation.docker = {
    enable = true;
  };
  hardware.nvidia-container-toolkit.enable = true; # Für GPU-Zugriff in Containern


  # --- Firewall für Home-AI-Dienste ---
  networking.firewall.allowedTCPPorts = [ 
    8123 # Home Assistant
    5678 # n8n
    8080 # Nextcloud (falls Host-Port gemappt)
  ];
}
