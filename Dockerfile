FROM ubuntu:jammy
WORKDIR /app
ADD ./linux.tar.gz /usr/bin
ENTRYPOINT ["/usr/bin/beetle"]
