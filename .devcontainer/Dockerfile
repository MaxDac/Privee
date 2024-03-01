FROM hexpm/elixir:1.16.1-erlang-26.2.2-debian-bookworm-20240130-slim AS elixir-build

RUN apt-get update && \
  apt-get install -y git && \
  apt-get install -y postgresql-client && \
  apt-get install -y inotify-tools && \
  apt-get install -y curl && \
  apt-get install -y wget && \
  apt-get install -y gnupg2 && \
  apt-get install -y dirmngr && \
  apt-get install -y gpg && \
  apt-get install -y gawk
