#!/usr/bin/env bash
set -eu

p_project=
p_dockerfile=
p_replicas=1
while [ $# -gt 0 ]; do
    case "$1" in
        --project)
            p_project=$2
            shift 2
            ;;
        --dockerfile)
            p_dockerfile=$2
            shift 2
            ;;
        --replicas)
            p_replicas=$2
            shift 2
            ;;
        *) break;;
    esac
done

start_app_container() {
    local i=$1
    docker run -d \
        -l bcompose="$p_project" \
        -l bcompose-service=app \
        -l bcompose-container=app-"$i" \
        "$p_project"
}

cid() {
    local service=$1 container=$2
    docker ps -qf label=bcompose="$p_project" \
        -f label=bcompose-service="$service" \
        -f label=bcompose-container="$container"
}

case "$1" in
    build)
        docker build -t "$p_project" -f "$p_dockerfile" .
        ;;

    up)
        for (( i = 1; i <= "$p_replicas"; i++ )); do
            cid=`cid app app-"$i"`
            if [ "$cid" ]; then
                docker stop -- "$cid"
            fi
            start_app_container "$i"
        done
        ;;

    down)
        docker ps -qf label=bcompose="$p_project" \
            | while IFS= read -r cid; do
                docker stop -- "$cid"
            done
        ;;

    *)
        printf '%s\n' "$0: unknown command ($1)" >&2
        exit 1
        ;;
esac
