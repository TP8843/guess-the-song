ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28
ARG FFMPEG_VERSION=7.1

# Minimal ffmpeg with only what nostrum's voice playback uses: reading an MP3
# preview over HTTPS, applying volume, resampling and encoding to Opus. See
# DOCKER_SIZE.md.
FROM debian:trixie-slim AS ffmpeg

ARG FFMPEG_VERSION

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential nasm pkg-config curl ca-certificates xz-utils libopus-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz | tar xJ

WORKDIR /ffmpeg-${FFMPEG_VERSION}

RUN ./configure --prefix=/opt/ffmpeg \
      --disable-everything --disable-autodetect --disable-doc \
      --disable-ffplay --disable-ffprobe --enable-small \
      --enable-network --enable-openssl --enable-libopus \
      --enable-protocol=file,pipe,http,https,tcp,tls \
      --enable-demuxer=mp3 --enable-parser=mpegaudio --enable-decoder=mp3float \
      --enable-encoder=libopus --enable-muxer=data \
      --enable-swresample --enable-filter=aresample,aformat,volume,anull \
    && make -j"$(nproc)" \
    && make install \
    && strip /opt/ffmpeg/bin/ffmpeg

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

# Remove debug symbols from the Erlang runtime (beam.smp is about 55 MB
# unstripped). Some files in bin are shell scripts, which strip skips with an
# error, hence the `|| true`.
RUN find _build/${MIX_ENV}/rel/guess_the_song/erts-*/bin -type f \
      -exec strip --strip-unneeded {} + 2>/dev/null || true

FROM debian:trixie-slim AS final

RUN apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates libopus0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ffmpeg /opt/ffmpeg/bin/ffmpeg /usr/local/bin/

# glibc already includes C.UTF-8, so no locales package is needed
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

WORKDIR "/app"
RUN chown nobody /app

ENV MIX_ENV="prod"

# Copy only the compiled release from the builder stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/guess_the_song ./

USER nobody

CMD ["sh", "-c", "/app/bin/guess_the_song eval GuessTheSong.Release.migrate && /app/bin/guess_the_song start"]
