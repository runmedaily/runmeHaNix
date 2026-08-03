{ config, pkgs, lib, ... }:

let cfg = config.services.runme.shell; in
{
  options.services.runme.shell = {
    enable = lib.mkEnableOption "Server shell environment (ZSH, starship, core tools)";
  };

  config = lib.mkIf cfg.enable {
    programs.zsh = {
      enable = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      ohMyZsh = {
        enable = true;
        plugins = [ "git" "sudo" "systemd" ];
        theme = "robbyrussell";
      };
      interactiveShellInit = ''
        fastfetch
        # OSC 52 remote clipboard — pipe output to yank to copy to local clipboard over SSH
        # Usage: echo "hello" | yank    or    cat file.log | yank
        yank() {
          local data=$(base64 | tr -d '\n')
          printf "\033]52;c;%s\a" "$data"
        }
      '';
      shellAliases = {
        nrs = "sudo nix flake update --flake /etc/nixos && sudo nixos-rebuild switch --flake /etc/nixos#default";
      };
    };

    # Prevent the ZSH new-user wizard from appearing
    system.activationScripts.zshrc = lib.stringAfter [ "users" ] ''
      for dir in /root /home/*; do
        if [ -d "$dir" ] && [ ! -f "$dir/.zshrc" ]; then
          touch "$dir/.zshrc"
        fi
      done
    '';

    programs.starship.enable = lib.mkDefault true;

    environment.systemPackages = with pkgs; [
      tmux
      git
      curl
      wget
      htop
      btop
      fastfetch
      unzip
      eza
      bat
      ripgrep
      fd
      fzf
      ranger
      starship
      cowsay
      kitty.terminfo
    ];

    services.xserver.enable = lib.mkDefault false;
  };
}
