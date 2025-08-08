{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Хост/локаль/время
  networking.hostName = "svetos";
  time.timeZone = "Europe/Moscow";

  i18n.defaultLocale = "ru_RU.UTF-8";
  i18n.supportedLocales = [
    "ru_RU.UTF-8/UTF-8"
    "en_US.UTF-8/UTF-8"
  ];

  # X11 + SDDM + BSPWM
  services.xserver = {
    enable = true;
    xkb = {
      layout = "us,ru";
      # второй раскладке (ru) задаём вариант "pc"
      variant = ",pc";
      options = "grp:ctrl_space_toggle,altwin:swap_alt_win";
    };

    displayManager.sddm.enable = true;
    displayManager.defaultSession = "none+bspwm";
    windowManager.bspwm.enable = true;
    libinput.enable = true;
  };

  # Аудио (PipeWire)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # NVIDIA + CUDA
  hardware.graphics.enable = true;        # GL, VA-API базово
  hardware.nvidia = {
    modesetting.enable = true;
    nvidiaSettings = true;
    open = false; # проприетарный драйвер
    package = config.boot.kernelPackages.nvidiaPackages.production;
    powerManagement.enable = true;
    # PRIME не настраиваю специально: предполагаю мониторы на dGPU.
  };
  hardware.nvidia.cudaSupport = true;

  # Видео-ускорение для NVIDIA через VA-API
  environment.systemPackages = with pkgs; [
    nvidia-vaapi-driver
  ];

  # NetworkManager с iwd
  networking = {
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
    # избегаем конфликтов
    useDHCP = false;
    dhcpcd.enable = false;
    firewall.enable = true;
    firewall.allowPing = true;
    # SSH
    hostName = "svetos";
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
  };

  # Шрифты
  fonts = {
    packages = with pkgs; [
      jetbrains-mono
      (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
      inter
      noto-fonts
      noto-fonts-emoji
      noto-fonts-cjk
    ];
    enableDefaultPackages = true;
  };

  # Пользователь
  users.mutableUsers = true;
  users.users.statix = {
    isNormalUser = true;
    description = "Statix";
    extraGroups = [ "wheel" "video" "audio" "networkmanager" "input" ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
  security.sudo.enable = true;

  # Автообновления и GC
  system.autoUpgrade = {
    enable = true;
    allowReboot = false;
    flake = "path:/etc/nixos";
    dates = "daily";
  };

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # Пакеты системы (минимум, остальное — в home)
  environment.systemPackages = with pkgs; [
    sudo
    git
    btrfs-progs
    mdadm             # на всякий случай, для диагностики RAID (мы используем btrfs-raid0)
    iwd
    dhcpcd
    alacritty
    google-chrome
    gcc
    gnumake
    cmake
    pkg-config
    unzip
    zip
    curl
    wget
    htop
    pciutils
    usbutils
    fwupd
  ];

  programs.firefox.enable = false; # Используем Chrome
  services.fwupd.enable = true;

  # Swap: 32ГБ swapfile на btrfs (создастся автоматически с NOCOW)
  swapDevices = [
    { device = "/swap/swapfile"; size = 32 * 1024; }
  ];

  # HiDPI (общесистемно в X11 это не трогаем, см. Xresources в home)
  # Можно будет тонко подстроить dpi/scale при желании.

  # Unfree/канал уже включены в flake через pkgs.config.allowUnfree
  system.stateVersion = "24.11";
}
