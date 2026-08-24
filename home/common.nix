{ dotfiles, ... }:

{
  home.file = {
    ".bash_profile".text = ''
      if [ -f ~/.bashrc ]; then
        . ~/.bashrc
      fi
    '';
    ".bashrc".source = "${dotfiles}/.bashrc";
    ".vimrc".source = "${dotfiles}/.vimrc";
    ".tmux.conf".source = "${dotfiles}/.tmux.conf";
  };
}
