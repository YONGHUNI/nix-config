{ dotfiles, ... }:

{
  home.file = {
    ".bashrc".source = "${dotfiles}/.bashrc";
    ".vimrc".source = "${dotfiles}/.vimrc";
    ".tmux.conf".source = "${dotfiles}/.tmux.conf";
    ".Rprofile".source = "${dotfiles}/.Rprofile";
  };
}
