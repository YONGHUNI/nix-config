{ dotfiles, ... }:

{
  # Positron looks for Pixi on PATH and then at ~/.pixi/bin/pixi.
  # Keep the shim itself in the shared dotfiles repository so NixOS/Home
  # Manager hosts and rootless Linux hosts use exactly the same implementation.
  #
  # The shared shim invokes the project's `apps.<system>.pixi` with `nix run`
  # rather than entering `nix develop`, preventing devShell variables from
  # leaking into Positron's Pixi activation environment.
  home.file.".pixi/bin/pixi".source = "${dotfiles}/bin/pixi-nix-shim";
}
