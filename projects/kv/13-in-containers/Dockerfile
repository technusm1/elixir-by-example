# Same two-stage layout as on the Containers page.
ARG ELIXIR_VERSION=1.20.5
ARG OTP_VERSION=29.1.2
ARG DEBIAN_VERSION=trixie-20261104-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV="prod"

# The lock file pins the exact dependency versions that were tested.
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV && mix deps.compile

COPY lib lib
# runtime.exs is read at boot, so changing it doesn't recompile anything.
COPY config/runtime.exs config/
RUN mix release

FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/kv ./

USER nobody
CMD ["/app/bin/kv", "start"]
