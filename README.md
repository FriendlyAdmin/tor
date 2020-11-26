# FriendlyAdmin/tor

General purpose Tor Docker image.

Comes with a reasonable level of hardening, reasonable defaults for Tor config and a simple healthcheck.

Built for Docker Hub automatically by utilizing a GitHub hook, see `hooks/build` for details.

Tor is being built from souces acquired automatically during build from [Tor distribution server](https://dist.torproject.org/) and verified using Tor Project's release PGP key. See `Dockerfile` for details on how it works.

Will not work as a general purpose proxy out of the box by design - the included Tor config will only allow proxy connections from inside the container.

Intended to be used as a part of a hidden service setup or as a general-purpose SOCKS4A/SOCKS5 Tor proxy, depending on the final config provided.

[Docker Hub repo](https://hub.docker.com/r/friendlyadmin/tor)

## Usage

Simply pull the image from Docker Hub:

```
docker pull friendlyadmin/tor:latest
```

Or just run a container:

```
docker container run --read-only -d --name=tor friendlyadmin/tor:latest
```

Here's an example on how to provide a final config file (torrc):

```
docker container run --read-only -d --name=tor --volume /path/to/torrc:/etc/tor/torrc:ro friendlyadmin/tor:latest
```

Note: The image contains a `torrc-defaults` file baked in (see `default.torcc` file in this repo).
Do not override it - it contains some important security configration and also options required for healthchecks and Docker logging to work.
Provide your custom config as `/etc/tor/torrc`. Tor will load both config files on startup, options in `torrc` override the ones from `torrc-default`.

See comments in `default.torrc` and [Tor manual](https://torproject.org/docs/tor-manual.html) for detailed explanation of every configuration option.

## Docker Compose example

```
...

services:
    tor:
        image: friendlyadmin/tor:latest
        read_only: true
        volumes:
            - /path/to/torrc:/etc/tor/torrc:ro

...
```

It is recommended to run this image as `read_only` - just as an additional protection is case of a 0-day vulnerability in Tor. Necessary volumes are already declared in `Dockerfile`, Docker will create ephemeral volumes for every directory Tor needs to write to.

## Building

To build the image manually run from inside the repo root directory:

```
docker build --build-arg ALPINE_VERSION=3.12 --build-arg TOR_VERSION=0.4.4.6 YOU_DESIRED_TAG .
```

You must provide `ALPINE_VERSION` and `TOR_VERSION` build arguments.

See tags on [Docker Hub Alpine repo](https://hub.docker.com/_/alpine) for what Alpine Linux versions are available and [Tor distribution server](https://dist.torproject.org/) for what versions of Tor are currently available.

## See also

[FriendlyAdmin/onionbalance](https://github.com/FriendlyAdmin/onionbalance) - Tor and Onionbalance neatly packaged in a single Docker image to server as a separated Onionbalance setup for a Tor hidden service.

[FriendlyAdmin/tor-hs](https://github.com/FriendlyAdmin/tor-hs) - A pre-made simple Docker Compose configuration for running a Tor hidden service.
