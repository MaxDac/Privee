FROM hexpm/elixir:1.16.1-erlang-26.2.2-debian-bookworm-20240130-slim as builder

# Setting the SMTP password
ARG MAIL_PASS  

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git npm xz-utils \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Installing zig compiler
WORKDIR /tmp

RUN wget https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz && \
  tar -xf zig-linux-x86_64-0.11.0.tar.xz && \
  mv zig-linux-x86_64-0.11.0 /usr/local/lib/ && \
  ln -s /usr/local/lib/zig-linux-x86_64-0.11.0/zig /usr/local/bin/zig

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"
ENV MAIL_PASS=${MAIL_PASS}

# install mix dependencies
COPY mix.exs mix.lock ./
COPY apps/stygian/mix.exs ./apps/stygian/mix.exs
COPY apps/stygian_web/mix.exs ./apps/stygian_web/mix.exs

RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs  config/config.exs
COPY config/${MIX_ENV}.exs config/${MIX_ENV}.exs

RUN cd /app

# Building Zig dependency
RUN zig build --build-file ./nifs/build.zig -- /usr/local/lib/erlang/erts-14.2.2/include

RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

COPY apps/stygian_web/priv apps/stygian_web/priv

# Substitutind this for umbrella apps
# COPY lib lib
COPY apps apps

COPY apps/stygian_web/assets apps/stygian_web/assets

# compile assets
RUN cd apps/stygian_web/assets && \
  npm install && \
  cd ../ && \
  mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM debian:bookworm-20231009-slim

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales \
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
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/stygian_umbrella ./

USER nobody

CMD ["/app/bin/stygian_umbrella", "start"]