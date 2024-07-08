#!/usr/bin/env bash
set -eu
g_bc_dir=`dirname -- "$0"`
g_bc_dir=`cd -- "$g_bc_dir"; pwd`

p_project=
p_app_build_args=()
p_app_args=()
p_app_cmd=()
declare -A p_app=(
    [name]=app
    [dockerfile]=
    [build_args]=p_app_build_args
    [args]=p_app_args
    [cmd]=p_app_cmd
    [http]=
    [replicas]=1
)
declare -n n_cur_svc=p_app
g_args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --project)
            p_project=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --name)
            n_cur_svc[name]=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --dockerfile)
            n_cur_svc[dockerfile]=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --build-arg)
            declare -n n_build_args=${n_cur_svc[build_args]}
            n_build_args+=("$1" "$2")
            g_args+=("$1" "$2")
            shift 2
            ;;
        --arg)
            declare -n n_args=${n_cur_svc[args]}
            n_args+=("$2")
            g_args+=("$1" "$2")
            shift 2
            ;;
        --cmd | --cmd-arg)
            declare -n n_cmd=${n_cur_svc[cmd]}
            n_cmd+=("$2")
            g_args+=("$1" "$2")
            shift 2
            ;;
        --http)
            n_cur_svc[http]=1
            g_args+=("$1")
            shift
            ;;
        --replicas)
            n_cur_svc[replicas]=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        *) break;;
    esac
done

services=("${p_app[name]}")
if [ "${p_app[http]}" ]; then
    services+=(haproxy)
fi

start_app_container() {
    local i=$1
    local -n p_args=${p_app[args]}
    local args=(${p_args[@]+"${p_args[@]}"})
    if [ "${p_app[http]}" ]; then
        args+=(--network "$p_project" --network-alias "${p_app[name]}")
    fi
    local -n p_cmd=${p_app[cmd]}
    docker run -d \
        -l bcompose="$p_project" \
        -l bcompose-service="${p_app[name]}" \
        -l bcompose-container="${p_app[name]}-$i" \
        ${args[@]+"${args[@]}"} \
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
        -e SERVER_NAME="${p_app[name]}" \
        -e REPLICAS="${p_app[replicas]}" \
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
        declare -n build_args=${p_app[build_args]}
        docker build \
            -t "$p_project" \
            -f "${p_app[dockerfile]}" \
            ${build_args[@]+"${build_args[@]}"} \
            .
        ;;

    up)
        if [ "${p_app[http]}" ]; then
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

        for (( i = 1; i <= "${p_app[replicas]}"; i++ )); do
            cid=`cid "${p_app[name]}" "${p_app[name]}-$i"`
            if [ "${p_app[http]}" ]; then
                if [ "$cid" ]; then
                    haproxy_cmd "disable server ${p_app[name]}/s$i"
                    docker stop -- "$cid"
                fi

                start_app_container "$i"
                haproxy_cmd "enable server ${p_app[name]}/s$i"

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
