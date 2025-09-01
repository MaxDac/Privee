#!/bin/sh

mix local.hex --force && \
mix local.rebar --force && \
mix archive.install --force hex phx_new && \
mix deps.get && \
mix deps.compile && \
mix ecto.create && \
mix ecto.migrate && \
npm i --prefix apps/privee_web/assets
