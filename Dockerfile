ARG RUBY_VERSION=3.0
FROM ruby:${RUBY_VERSION}-alpine

ARG BUNDLER_VERSION=2.5.23

RUN apk add --no-cache \
    bash \
    build-base \
    git \
    tzdata \
    yaml-dev \
    libxml2-dev \
    libxslt-dev

ENV BUNDLE_FORCE_RUBY_PLATFORM=1

RUN gem install bundler -v "${BUNDLER_VERSION}" --no-document

WORKDIR /app

COPY Gemfile Gemfile.lock puma-enhanced-stats.gemspec ./
COPY lib/ lib/
COPY schema/ schema/

RUN bundle install

COPY . .

RUN bundle install

COPY bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["bundle", "exec", "rake"]
