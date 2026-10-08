# Multi-stage release image, based on `mix phx.gen.release --docker`.
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - builder image
#   - https://hub.docker.com/_/debian?tab=tags - runner image
#
# Keep ELIXIR_VERSION / OTP_VERSION in sync with .tool-versions.
ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29.1.1
ARG DEBIAN_VERSION=trixie-20261005-slim
ARG NODE_MAJOR=24

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

ARG NODE_MAJOR

# install build dependencies (Node.js is needed for the daisyUI npm package)
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git curl ca-certificates \
  && curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
COPY apps/privee/mix.exs apps/privee/mix.exs
COPY apps/privee_web/mix.exs apps/privee_web/mix.exs
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

RUN mix compile

COPY apps/privee_web/assets apps/privee_web/assets

# compile assets (tailwind/esbuild binaries are downloaded on first use)
RUN npm ci --omit=dev --prefix apps/privee_web/assets \
  && mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Source code of this build, reported to users (AGPL-3.0). The publish
# workflow sets it to the building repository; PRIVEE_SOURCE_URL at runtime
# still takes precedence, and an empty value falls back to upstream.
ARG PRIVEE_SOURCE_URL=""
ENV PRIVEE_SOURCE_URL="${PRIVEE_SOURCE_URL}"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/privee_umbrella ./

USER nobody

CMD ["/app/bin/server"]
