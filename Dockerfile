FROM buildpack-deps:jammy-scm as builder
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    libzmq3-dev \
    && rm -rf /var/lib/apt/lists/*

# install go compiler
ENV GOLANG_VERSION 1.19.8
ENV GOLANG_DOWNLOAD_URL https://golang.org/dl/go$GOLANG_VERSION.linux-amd64.tar.gz
ENV GOLANG_DOWNLOAD_SHA256 e1a0bf0ab18c8218805a1003fd702a41e2e807710b770e787e5979d1cf947aba
RUN curl -fsSL "$GOLANG_DOWNLOAD_URL" -o golang.tar.gz \
        && echo "$GOLANG_DOWNLOAD_SHA256  golang.tar.gz" | sha256sum -c - \
        && tar -C /usr/local -xzf golang.tar.gz \
        && rm golang.tar.gz
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

ADD . /app
WORKDIR /app
RUN make beetle

FROM ubuntu:jammy
RUN apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libzmq5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/beetle /usr/bin/beetle

ENTRYPOINT ["/usr/bin/beetle"]
