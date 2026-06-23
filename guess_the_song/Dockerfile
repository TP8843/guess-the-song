ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=27

FROM elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION} AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex + rebar (needed for deps installation)
RUN mix local.hex --force \
  && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/
RUN mix deps.compile

COPY lib lib
COPY priv priv
RUN mix compile

COPY config/runtime.exs config/

RUN mix release

FROM debian:bookworm-slim AS final

RUN apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates ffmpeg \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_GB.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_GB.UTF-8
ENV LANGUAGE=en_GB:en
ENV LC_ALL=en_GB.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

# Copy only the compiled release from the builder stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/guess_the_song ./

USER nobody

CMD ["sh", "-c", "/app/bin/guess_the_song eval GuessTheSong.Release.migrate && /app/bin/guess_the_song start"]
