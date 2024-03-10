#!/bin/sh

git clone https://codeberg.org/MaxDac/dotfiles.git ~/.dotfiles && \
sh ~/.dotfiles/setup-environment.sh && \
sh ~/.dotfiles/install-neovim-tooling.sh && \
zsh && \
asdf plugin add neovim && \
asdf plugin add elixir && \
asdf plugin add erlang && \
asdf plugin add nodejs && \
asdf plugin add tmux
