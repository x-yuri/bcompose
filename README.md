## Usage

```
$ bc.sh SERVICE_DEFINITION COMMON ARGS
```

The recommended approach is to create a local wrapper around `bc.sh` (think `docker-compose.yml`), e.g.:

`bc.sh`:

```sh
#!/bin/sh -eu
path/to/bcompose/bc.sh \
    --project bc-test \
    --image alpine:3.20 \
    --cmd sleep infinity \
    -- \
    "$@"
```

```
$ ./bc.sh up -d
```

If you need more than one service:

`bc.sh`:

```sh
#!/usr/bin/env bash
set -eu
service_a=(
    --name service-a
    --image alpine:3.20
    --args --init
    --cmd sleep infinity
)
service_b=(
    --service
    --name service-b
    --image alpine:3.20
    --args --init
    --cmd sleep infinity
)
path/to/bcompose/bc.sh \
    --project bc-test \
    "${service_a[@]}" \
    "${service_b[@]}" \
    -- \
    "$@"
```

Do note the `--` argument. It's needed because `--args` and `--cmd` take arguments until they run into one of `bc`'s arguments or `--`. Or to be more precise `--args` takes arguments until it meets any other `bc` argument except `--args`. `--args` arguments are ignored (`--args --args --` specifies no arguments). The same goes for `--cmd`.
