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
#   - Ex: hexpm/elixir:1.18.4-erlang-28.0.1-debian-bullseye-20240130-slim
#
ARG TARGETPLATFORM="linux/amd64"
ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=28.0.1
ARG DEBIAN_VERSION=bookworm-20250610-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# Build argument for PHX_HOST with Fly.io as default
ARG PHX_HOST=privee.fly.dev

FROM ${BUILDER_IMAGE} AS builder

ARG TARGETPLATFORM
ARG PHX_HOST

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install Node.js early for better caching
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs

# prepare build dir
WORKDIR /app

# install hex + rebar early for better caching
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"
# Set PHX_HOST at build time for Phoenix compilation
ENV PHX_HOST=${PHX_HOST}

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

# Copy application code
COPY apps/privee/priv apps/privee/priv
COPY apps/privee_web/priv apps/privee_web/priv

COPY apps/privee/lib apps/privee/lib
COPY apps/privee_web/lib apps/privee_web/lib

# Copy assets and compile them
COPY apps/privee_web/assets apps/privee_web/assets

# compile assets
RUN npm ci --prefix apps/privee_web/assets && \
    npm run --prefix apps/privee_web/assets check && \
    mix assets.deploy --app apps/privee_web

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# Verify the release was built successfully
RUN ls -la _build/${MIX_ENV}/rel/privee_umbrella/ && \
    echo "Release built successfully"

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

# Install runtime dependencies
RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    # Debug utils, comment when done
    iputils-ping netcat-traditional sudo dnsutils telnet postgresql-client \
    libc6 libgcc-s1 && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/privee_umbrella ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
