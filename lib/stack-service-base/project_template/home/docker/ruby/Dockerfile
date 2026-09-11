FROM ruby:3.4.10-slim-bookworm AS base

RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends build-essential pkg-config libpq-dev curl cmake libssl-dev libyaml-dev \
     && rm -rf /var/lib/apt/lists/*

RUN echo 'gem: --no-document' >> ~/.gemrc

WORKDIR /app

COPY Gemfile* /app/

RUN bundle install --jobs $(nproc) --retry=3 && \
    bundle clean --force && rm -rf /usr/local/bundle/cache/*

# The bundle replaces the vulnerable resolver shipped as a default gem.
RUN rm -f /usr/local/lib/ruby/3.4.0/resolv.rb \
    /usr/local/lib/ruby/gems/3.4.0/specifications/default/resolv-0.7.1.gemspec

COPY . /app

ENV RACK_ENV=production NODE_ENV=production
RUN rake -T | grep 'rake build' && rake build || echo 'no build task'

# used in .gitlab-ci.yml Tests.
FROM base AS tests
# COPY . . required test fixtures
CMD bundle exec rspec

FROM ruby:3.4.10-slim-bookworm AS deploy
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends bash curl libssl-dev wget libpq-dev libyaml-0-2 \
     && rm -rf /var/lib/apt/lists/*

COPY --from=base /usr/local/bundle /usr/local/bundle

# The bundle replaces the vulnerable resolver shipped as a default gem.
RUN rm -f /usr/local/lib/ruby/3.4.0/resolv.rb \
    /usr/local/lib/ruby/gems/3.4.0/specifications/default/resolv-0.7.1.gemspec

# Force start & wait test Stage
# COPY --from=tests /app/src/spec/results /app/src/spec/results

COPY . /app

ENV RUBY_YJIT_ENABLE=1 \
    SERVER_ENV=production \
    RACK_ENV=production \
    PORT=7000

WORKDIR /app

# --start_period=5s (Unknown flag: start_period)
HEALTHCHECK --interval=15s --timeout=2s --retries=3 CMD curl --fail http://127.0.0.1:$PORT/healthcheck || exit 1
CMD bundle exec rackup -o 0.0.0.0 -p $PORT -s falcon
# docker-compose build --progress plain
