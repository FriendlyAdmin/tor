#
# This Dockefile will download and build the most recent possible version of Tor.
# Which is the only way to get the functionality required to use Onionbalance.
#
# To sucessfully build an image from this Dockerfile the following build ARGs must be provided:
# ALPINE_VERSION, TOR_VERSION
#

# This version of Alpine will be used at every stage.
ARG ALPINE_VERSION

# Tor build stage
# Not going to do any space-saving here to utilize cache more, since this stage isn't going into productin anyway.
FROM alpine:$ALPINE_VERSION as tor-build

# This version of Tor will be downloaded from official sources and verified using GPG.
ARG TOR_VERSION

ENV TOR_TARBALL_NAME tor-$TOR_VERSION.tar.gz
ENV TOR_TARBALL_LINK https://dist.torproject.org/$TOR_TARBALL_NAME
ENV TOR_TARBALL_ASC $TOR_TARBALL_NAME.asc
ENV TOR_GPG_KEY 0x6AFEE6D49E92B601

WORKDIR '/'

# Add edge repositories to get the latest available versions of build dependencies.
RUN \
    echo 'http://dl-cdn.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories && \
    echo 'http://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories

# Download build dependencies.
# Same ones that are used to build Tor binaries from apk community repo.
RUN apk --no-cache --update add \
        wget \
        gnupg \
        build-base \
        libevent \
        libevent-dev \
        openssl \
        openssl-dev \
        xz-libs \
        xz-dev \
        zlib \
        zlib-dev \
        zstd \
        zstd-libs \
        zstd-dev

# Download Tor sources and signature.
RUN \
    wget -q $TOR_TARBALL_LINK && \
    wget -q $TOR_TARBALL_LINK.asc

# Verify Tor sources.
RUN \
    gpg --keyserver pool.sks-keyservers.net --recv-keys $TOR_GPG_KEY && \
    gpg --verify $TOR_TARBALL_NAME.asc

# Unpack Tor sources.
RUN tar xf $TOR_TARBALL_NAME

# Build Tor.
RUN cd tor-$TOR_VERSION && \
    ./configure && \
    make && \
    make install



# Separate stage to get dockerize script.
FROM alpine:$ALPINE_VERSION as dockerize-build

# Dockerize script version to use.
ENV DOCKERIZE_VERSION v0.6.1

# Download and unpack dockerize script.
RUN \
    wget -q https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz && \
    tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz && \
    rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz



# Run stage
FROM alpine:$ALPINE_VERSION

# Generic user for running Tor
ENV USER=tor
ENV GROUP=tor

# Tor-realated directories. Configured in default.torrc and other torrc files.
ENV DATA_DIR=/var/lib/tor
ENV HS_DATA_DIR=/var/lib/hs_data
ENV CONFIG_DIR=/usr/local/etc/tor

WORKDIR '/'

