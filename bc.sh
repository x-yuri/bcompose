#!/usr/bin/env bash
set -eu

p_project=
p_dockerfile=
p_build_args=()
p_args=()
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
        --build-arg)
            p_build_args+=("$1" "$2")
            shift 2
            ;;
        --arg)
            p_args+=("$2")
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
        "${p_args[@]}" \
        "$p_project"
}

cid() {
    local service=$1 container=${2-}
    local args=()
    if [ "$service" ]; then
        args+=(-f label=bcompose-service="$service")
    fi
    if [ "$container" ]; then
        args+=(-f label=bcompose-container="$container")
    fi
    docker ps -qf label=bcompose="$p_project" "${args[@]}"
}

case "$1" in
    ps)
        docker ps -f label=bcompose="$p_project"
        ;;

    build)
        docker build \
            -t "$p_project" \
            -f "$p_dockerfile" \
            "${p_build_args[@]}" \
            .
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

    exec)
        shift
        exec_args=()
        while [ $# -gt 0 ]; do
            case "$1" in
                -h) cat <<USAGE
Usage: $0 [ARG...] exec [EXEC_ARG...] [SERVICE|CONTAINER]... COMMAND [ARG...]
USAGE
                    exit
                    ;;
                --detach-keys | -e | --env | --env-file | -u | --user | -w | --workdir)
                    exec_args+=("$1" "$2")
                    shift 2
                    ;;
                --)
                    shift
                    break
                    ;;
                -*)
                    exec_args+=("$1")
                    shift
                    ;;
                *) break;;
            esac
        done
        p_name=$1
        shift

        cid=`cid '' "$p_name"`
        if ! [ "$cid" ]; then
            cid=`cid "$p_name"`
        fi
        docker exec "${exec_args[@]}" -- "$cid" "$@"
        ;;

    *)
        printf '%s\n' "$0: unknown command ($1)" >&2
        exit 1
        ;;
esac
