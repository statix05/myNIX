{ config, pkgs, lib, astronvim, ... }:

{
  home.username = "statix";
  home.homeDirectory = "/home/statix";
  home.stateVersion = "24.11";

  home.packages = with pkgs; [
    bspwm
    sxhkd
    polybar
    (pkgs.picom-pijulius or pkgs.picom) # fallback, если pijulius недоступен в канале
    rofi
    feh
  ];

  programs.starship.enable = true;

  programs.zsh = {
    enable = true;
    dotDir = ".config/zsh";
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" "fzf" "sudo" ];
    };
    initExtra = ''
      bindkey -e
      export EDITOR="nvim"
      export LANG=ru_RU.UTF-8
      export LC_ALL=ru_RU.UTF-8
      eval "$(starship init zsh)"
      [ -f ${pkgs.fzf}/share/fzf/key-bindings.zsh ] && source ${pkgs.fzf}/share/fzf/key-bindings.zsh
      [ -f ${pkgs.fzf}/share/fzf/completion.zsh ] && source ${pkgs.fzf}/share/fzf/completion.zsh
    '';
    shellAliases = {
      ll = "ls -lah";
      gs = "git status";
      gc = "git commit";
      ga = "git add";
      gl = "git log --oneline --graph --decorate";
      rebuild = "sudo nixos-rebuild switch --flake /etc/nixos#svetos";
      update = "cd /etc/nixos && sudo nix flake update && sudo nixos-rebuild switch --flake .#svetos";
    };
  };

  programs.alacritty = {
    enable = true;
    settings = {
      window = { opacity = 0.95; decorations = "full"; };
      font = {
        normal = { family = "JetBrainsMono Nerd Font"; style = "Regular"; };
        bold = { family = "JetBrainsMono Nerd Font"; style = "Bold"; };
        italic = { family = "JetBrainsMono Nerd Font"; style = "Italic"; };
        size = 13.0;
      };
    };
  };

  xresources.properties = {
    "Xft.dpi" = 144;
    "Xft.antialias" = 1;
    "Xft.hinting" = 1;
    "Xft.hintstyle" = "hintslight";
    "Xft.rgba" = "rgb";
  };

  xdg.configFile."bspwm/bspwmrc".text = ''
    #!/usr/bin/env sh
    bspc monitor -d 1 2 3 4 5 6 7 8 9
    bspc config border_width         2
    bspc config window_gap           8
    bspc config split_ratio          0.52
    bspc config borderless_monocle   true
    bspc config gapless_monocle      true
    bspc config focus_follows_pointer true

    pgrep -x sxhkd >/dev/null || sxhkd &
    pgrep -x picom >/dev/null || picom --experimental-backends &
    if command -v polybar >/dev/null; then
      killall -q polybar
      while pgrep -x polybar >/dev/null; do sleep 0.2; done
      polybar main &
    fi
  '';
  xdg.configFile."bspwm/bspwmrc".mode = "0755";

  xdg.configFile."sxhkd/sxhkdrc".text = ''
    super + Return
      alacritty
    super + Shift + r
      bspc wm -r
    super + q
      bspc node -c
    super + {h,j,k,l}
      bspc node -f {west,south,north,east}
    super + shift + {h,j,k,l}
      bspc node -s {west,south,north,east}
    super + {1-9}
      bspc desktop -f {1-9}
    super + shift + {1-9}
      bspc node -d {1-9}
  '';

  xdg.configFile."polybar/config.ini".text = ''
    [bar/main]
    width = 100%
    height = 30
    dpi = 144
    background = #AA1E1E2E
    foreground = #ECEFF4
    font-0 = JetBrainsMono Nerd Font:style=Regular:size=10;3
    modules-left = bspwm
    modules-center =
    modules-right = date
    tray-position = right

    [module/bspwm]
    type = internal/bspwm

    [module/date]
    type = internal/date
    interval = 1
    date = %Y-%m-%d %H:%M:%S
  '';

  xdg.configFile."picom/picom.conf".text = ''
    backend = "glx";
    vsync = true;
    corner-radius = 8.0;
    round-borders = 1;
    glx-no-stencil = true;
    detect-rounded-corners = true;
    detect-client-leader = true;
    shadow = true;
    shadow-radius = 12;
    shadow-opacity = 0.35;
    fading = true;
    fade-in-step = 0.03;
    fade-out-step = 0.03;
    opacity-rule = [ "90:class_g *= 'Alacritty'" ];
  '';

  # AstroNvim из input
  xdg.configFile."nvim".source = astronvim;

  xdg.configFile."nvim/lua/user/init.lua".text = ''
    return {
      colorscheme = "habamax",
    }
  '';
}
