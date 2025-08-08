{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Загрузчик
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Хост/локали/время
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
    videoDrivers = [ "nvidia" ];
    xkb = {
      layout = "us,ru";
      variant = ",pc";
      options = "grp:ctrl_space_toggle,altwin:swap_alt_win";
    };

    displayManager.sddm.enable = true;
    displayManager.defaultSession = "none+bspwm";
    windowManager.bspwm.enable = true;
    libinput.enable = true;
  };

  # Аудио
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
  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true;
    nvidiaSettings = true;
    open = false; # проприетарный драйвер
    package = config.boot.kernelPackages.nvidiaPackages.production;
    powerManagement.enable = true;
  };
  hardware.nvidia.cudaSupport = true;

  # Сеть
  networking = {
    networkmanager = {
      enable = true;
      wifi.backend = "iwd";
    };
    useDHCP = false;
    dhcpcd.enable = false;
    firewall.enable = true;
    firewall.allowPing = true;
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
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;
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

  # Пакеты системы
  environment.systemPackages = with pkgs; [
    sudo
    git
    btrfs-progs
    mdadm
    iwd
    dhcpcd
    alacritty
    google-chrome
    gcc gnumake cmake pkg-config binutils autoconf automake libtool patch which
    unzip zip curl wget htop pciutils usbutils fwupd
    nvidia-vaapi-driver
  ];

  services.fwupd.enable = true;

  # Swap: 32 ГБ swapfile на btrfs (создастся автоматически с NOCOW)
  swapDevices = [
    { device = "/swap/swapfile"; size = 32 * 1024; }
  ];

  system.stateVersion = "24.11";
}
