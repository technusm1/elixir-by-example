# Builder and runner use the same Debian release, so the release built in the
# first stage finds the same system libraries in the second.
# Tags: https://hub.docker.com/r/hexpm/elixir/tags
ARG ELIXIR_VERSION=1.20.5
ARG OTP_VERSION=29.1.2
ARG DEBIAN_VERSION=trixie-20261104-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ---- Stage 1: build the release ----
FROM ${BUILDER_IMAGE} AS builder

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV="prod"

# Dependencies first: this layer is cached until mix.exs changes.
COPY mix.exs ./
RUN mix deps.get --only $MIX_ENV && mix deps.compile

# Then the code, which changes on every commit.
COPY lib lib
RUN mix release

# ---- Stage 2: the image that runs ----
FROM ${RUNNER_IMAGE} AS final

# What the Erlang runtime needs from the OS, and nothing else.
RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

# Only the release crosses over: no compiler, no Mix, no source.
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/greeter ./

USER nobody
CMD ["/app/bin/greeter", "start"]
