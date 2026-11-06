ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.3.4.3
ARG DEBIAN_VERSION=bookworm-20250929-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
# Unpinned on purpose: a dated Debian tag stops resolving its apt packages once
# they rotate out of the mirrors. Keep the suite in sync with the builder's glibc.
ARG RUNNER_IMAGE="debian:bookworm-slim"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock VERSION ./
COPY apps/heddle/mix.exs apps/heddle/mix.exs
COPY apps/heddle_local/mix.exs apps/heddle_local/mix.exs
COPY apps/heddle_core/mix.exs apps/heddle_core/mix.exs
COPY apps/heddle_nodes/mix.exs apps/heddle_nodes/mix.exs
COPY apps/heddle_runtime/mix.exs apps/heddle_runtime/mix.exs
COPY apps/heddle_ai/mix.exs apps/heddle_ai/mix.exs
COPY apps/heddle_ui/mix.exs apps/heddle_ui/mix.exs
COPY apps/heddle_worker/mix.exs apps/heddle_worker/mix.exs

RUN mix deps.get --only prod
RUN mix deps.compile

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs

COPY config config
COPY apps apps
COPY scripts scripts

RUN mix assets.setup
RUN mix assets.deploy
RUN mix compile
RUN mix release heddle_ui
RUN mix release heddle_worker

FROM ${RUNNER_IMAGE}

RUN apt-get update -y && apt-get install -y bash libstdc++6 openssl libncurses5 locales python3 ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV MIX_ENV=prod
ENV PHX_SERVER=true
ENV HOME=/app

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/heddle_ui /app/ui
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/heddle_worker /app/worker
COPY scripts/entrypoint.sh /app/entrypoint.sh

RUN sed -i 's/\r$//' /app/entrypoint.sh && chmod +x /app/entrypoint.sh
RUN mkdir -p /app/.cache /app/data && chown -R nobody:root /app/.cache /app/data

USER nobody

# The Claude Agent needs the claude binary. It stays out of the default image: build
# with --build-arg INSTALL_CLAUDE=true to include it.
ARG INSTALL_CLAUDE=false
ENV PATH="/app/.local/bin:${PATH}"
USER root
RUN if [ "$INSTALL_CLAUDE" = "true" ]; then \
      apt-get update -y && apt-get install -y curl \
      && apt-get clean && rm -f /var/lib/apt/lists/*_* \
      && su -s /bin/bash nobody -c 'HOME=/app curl -fsSL https://claude.ai/install.sh | HOME=/app bash'; \
    fi
USER nobody

# Fetch Python now. Otherwise every new container downloads it on boot, and in
# `all` mode the two releases race to create the same venv and one loses Python.
RUN DATABASE_URL=ecto://build SECRET_KEY_BASE=build /app/worker/bin/heddle_worker eval \
    '{:ok, _} = Application.ensure_all_started(:heddle_runtime); Pythonx.eval("1", %{})'

EXPOSE 4000

ENTRYPOINT ["/app/entrypoint.sh"]
