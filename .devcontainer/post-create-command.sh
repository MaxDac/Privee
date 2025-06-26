#!/bin/sh

mix local.hex --force && \
mix local.rebar --force && \
mix archive.install --force hex phx_new && \
mix deps.get && \
mix deps.compile && \
zig build --build-file nifs/build.zig -- /usr/local/lib/erlang/erts-16.0.1/include && \
mix ecto.create && \
mix ecto.migrate && \
npm i --prefix apps/privee_web/assets
