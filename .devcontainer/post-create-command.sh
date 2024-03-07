#!/bin/sh

git clone https://codeberg.org/MaxDac/dotfiles.git ~/.dotfiles && \
sh ~/.dotfiles/setup-environment.sh && \
sh ~/.dotfiles/install-neovim-tooling.sh && \
mix local.hex --force && \
mix local.rebar --force && \
mix archive.install --force hex phx_new && \
mix deps.get && \
mix deps.compile && \
zig build --build-file nifs/build.zig -- /usr/local/lib/erlang/erts-14.2.2/include