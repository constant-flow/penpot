#!/usr/bin/env bash
set -ex

export ORGANIZATION="penpotapp";
export DEVENV_IMGNAME="$ORGANIZATION/devenv";
export DEVENV_PNAME="penpotdev";

export CURRENT_USER_ID=$(id -u);
export CURRENT_VERSION=$(cat ./version.txt);
export CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD);
export CURRENT_HASH=$(git rev-parse --short HEAD);
export CURRENT_COMMITS=$(git rev-list --count HEAD)

function print-current-version {
    echo -n "$CURRENT_VERSION-$CURRENT_COMMITS-g$CURRENT_HASH"
}

function build-devenv {
    echo "Building development image $DEVENV_IMGNAME:latest..."

    pushd docker/devenv;

    podman run --privileged --rm tonistiigi/binfmt --install all
    podman buildx inspect penpot > /dev/null 2>&1;

    if [ $? -eq 1 ]; then
        podman buildx create --name=penpot --use
        podman buildx inspect --bootstrap > /dev/null 2>&1;
    else
        podman buildx use penpot;
        podman buildx inspect --bootstrap  > /dev/null 2>&1;
    fi

    # podman build -t $DEVENV_IMGNAME:latest .
    podman buildx build --platform linux/amd64,linux/arm64 --push -t $DEVENV_IMGNAME:latest .;
    podman pull $DEVENV_IMGNAME:latest;

    popd;
}

function build-devenv-local {
    echo "Building local only development image $DEVENV_IMGNAME:latest..."

    pushd docker/devenv;
    podman build -t $DEVENV_IMGNAME:latest .;
    popd;
}

function pull-devenv {
    set -ex
    podman pull $DEVENV_IMGNAME:latest
}

function pull-devenv-if-not-exists {
    if [[ ! $(podman images $DEVENV_IMGNAME:latest -q) ]]; then
        pull-devenv $@
    fi
}

function start-devenv {
    pull-devenv-if-not-exists $@;

    podman-compose -p $DEVENV_PNAME -f docker/devenv/docker-compose.yaml up -d;
}

function stop-devenv {
    podman-compose -p $DEVENV_PNAME -f docker/devenv/docker-compose.yaml stop -t 2;
}

function drop-devenv {
    podman-compose -p $DEVENV_PNAME -f docker/devenv/docker-compose.yaml down -t 2 -v;

    echo "Clean old development image $DEVENV_IMGNAME..."
    podman images $DEVENV_IMGNAME -q | awk '{print $3}' | xargs --no-run-if-empty podman rmi
}

function log-devenv {
    podman-compose -p $DEVENV_PNAME -f docker/devenv/docker-compose.yaml logs -f --tail=50
}

function run-devenv {
    if [[ ! $(podman ps -f "name=penpot-devenv-main" -q) ]]; then
        start-devenv
    fi

    podman exec -ti penpot-devenv-main sudo -EH -u penpot /home/start-tmux.sh
}

function build {
    echo ">> build start: $1"
    local version=$(print-current-version);

    pull-devenv-if-not-exists;
    podman volume create ${DEVENV_PNAME}_user_data;
    podman run -t --rm \
           --mount source=${DEVENV_PNAME}_user_data,type=volume,target=/home/penpot/ \
           --mount source=`pwd`,type=bind,target=/home/penpot/penpot \
           -e EXTERNAL_UID=$CURRENT_USER_ID \
           -e SHADOWCLJS_EXTRA_PARAMS=$SHADOWCLJS_EXTRA_PARAMS \
           -w /home/penpot/penpot/$1 \
           $DEVENV_IMGNAME:latest sudo -EH -u penpot ./scripts/build $version

    echo ">> build end: $1"
}

function put-license-file {
    local target=$1;
    tee -a $target/LICENSE  >> /dev/null <<EOF
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.

Copyright (c) KALEIDOS INC
EOF
}

function build-frontend-bundle {
    echo ">> bundle frontend start";

    mkdir -p ./bundles
    local version=$(print-current-version);
    local bundle_dir="./bundles/frontend";

    build "frontend";

    rm -rf $bundle_dir;
    mv ./frontend/target/dist $bundle_dir;
    echo $version > $bundle_dir/version.txt;
    put-license-file $bundle_dir;
    echo ">> bundle frontend end";
}

function build-backend-bundle {
    echo ">> bundle backend start";

    mkdir -p ./bundles
    local version=$(print-current-version);
    local bundle_dir="./bundles/backend";

    build "backend";

    rm -rf $bundle_dir;
    mv ./backend/target/dist $bundle_dir;
    echo $version > $bundle_dir/version.txt;
    put-license-file $bundle_dir;
    echo ">> bundle backend end";
}

function build-exporter-bundle {
    echo ">> bundle exporter start";

    mkdir -p ./bundles
    local version=$(print-current-version);
    local bundle_dir="./bundles/exporter";

    build "exporter";

    rm -rf $bundle_dir;
    mv ./exporter/target $bundle_dir;

    echo $version > $bundle_dir/version.txt
    put-license-file $bundle_dir;

    echo ">> bundle exporter end";
}

function usage {
    echo "PENPOT build & release manager"
    echo "USAGE: $0 OPTION"
    echo "Options:"
    echo "- pull-devenv                      Pulls podman development oriented image"
    echo "- build-devenv                     Build podman development oriented image"
    echo "- start-devenv                     Start the development oriented podman-compose service."
    echo "- stop-devenv                      Stops the development oriented podman-compose service."
    echo "- drop-devenv                      Remove the development oriented podman-compose containers, volumes and clean images."
    echo "- run-devenv                       Attaches to the running devenv container and starts development environment"
    echo ""
}

case $1 in
    version)
        print-current-version
        ;;

    ## devenv related commands
    pull-devenv)
        pull-devenv ${@:2};
        ;;

    build-devenv)
        build-devenv ${@:2}
        ;;

    build-devenv-local)
        build-devenv-local ${@:2}
        ;;

    push-devenv)
        push-devenv ${@:2}
        ;;

    start-devenv)
        start-devenv ${@:2}
        ;;
    run-devenv)
        run-devenv ${@:2}
        ;;
    stop-devenv)
        stop-devenv ${@:2}
        ;;
    drop-devenv)
        drop-devenv ${@:2}
        ;;
    log-devenv)
        log-devenv ${@:2}
        ;;

    # production builds
    build-frontend-bundle)
        build-frontend-bundle;
        ;;

    build-backend-bundle)
        build-backend-bundle;
        ;;

    build-exporter-bundle)
        build-exporter-bundle;
        ;;

    # Podman Image Tasks
    *)
        usage
        ;;
esac
