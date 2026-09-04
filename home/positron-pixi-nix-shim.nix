{ pkgs, ... }:

let
  # Workaround for Positron R Pixi discovery on Nix/NixOS.
  # Positron looks for Pixi on PATH and then at ~/.pixi/bin/pixi. This shim
  # keeps Pixi project-local by delegating every call to the project's Nix
  # devShell instead of installing a global Pixi package.
  pixiNixShim = pkgs.writeShellApplication {
    name = "pixi";

    runtimeInputs = [
      pkgs.nix
      pkgs.coreutils
    ];

    text = ''
      # Canonicalize the working directory because Nix path: inputs reject
      # paths whose intermediate components are symlinks (for example ~/data
      # pointing at /data/<user> on a research host).
      project_dir="$(pwd -P)"

      # Positron uses --manifest-path when activating an already-discovered
      # Pixi environment. Prefer that path when available because activation
      # is not guaranteed to run with the project root as the current directory.
      args=("$@")
      for ((i = 0; i < ''${#args[@]}; i++)); do
        case "''${args[$i]}" in
          --manifest-path)
            if ((i + 1 >= ''${#args[@]})); then
              echo "pixi-nix-shim: --manifest-path requires a value" >&2
              exit 64
            fi
            manifest="''${args[$((i + 1))]}"
            project_dir="$(dirname "$(realpath "$manifest")")"
            break
            ;;
          --manifest-path=*)
            manifest="''${args[$i]#--manifest-path=}"
            project_dir="$(dirname "$(realpath "$manifest")")"
            break
            ;;
        esac
      done

      # The Pixi manifest may live below the flake root. Walk upward and use
      # the nearest flake so each project keeps control of its pinned Pixi.
      flake_root="$project_dir"
      while [[ "$flake_root" != "/" && ! -f "$flake_root/flake.nix" ]]; do
        flake_root="$(dirname "$flake_root")"
      done

      if [[ ! -f "$flake_root/flake.nix" ]]; then
        echo "pixi-nix-shim: no flake.nix found from $project_dir upward" >&2
        exit 127
      fi

      # Resolve any remaining symlinks before passing the flake root to Nix.
      flake_root="$(realpath "$flake_root")"

      # Guard against accidental recursion if a devShell does not provide
      # Pixi and this shim is also present on that shell's PATH.
      if [[ "''${PIXI_NIX_SHIM_ACTIVE:-0}" == "1" ]]; then
        echo "pixi-nix-shim: recursive invocation detected; does this flake provide pixi?" >&2
        exit 126
      fi
      export PIXI_NIX_SHIM_ACTIVE=1

      exec nix develop "$flake_root" -c pixi "$@"
    '';
  };
in
{
  home.file.".pixi/bin/pixi".source = "${pixiNixShim}/bin/pixi";
}
