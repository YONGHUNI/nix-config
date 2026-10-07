{
  pkgs,
  positron-slurm,
  ...
}:

let
  mkPositronSlurmCommand =
    name:
    pkgs.writeShellApplication {
      inherit name;

      runtimeInputs = with pkgs; [
        openssh
        gawk
        gnugrep
        coreutils
        iproute2
      ];

      text = ''
        exec ${pkgs.bash}/bin/bash \
          ${positron-slurm}/scripts/${name} "$@"
      '';
    };

  positron-slurm-start = mkPositronSlurmCommand "positron-slurm-start";
  positron-slurm-stop = mkPositronSlurmCommand "positron-slurm-stop";
  positron-slurm-tunnel = mkPositronSlurmCommand "positron-slurm-tunnel";
in
{
  home.packages = [
    positron-slurm-start
    positron-slurm-stop
    positron-slurm-tunnel
  ];

  # Local settings consumed by the helper scripts.
  xdg.configFile."positron-slurm/config".text = ''
    LOGIN_TARGET="sapelo"
    SHARED_DIR="/work/whlab/ys01849/.positron-slurm"
    LOCAL_PORT=22022
    PARTITION="inter_p"
  '';
}
