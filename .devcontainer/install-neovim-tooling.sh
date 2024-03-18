#!/bin/sh

git clone https://codeberg.org/MaxDac/dotfiles.git ~/.dotfiles || true && \
sh ~/.dotfiles/setup-environment.sh && \
sh ~/.dotfiles/install-neovim-tooling.sh && \
zsh asdf plugin add neovim && \
zsh asdf plugin add tmux && \
zsh asdf install neovim && \
zsh asdf install tmux 