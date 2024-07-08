#!/usr/bin/env bash
set -eu
g_bc_dir=`dirname -- "$0"`
g_bc_dir=`cd -- "$g_bc_dir"; pwd`

p_project=
p_dockerfile=
p_build_args=()
p_args=()
p_cmd=()
p_http=
p_replicas=1
g_args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --project)
            p_project=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --dockerfile)
            p_dockerfile=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --build-arg)
            p_build_args+=("$1" "$2")
            g_args+=("$1" "$2")
            shift 2
            ;;
        --arg)
            p_args+=("$2")
            g_args+=("$1" "$2")
            shift 2
            ;;
        --cmd | --cmd-arg)
            p_cmd+=("$2")
            g_args+=("$1" "$2")
            shift 2
            ;;
        --http)
            p_http=1
            g_args+=("$1")
            shift
            ;;
        --replicas)
            p_replicas=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        *) break;;
    esac
done

services=(app)
if [ "$p_http" ]; then
    services+=(haproxy)
fi

start_app_container() {
    local i=$1
    local args=()
    if [ "$p_http" ]; then
        args+=(--network "$p_project" --network-alias app)
    fi
    docker run -d \
        -l bcompose="$p_project" \
        -l bcompose-service=app \
        -l bcompose-container=app-"$i" \
        ${args[@]+"${args[@]}"} \
        ${p_args[@]+"${p_args[@]}"} \
        "$p_project" \
        ${p_cmd[@]+"${p_cmd[@]}"}
}

start_haproxy_container() {
    docker run -d \
        -l bcompose="$p_project" \
        -l bcompose-service=haproxy \
        -l bcompose-container=haproxy \
        --network "$p_project" \
        --network-alias haproxy \
        -e REPLICAS="$p_replicas" \
        -v "$g_bc_dir"/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro \
        bcompose-haproxy
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
    docker ps -qf label=bcompose="$p_project" ${args[@]+"${args[@]}"}
}

get_server_status() {
    haproxy_cmd 'show stat' \
        | awk -F, -v server="$1" '
            NR == 1 {
                gsub(/^# /, "", $0)
                split($0, headers, ",")
                for (i = 1; i in headers; i++) {
                    if (headers[i] == "svname") svname_idx = i;
                    if (headers[i] == "status") status_idx = i;
                    if (headers[i] == "check_status") check_status_idx = i;
                }
            }
            NR > 1 && $svname_idx == server {
                print $status_idx "|" $check_status_idx
            }
        '
}

haproxy_cmd() {
    printf '%s\n' "$1" \
        | "$0" ${g_args[@]+"${g_args[@]}"} exec -i \
            haproxy socat - /var/lib/haproxy/haproxy.sock
}

case "$1" in
    ps)
        docker ps -f label=bcompose="$p_project"
        ;;

    build)
        docker build \
            -t "$p_project" \
            -f "$p_dockerfile" \
            ${p_build_args[@]+"${p_build_args[@]}"} \
            .
        ;;

    up)
        if [ "$p_http" ]; then
            if ! [ "`docker network ls -qf label=bcompose="$p_project"`" ]; then
                docker network create --label bcompose="$p_project" \
                    -- "$p_project"
            fi

            if ! [ "`cid haproxy haproxy`" ]; then
                docker build -t bcompose-haproxy \
                             -f "$g_bc_dir/Dockerfile-haproxy" \
                             "$g_bc_dir"
                start_haproxy_container
            fi
        fi

        for (( i = 1; i <= "$p_replicas"; i++ )); do
            cid=`cid app app-"$i"`
            if [ "$p_http" ]; then
                if [ "$cid" ]; then
                    haproxy_cmd "disable server app/s$i"
                    docker stop -- "$cid"
                fi

                start_app_container "$i"
                haproxy_cmd "enable server app/s$i"

                while true; do
                    status=`get_server_status "s$i"`
                    check_status=${status#*|}
                    status=${status%|*}
                    if [ "$status" = UP ] && [[ "$check_status" =~ ^L[467]OK$ ]]; then
                        break
                    fi
                    sleep 1
                done
            else
                if [ "$cid" ]; then
                    docker stop -- "$cid"
                fi
                start_app_container "$i"
            fi
        done
        ;;

    down)
        docker ps -qf label=bcompose="$p_project" \
            | while IFS= read -r cid; do
                docker stop -- "$cid"
            done
        docker network ls -qf label=bcompose="$p_project" \
            | while IFS= read -r nid; do
                docker network rm "$nid"
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
        docker exec ${exec_args[@]+"${exec_args[@]}"} -- "$cid" "$@"
        ;;

    logs)
        shift
        log_args=()
        while [ $# -gt 0 ]; do
            case "$1" in
                -h) cat <<USAGE
Usage: $0 [ARG...] logs [LOG_ARG...] [SERVICE|CONTAINER]...
USAGE
                    exit
                    ;;
                --since | -n | --tail | --until)
                    log_args+=("$1" "$2")
                    shift 2
                    ;;
                --)
                    shift
                    break
                    ;;
                -*)
                    log_args+=("$1")
                    shift
                    ;;
                *) break;;
            esac
        done

        if (( $# )); then
            cids=$(
                for t; do
                    cids=`cid "$t"`
                    if [ "$cids" = '' ]; then
                        cids=`cid '' "$t"`
                    fi
                    printf '%s\n' "$cids"
                done
            )
            if [ "$cids" = '' ]; then
                n_cids=0
            else
                n_cids=`printf '%s\n' "$cids" | wc -l`
            fi
            if [ "$n_cids" = 0 ]; then
                :
            elif [ "$n_cids" = 1 ]; then
                docker logs ${log_args[@]+"${log_args[@]}"} -- "$cids"
            else
                trap 'tput sgr0; trap INT; kill -2 $$' INT
                printf '%s\n' "$cids" \
                    | {
                        i=1
                        while IFS= read -r cid; do
                            ( trap INT
                            docker logs ${log_args[@]+"${log_args[@]}"} -- "$cid" \
                                |& sed "s/^/`tput setaf "$i"`$cid | /" ) &
                            i=$(( i + 1 ))
                        done
                        wait
                    }
                tput sgr0
            fi
        else
            "$0" ${g_args[@]+"${g_args[@]}"} \
                logs \
                ${log_args[@]+"${log_args[@]}"} \
                -- ${services[@]+"${services[@]}"}
        fi
        ;;

    *)
        printf '%s\n' "$0: unknown command ($1)" >&2
        exit 1
        ;;
esac
