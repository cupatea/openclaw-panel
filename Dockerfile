# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom;error=true

# Skip rationale: RUBY_VERSION + DOCKER_VERSION are sourced from .ruby-version
# and .docker-version at build time (bin/build passes them via --build-arg).
# Single source of truth — no Dockerfile defaults to drift.

ARG RUBY_VERSION
ARG DOCKER_VERSION

# Static docker CLI + compose plugin. The panel drives the OpenClaw stack the
# same way you would over SSH: `docker compose ...` against the host's socket.
FROM docker.io/library/docker:${DOCKER_VERSION}-cli AS docker-cli

FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base
WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 sqlite3 ca-certificates && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    PORT="3005" \
    RAILS_LOG_TO_STDOUT="1" \
    RAILS_SERVE_STATIC_FILES="1" \
    OPENCLAW_DIR="/openclaw"

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

FROM base

# Runs as root: the docker socket's group id differs from NAS to NAS, and the
# panel has to chown openclaw.json back to the gateway's `node` user after
# editing it. Anyone who can reach the socket is root on the host anyway.
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

LABEL org.opencontainers.image.source="https://github.com/cupatea/openclaw-panel"
LABEL org.opencontainers.image.description="A small web panel for a docker-compose OpenClaw install: status, logs, restarts, updates, pairing approvals, config edits."
LABEL org.opencontainers.image.licenses="MIT"

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3005
VOLUME ["/rails/storage"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
