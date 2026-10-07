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
  '';

  # Keep Positron on a simple localhost SSH target. The system OpenSSH
  # tunnel handles the login-node -> compute-node hop before Positron connects.
  # This is separate from ~/.ssh/config so the existing
  # remoteSSH.configFile setting can remain unchanged.
  home.file.".ssh/positron-slurm.conf".text = ''
    Host sapelo-slurm
        HostName 127.0.0.1
        Port 22022
        User ys01849

        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes

        HostKeyAlias sapelo-slurm
  '';
}
