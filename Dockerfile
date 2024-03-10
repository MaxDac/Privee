# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20240130-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.16.1-erlang-26.2.2-debian-bullseye-20240130-slim
#
ARG ELIXIR_VERSION=1.16.1
ARG OTP_VERSION=26.2.2
ARG DEBIAN_VERSION=bullseye-20240130-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

ARG ZIG_VERSION="0.11.0"

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git xz-utils wget \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /tmp

RUN wget https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz && \
  tar -xf zig-linux-x86_64-${ZIG_VERSION}.tar.xz && \
  mv zig-linux-x86_64-${ZIG_VERSION} /usr/local/lib/ && \
  ln -s /usr/local/lib/zig-linux-x86_64-${ZIG_VERSION}/zig /usr/local/bin/zig 

# prepare build dir
WORKDIR /app

# Copying NIFs files over
COPY nifs nifs

# Building Zig dependencies
RUN zig build --build-file nifs/build.zig -- /usr/local/lib/erlang/erts-14.2.2/include

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
COPY apps/privee/mix.exs ./apps/privee/mix.exs
COPY apps/privee_web/mix.exs ./apps/privee_web/mix.exs

RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY apps/privee/priv apps/privee/priv
COPY apps/privee_web/priv apps/privee_web/priv

COPY apps/privee/lib apps/privee/lib
COPY apps/privee_web/lib apps/privee_web/lib

COPY apps/privee_web/assets apps/privee_web/assets

# compile assets
RUN cd apps/privee_web && mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# Copy the NIFs files over
COPY nifs /app/_build/${mix_env}/rel/privee_umbrella/nifs

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${mix_env}/rel/privee_umbrella ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
