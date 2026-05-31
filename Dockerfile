# syntax=docker/dockerfile:1
# check=error=true

# Local-first image. Build once, then run with your data folder mounted and your
# own API key(s) — everything (SQLite DB, recordings, generated manuals) stays in
# the mounted folder:
#
#   docker build -t scribe .
#   docker run -p 3000:80 -v "$PWD/data:/data" \
#     -e SECRET_KEY_BASE=$(openssl rand -hex 32) \
#     -e ANTHROPIC_API_KEY=sk-ant-... \
#     scribe
#
# Or point it at a local llama model instead of Anthropic:
#   -e LLM_PROVIDER=local -e LLM_BASE_URL=http://host.docker.internal:11434/v1 -e LLM_MODEL=llama3.2-vision

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.3.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages. The media pipeline needs ffmpeg (scene detection, audio
# extraction) and WeasyPrint (HTML→PDF export); sqlite is the datastore. Python +
# faster-whisper provide fully local, offline speech-to-text (libgomp1 is needed
# by ctranslate2's CPU backend).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libvips libsqlite3-0 ffmpeg weasyprint \
      python3 python3-pip libgomp1 && \
    pip3 install --no-cache-dir --break-system-packages faster-whisper && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Pre-download the Whisper model so transcription is fully offline at runtime
# (nothing is fetched on first use). World-readable so the non-root app user can
# load it. Override the size at build time with --build-arg WHISPER_MODEL=small.
ARG WHISPER_MODEL=base
RUN python3 -c "from faster_whisper import WhisperModel; WhisperModel('${WHISPER_MODEL}', device='cpu', compute_type='int8', download_root='/opt/whisper-models')" && \
    chmod -R a+rX /opt/whisper-models

# Local-first runtime defaults: production env, the SQLite/recordings data dir at
# the mount point, and Solid Queue running inside Puma so a single container does
# both the web app and the background pipeline.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    SCRIBE_DATA_DIR="/data" \
    SOLID_QUEUE_IN_PUMA="1" \
    TRANSCRIPTION_PROVIDER="whisper" \
    WHISPER_BIN="/rails/script/faster-whisper" \
    WHISPER_MODEL="${WHISPER_MODEL}" \
    WHISPER_MODEL_DIR="/opt/whisper-models"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libsqlite3-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /data && chown 1000:1000 /data

# Everything persistent (SQLite DB, recordings, generated manual files) lives
# here. Mount it to keep your data across container rebuilds.
VOLUME /data

USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
