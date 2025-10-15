#$ <remote_execution/Dockerfile docker build --tag=dtolnay/buck2-rustc-bootstrap:latest -
#$ docker push dtolnay/buck2-rustc-bootstrap:latest

FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    clang-19 \
    lld-19 \
    python3 \
    xz-utils \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s clang-19 /usr/bin/clang \
    && ln -s clang++-19 /usr/bin/clang++ \
    && ln -s lld-19 /usr/bin/lld
