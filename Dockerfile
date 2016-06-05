FROM ubuntu:14.04

# ----------------------------
# add railsexpress repo
# ----------------------------
RUN echo 'deb [trusted=yes] http://railsexpress.de/packages/ubuntu/trusty ./' >> /etc/apt/sources.list

# ----------------------------
# install base packages
# ----------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        curl \
        gawk \
        git \
        git-core \
        htop \
        libcurl4-openssl-dev \
        libffi-dev \
        libgdbm-dev \
        libgmp-dev \
        libicu-dev \
        libncurses5-dev\
        libossp-uuid-dev \
        libreadline-dev \
        libsqlite3-dev\
        libssl-dev \
        libtool \
        libxml2-dev \
        libxslt-dev \
        libyaml-dev \
        lsof \
        patch \
        pkg-config \
        sudo \
        wget \
        zlib1g-dev

RUN apt-get install -y --no-install-recommends \
        railsexpress-ruby=2.3.1-1 \
        rabbitmq-server=3.6.2-1

# ----------------------------
# Redis: stolen from https://github.com/docker-library/redis/blob/6cb8a8015f126e2a7251c5d011b86b657e9febd6/3.2/Dockerfile
# ----------------------------
ENV REDIS_VERSION 3.2.0
ENV REDIS_DOWNLOAD_URL http://download.redis.io/releases/redis-3.2.0.tar.gz
ENV REDIS_DOWNLOAD_SHA1 0c1820931094369c8cc19fc1be62f598bc5961ca
RUN set -x \
        && wget -q -O redis.tar.gz "$REDIS_DOWNLOAD_URL" \
        && echo "$REDIS_DOWNLOAD_SHA1 *redis.tar.gz" | sha1sum -c - \
        && mkdir -p /usr/src/redis \
        && tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1 \
        && rm redis.tar.gz \
        && make -C /usr/src/redis \
        && make -C /usr/src/redis install \
        && rm -r /usr/src/redis

RUN apt-get install -y --no-install-recommends \
        libmysqlclient-dev \
        mysql-server

RUN wget -q -O /tini https://github.com/krallin/tini/releases/download/v0.9.0/tini-static && chmod 755 /tini

ENV BEETLE_HOME /usr/src/beetle
RUN mkdir -p $BEETLE_HOME
WORKDIR $BEETLE_HOME

# Docker for Mac is currently broken
COPY Gemfile Rakefile beetle.gemspec $BEETLE_HOME/
COPY lib $BEETLE_HOME/lib

ENV BUNDLE_SILENCE_ROOT_WARNING=1
RUN bundle install -j 4

COPY bin $BEETLE_HOME/bin
COPY etc $BEETLE_HOME/etc
COPY examples $BEETLE_HOME/examples
COPY features $BEETLE_HOME/features
COPY test $BEETLE_HOME/test
COPY tmp $BEETLE_HOME/tmp
COPY script $BEETLE_HOME/script

RUN echo '[{rabbit, [{loopback_users, []}]}].' > /etc/rabbitmq/rabbitmq.config

ENV RAINBOW_COLORED_TESTS 1

EXPOSE 6379 6380 5672 15672

ENTRYPOINT ["/tini", "--", "script/docker-entrypoint.sh"]

CMD ["bundle", "exec", "rake"]