RUN \
    # Update apk, then update all built-in packages with the latest stable versions from pre-configured repositories.
    apk update && \
    apk --no-cache upgrade && \
    # Stable versions of curl and tini will be installed from built-in repositories.
    # tini will be used as a standart entrypoint and curl is for doing healthchecks.
    apk --no-cache add curl tini && \
    # Tor will be run from a generic user, since it doesn't need root priviligies.
    addgroup -g 101 -S $GROUP && \
    adduser -D -H -u 100 -s /sbin/nologin -G $GROUP -S $USER && \
    # Delete apk cache to save some space.
    rm -rf /var/cache/apk/*

# Copy Tor and all related files and directories from the build stage.
COPY --from=tor-build /usr/local/ /usr/local/

# Copy Dockerize.
COPY --from=dockerize-build /usr/local/bin/dockerize /usr/local/bin/dockerize

RUN \
    # Update apk and upgrade built-in packages to the latest stable versions.
    apk update && \
    apk --no-cache upgrade && \
    # Add apk edge repos to get the edge versions of packages.
    # We will restore the original repo list from this file to keep everything neat afterwards.
    cp /etc/apk/repositories /etc/apk/default-repositories && \
    echo 'http://dl-cdn.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories && \
    echo 'http://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories && \
    # Get edge verions of Tor runtime dependencies.
    # List is copied from https://pkgs.alpinelinux.org/package/edge/community/x86_64/tor
    apk --no-cache --update add \
        libevent \
        openssl \
        musl \
        xz-libs \
        zlib \
        zstd-libs \
        zstd \
        && \
    # Delete torrc.sample, just not to confuse ourselves.
    # This Dockerfiles assumes that torrc will be provided on run.
    rm $CONFIG_DIR/torrc.sample && \
    # Delete apk cache to save some space.
    rm -rf /var/cache/apk/* && \
    # Restore the default apk repo list.
    mv -f /etc/apk/default-repositories /etc/apk/repositories

# Create directories required by Tor and set proper ownership and permissions.
RUN \
    # Create a Tor data directory configured in default.torrc.
    mkdir $DATA_DIR && \
    chown -R $USER:$GROUP $DATA_DIR && \
    chmod 0700 $DATA_DIR && \
    # Create a directory for hidden service data.
    mkdir -m 0700 $HS_DATA_DIR && \
    chown -R $USER:$GROUP $HS_DATA_DIR && \
    mkdir -m 0700 $HS_DATA_DIR/authorized_clients && \
    chown -R $USER:$GROUP $HS_DATA_DIR/authorized_clients && \
    # Create a directory that can be used to keep an auth cookie in.
    mkdir -m 0700 $DATA_DIR/cookie && \
    chown -R $USER:$GROUP $DATA_DIR/cookie && \
    # Create a directory that can be used to keep a control port socket file in.
    mkdir -m 0700 $DATA_DIR/socket && \
    chown -R $USER:$GROUP $DATA_DIR/socket

# Copy the default torrc config file,
# which does nothing but providing a SOCKS5 proxy for healthchecking by curl.
# Tor will use this file by default.
# The intent is to pass an additional config on run either by hand or by docker-compose file.
COPY default.torrc $CONFIG_DIR/torrc-defaults

# Create a blank torrc file, so Tor can start with no additional configuration out of the box.
RUN touch $CONFIG_DIR/torrc

# Tor doesn't need root priviliges, so run it as a generic user.
USER $USER:$GROUP

# Declare anonymous volumes for this directories to persist data and run containers in read-only mode.
VOLUME $DATA_DIR $HS_DATA_DIR

# Tell Docker to periodically run curl as a way of checking that Tor is runnning OK,
# and is able to build a circuit. Link goes to a Tor Project page, which checks that
# client is accessing it through Tor network and not directly. It gives false negatives
# sometimes, so we should allow several retries.
#
# --socks5-hostname parameter is very important - it tells curl to ask proxy (Tor) for DNS lookup,
#   instead of doing it on its own - the behavior that torrc file above explicitly prohibits,
#   because it opens a possibility for a traffic correlation attack.
#
# --location flag is added just in case Tor Project changes the location of the page and puts a redirect at
#   the previos location, so curl can follow that redirect.
#
# grep gets the output of curl and looks for first occurence of the string 'Congratulations',
# exits with 0 if found and 1 otherwise. Nothing is printed to stdout during this command.
HEALTHCHECK --interval=120s --timeout=30s --start-period=60s --retries=5 \
            CMD curl --silent --location --socks5-hostname localhost:9050 https://check.torproject.org/?lang=en_US | \
            grep -qm1 Congratulations

# Run tini as a host proccess for Tor. Especcially important
# because we are using the most recent available version of Tor,
# which may not be 100% stable.
ENTRYPOINT [ "/sbin/tini", "--" ]

# By default - just simply run tor. Dockerize script can be utilized in docker-compose files.
CMD [ "tor" ]
