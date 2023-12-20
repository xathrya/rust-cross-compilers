# docker build -t xathrya/rust-cross-compilers .

FROM debian:12.2-slim AS builder 

ARG OSX_SDK_VERSION=13.3 
ARG OSX_VERSION_MIN=10.14
ARG OSX_CROSS_COMMIT="ff8d100f3f026b4ffbe4ce96d8aac4ce06f1278b"
ARG LLVM_MINGW_VERSION=20231114

ENV PATH=/root/.cargo/bin:/usr/local/musl/bin:/usr/local/osxcross/target/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV MACOSX_DEPLOYMENT_TARGET=${OSX_VERSION_MIN}
ENV OSXCROSS_MACPORTS_MIRROR=https://packages.macports.org

# setup dev tools for building C libraries
RUN set -eux \
    && dpkg --add-architecture arm64 \
    && DEBIAN_FRONTEND=noninteractive apt-get -y update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -qq -y --no-install-recommends --no-install-suggests \
        autoconf automake build-essential ca-certificates clang cmake curl file git \
        libbz2-dev libgmp-dev libicu-dev libmpc-dev libmpfr-dev libpq-dev libsqlite3-dev \
        libssl-dev libtool libxml2-dev linux-libc-dev llvm-dev lzma-dev \
        patch pkgconf python3 xutils-dev yasm xz-utils zlib1g-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && true 

RUN set -eux \
    && ln -s "/usr/bin/g++" "/usr/bin/musl-g++" \
    && mkdir -p /root/libs /root/src \
    && true 

# OSX
## building SDK
RUN set -eux \
    && echo "<builder:osx:1> cloning OSX Cross..." \
    && git clone https://github.com/tpoechtrager/osxcross.git /usr/local/osxcross \
    && cd /usr/local/osxcross \
    && git checkout -q "${OSX_CROSS_COMMIT}" \
    && rm -rf ./.git \
    && true

RUN set -eux \
    && echo "<builder:osx:2> building SDK..." \
    && cd /usr/local/osxcross \
    && curl -Lo "./tarballs/MacOSX${OSX_SDK_VERSION}.sdk.tar.xz" "https://github.com/joseluisq/macosx-sdks/releases/download/${OSX_SDK_VERSION}/MacOSX${OSX_SDK_VERSION}.sdk.tar.xz" \
    && env UNATTENDED=yes OSX_VERSION_MIN=${OSX_VERSION_MIN} ./build.sh \
    && true 

## building compiler-rt
RUN set -eux \
    && echo "<builder:osx:3> building compiler-rt..." \
    && cd /usr/local/osxcross \
    && env DISABLE_PARALLEL_ARCH_BUILD=1 ./build_compiler_rt.sh \
    && true 

## get dependencies
RUN set -eux \
    && echo "<build:osx:4> install dependencies..." \
    && apt-get update \
    && /usr/local/osxcross/tools/get_dependencies.sh \
    && osxcross-macports install cctools zlib openssl libarchive \
    && osxcross-macports upgrade \
    && true 

# Windows MinGW
RUN set -eux \
    && echo "<build:mingw> install LLVM-MinGW" \
    && cd /tmp \
    && curl -LO "https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-20.04-x86_64.tar.xz" \
    && tar -xJf llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-20.04-x86_64.tar.xz \
    && mv llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-20.04-x86_64 /usr/local/llvm-mingw \
    && rm llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-20.04-x86_64.tar.xz \
    && true
COPY "libs/x86_64-pc-windows-gnu/10-win32/libgcc*" /usr/local/llvm-mingw/x86_64-w64-mingw32/lib/
COPY "libs/i686-pc-windows-gnu/10-win32/libgcc*" /usr/local/llvm-mingw/i686-w64-mingw32/lib/

# ================= IMAGE BUILDING =================

FROM python:3.12-slim-bookworm 

LABEL maintainer="Satria Ady Pradana <me@xathrya.id>" \
    architecture="amd64" \
    python-version="3.12.0" \
    rustup-version="1.26.0" \
    rustc-version="1.74.0" \
    build="24-November-2023" \
    org.opencontainers.image.title="Rust Cross Compiler" \
    org.opencontainers.image.description="Rust toolchains on Debian Slim" \
    org.opencontainers.image.authors="Satria Ady Pradana <me@xathrya.id>" \
    org.opencontainers.image.vendor="" \
    org.opencontainers.image.version="1.74.0" \
    org.opencontainers.image.url="https://hub.docker.com/r/xathrya/mythic-rust-payload/" \
    org.opencontainers.image.source="https://github.com/xathrya/docker-images/" \
    org.opencontainers.image.revision=$VCS_REF \
    org.opencontainers.image.created=$BUILD_DATE

ARG SCCACHE_VERSION=0.7.3
ARG TOOLCHAIN=stable 

ENV CARGO_HOME="/usr/local/cargo"
ENV RUSTUP_HOME="/usr/local/rustup"
ENV OSXCROSS_PATH="/usr/local/osxcross"
ENV LLVM_MINGW_PATH="/usr/local/llvm-mingw"
ENV PATH="/root/.cargo/bin:${OSXCROSS_PATH}/bin:${LLVM_MINGW_PATH}/bin:${CARGO_HOME}/bin:${RUSTUP_HOME}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# install prerequisites (+musl)
RUN set -eux \
    && dpkg --add-architecture arm64 \
    && DEBIAN_FRONTEND=noninteractive apt-get -y update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -qq -y --no-install-recommends --no-install-suggests \
        curl ca-certificates \
        gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
        musl-dev musl-dev:arm64 musl-tools \
        python3-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && true

RUN set -eux \
    && ln -s "/usr/bin/g++" "/usr/bin/musl-g++" \
    && mkdir -p /root/libs /root/src \
    && true

# install compilers
## OSX
COPY --from=builder ${OSXCROSS_PATH}/target ${OSXCROSS_PATH}
## LLVM MinGW
COPY --from=builder ${LLVM_MINGW_PATH} ${LLVM_MINGW_PATH}

# install sccache
RUN set -eux \
    && echo "<image> installing sccache" \
    && curl -LO "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && tar -xzf "sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && mv sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl/sccache /usr/local/bin \
    && rm -rf sccache* \
    && true

# install rust (+toolchains)
RUN set -eux \
    && echo "<image> installing rust" \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain $TOOLCHAIN --profile minimal \
    && rustup target add \
        aarch64-apple-darwin \
        aarch64-pc-windows-msvc \
        aarch64-unknown-linux-musl \
        i686-pc-windows-gnu \
        i686-unknown-linux-musl \
        x86_64-apple-darwin \
        x86_64-pc-windows-gnu \
        x86_64-pc-windows-msvc \
        x86_64-unknown-linux-gnu \
        x86_64-unknown-linux-musl \
    && cargo install cargo-xwin \
    && true 
COPY ./cargo/config.toml /root/.cargo/config

WORKDIR /root/src 

CMD ["/bin/bash"]