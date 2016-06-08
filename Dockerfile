FROM ubuntu:14.04

ENV DEBIAN_FRONTEND noninteractive

# add railsexpress repo
RUN echo 'deb [trusted=yes] http://railsexpress.de/packages/ubuntu/trusty ./' >> /etc/apt/sources.list

# install base packages
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
        railsexpress-ruby=2.3.1-1

# need the redis-cli
# Redis: stolen from https://github.com/docker-library/redis/blob/6cb8a8015f126e2a7251c5d011b86b657e9febd6/3.2/Dockerfile
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

# need mysql libraries
RUN apt-get install -y --no-install-recommends \
        libmysqlclient-dev

# docker binaries to communicate with /var/run/docker.sock on the host
# see https://jpetazzo.github.io/2015/09/03/do-not-use-docker-in-docker-for-ci/
RUN apt-get install -y apt-transport-https ca-certificates
RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
RUN echo 'deb https://apt.dockerproject.org/repo ubuntu-trusty main' >>/etc/apt/sources.list
RUN apt-get update && apt-get install -y docker-engine


RUN wget -q -O /tini https://github.com/krallin/tini/releases/download/v0.9.0/tini-static && chmod 755 /tini

ENV BEETLE_HOME /usr/src/beetle
RUN mkdir -p $BEETLE_HOME
WORKDIR $BEETLE_HOME

# mount files necessary for bundling
COPY Gemfile beetle.gemspec $BEETLE_HOME/
COPY lib/beetle/version.rb $BEETLE_HOME/lib/beetle/

# bundle before mounting the code so we don't need to rebundle when code changes
ENV BUNDLE_SILENCE_ROOT_WARNING=1
RUN bundle install -j 4

# mount the source code
COPY bin $BEETLE_HOME/bin
COPY examples $BEETLE_HOME/examples
COPY features $BEETLE_HOME/features
COPY lib $BEETLE_HOME/lib
COPY script $BEETLE_HOME/script
COPY test $BEETLE_HOME/test
COPY tmp $BEETLE_HOME/tmp
COPY Rakefile $BEETLE_HOME/

# allow containerization detection
ENV BEETLE_TEST_CONTAINER 1

ENTRYPOINT ["/tini", "--", "script/docker-entrypoint.sh"]

CMD ["bundle", "exec", "rake"]
