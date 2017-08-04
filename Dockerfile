FROM ubuntu:xenial
WORKDIR /app
ADD beetle /usr/bin/beetle
ENTRYPOINT ["/usr/bin/beetle"]
