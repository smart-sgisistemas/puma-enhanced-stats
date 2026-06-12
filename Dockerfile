FROM ruby:3.0-alpine

ARG BUNDLER_VERSION=2.5.23

RUN apk add --no-cache \
    bash \
    build-base \
    git

RUN gem install bundler -v "${BUNDLER_VERSION}" --no-document

WORKDIR /app

CMD ["bash"]
