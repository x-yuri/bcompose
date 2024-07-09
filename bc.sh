#!/usr/bin/env bash
set -eu
g_bc_dir=`dirname -- "$0"`
g_bc_dir=`cd -- "$g_bc_dir"; pwd`

array_size() {
    [ "$1" = a ] || local -n a=$1
    if declare -p "$1" >/dev/null 2>&1; then
        echo ${#a[@]}
    else
        echo 0
    fi
}

p_project=
p_haproxy_env=()
p_haproxy_network=
p_haproxy_expose=
p_app_build_args=()
p_app_args=()
p_app_cmd=()
declare -A p_app=(
    [name]=app
    [context]=.
    [dockerfile]=
    [build_args]=p_app_build_args
    [args]=p_app_args
    [cmd]=p_app_cmd
    [http]=
    [replicas]=1
)
p_more_services=()
cur_svc=p_app
declare -n n_cur_svc=$cur_svc
g_args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --project)
            p_project=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --haproxy-env)
            p_haproxy_env+=("$2")
            g_args+=("$1" "$2")
            shift 2
            ;;
        --haproxy-network)
            p_haproxy_network=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --haproxy-expose)
            p_haproxy_expose=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --name)
            n_cur_svc[name]=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --context)
            n_cur_svc[context]=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --same-context)
            if [ "$cur_svc" = p_app ]; then
                printf '%s\n' "$0: $1 can not be specified for an app" >&2
                exit 1
            fi
            n_cur_svc[context]=${p_app[context]}
            g_args+=("$1")
            shift
            ;;
        --dockerfile)
            n_cur_svc[dockerfile]=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --same-dockerfile)
            if [ "$cur_svc" = p_app ]; then
                printf '%s\n' "$0: $1 can not be specified for an app" >&2
                exit 1
            fi
            n_cur_svc[dockerfile]=${p_app[dockerfile]}
            g_args+=("$1")
            shift
            ;;
        --build-arg)
            declare -n n_build_args=${n_cur_svc[build_args]}
            n_build_args+=("$1" "$2")
            g_args+=("$1" "$2")
            shift 2
            ;;
        --same-build-args)
            if [ "$cur_svc" = p_app ]; then
                printf '%s\n' "$0: $1 can not be specified for an app" >&2
                exit 1
            fi
            n_cur_svc[build_args]=${p_app[build_args]}
            g_args+=("$1")
            shift
            ;;
        --arg)
            declare -n n_args=${n_cur_svc[args]}
            n_args+=("$2")
            g_args+=("$1" "$2")
            shift 2
            ;;
        --same-args)
            if [ "$cur_svc" = p_app ]; then
                printf '%s\n' "$0: $1 can not be specified for an app" >&2
                exit 1
            fi
            n_cur_svc[args]=${p_app[args]}
            g_args+=("$1")
            shift
            ;;
        --cmd | --cmd-arg)
            declare -n n_cmd=${n_cur_svc[cmd]}
            n_cmd+=("$2")
            g_args+=("$1" "$2")
            shift 2
            ;;
        --same-cmd)
            if [ "$cur_svc" = p_app ]; then
                printf '%s\n' "$0: $1 can not be specified for an app" >&2
                exit 1
            fi
            n_cur_svc[cmd]=${p_app[cmd]}
            g_args+=("$1")
            shift
            ;;
        --http)
            if [ "$cur_svc" = p_upstream ]; then
                printf '%s\n' "$0: $1 can only be specified for an app" >&2
                exit 1
            fi
            n_cur_svc[http]=1
            g_args+=("$1")
            shift
            ;;
        --replicas)
            if [ "$cur_svc" = p_upstream ]; then
                printf '%s\n' "$0: number of app and upstream replicas should match" >&2
                exit 1
            fi
            if [ "$cur_svc" != p_app ]; then
                printf '%s\n' "$0: number of replicas can only be specified for an app" >&2
                exit 1
            fi
            n_cur_svc[replicas]=$2
            g_args+=("$1" "$2")
            shift 2
            ;;
        --upstream)
            if [ "$cur_svc" = p_upstream ]; then
                printf '%s\n' "$0: there can be only one upstream" >&2
                exit 1
            fi
            if ! [ "${p_app[http]}" ]; then
                printf '%s\n' "$0: --upstream expects --http for the app" >&2
                exit 1
            fi
            p_upstream_build_args=()
            p_upstream_args=()
            p_upstream_cmd=()
            declare -A p_upstream=(
                [name]=upstream
                [context]=.
                [dockerfile]=
                [build_args]=p_upstream_build_args
                [args]=p_upstream_args
                [cmd]=p_upstream_cmd
            )
            cur_svc=p_upstream
            declare -n n_cur_svc=$cur_svc
            g_args+=("$1")
            shift
            ;;
        --service)
            i=$(( `array_size p_more_services` + 1 ))
            cur_svc=p_service_$i
            declare -A $cur_svc
            declare -n n_cur_svc=$cur_svc
            p_more_services+=($cur_svc)

            n_cur_svc[name]=
            n_cur_svc[context]=.
            n_cur_svc[dockerfile]=

            build_args_array_name=p_service_${i}_build_args
            eval "$build_args_array_name=()"
            n_cur_svc[build_args]=$build_args_array_name

            args_array_name=p_service_${i}_args
            eval "$args_array_name=()"
            n_cur_svc[args]=$args_array_name

            cmd_array_name=p_service_${i}_cmd
            eval "$cmd_array_name=()"
            n_cur_svc[cmd]=$cmd_array_name

            g_args+=("$1")
            shift
            ;;
        *) break;;
    esac
done

services=("${p_app[name]}")
if [ "${p_app[http]}" ]; then
    services+=(haproxy)
fi
if [ -v p_upstream[@] ]; then
    services+=("${p_upstream[name]}")
fi
if (( `array_size p_more_services` )); then
    declare -n s
    for s in ${p_more_services[@]+"${p_more_services[@]}"}; do
        services+=("${s[name]}")
    done
fi

start_svc_container() {
    local sv=$1
    [ "$sv" = s ] || local -n s=$sv
    local i=${2-}
    local -n p_args=${s[args]}
    local args=(${p_args[@]+"${p_args[@]}"})
    if [ "${p_app[http]}" ] || (( `array_size p_more_services` )); then
        args+=(--network "$p_project" --network-alias "${s[name]}")
    fi
    local image
    if [ "${s[name]}" = "${p_app[name]}" ]; then
        image=$p_project
    else
        image=$p_project-${s[name]}
    fi
    if [ "$sv" != p_app ] \
    && [ "${p_app[dockerfile]}" = "${s[dockerfile]}" ] \
    && [ "${!p_app[build_args]}" = "${!s[build_args]}" ]; then
        image=$p_project
    fi
    local -n p_cmd=${s[cmd]}
    docker run -d \
        -l bcompose="$p_project" \
        -l bcompose-service="${s[name]}" \
        -l bcompose-container="${s[name]}${i:+-"$i"}" \
        ${args[@]+"${args[@]}"} \
        "$image" \
        ${p_cmd[@]+"${p_cmd[@]}"}
}

start_haproxy_container() {
    local args=()
    local env
    for env in ${p_haproxy_env[@]+"${p_haproxy_env[@]}"}; do
        args+=(-e "$env")
    done
    if [ "$p_haproxy_expose" ]; then
        args+=(--expose "$p_haproxy_expose")
    fi
    local cid
    cid=`docker create \
        -l bcompose="$p_project" \
        -l bcompose-service=haproxy \
        -l bcompose-container=haproxy \
        --network "$p_project" \
        --network-alias haproxy \
        -e SERVER_NAME="${p_app[name]}" \
        -e REPLICAS="${p_app[replicas]}" \
        ${args[@]+"${args[@]}"} \
        -v "$g_bc_dir"/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro \
        bcompose-haproxy`
    if [ "$p_haproxy_network" ]; then
        docker network connect "$p_haproxy_network" "$cid"
    fi
    docker start "$cid"
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
            "${p_app[context]}"

        if [ -v p_upstream[@] ] \
        && { [ "${p_upstream[dockerfile]}" != "${p_app[dockerfile]}" ] \
        || [ "${!p_upstream[build_args]}" != "${!p_app[build_args]}" ]; }; then
            declare -n build_args=${p_upstream[build_args]}
            docker build \
                -t "$p_project-${p_upstream[name]}" \
                -f "${p_upstream[dockerfile]}" \
                ${build_args[@]+"${build_args[@]}"} \
                "${p_upstream[context]}"
        fi

        if (( `array_size p_more_services` )); then
            declare -n s
            for s in ${p_more_services[@]+"${p_more_services[@]}"}; do
                if { [ "${s[dockerfile]}" != "${p_app[dockerfile]}" ] \
                || [ "${!s[build_args]}" != "${!p_app[build_args]}" ]; }; then
                    declare -n build_args=${s[build_args]}
                    docker build \
                        -t "$p_project-${s[name]}" \
                        -f "${s[dockerfile]}" \
                        ${build_args[@]+"${build_args[@]}"} \
                        "${s[context]}"
                fi
            done
        fi
        ;;

    up)
        if [ "${p_app[http]}" ] || (( `array_size p_more_services` )); then
            if ! [ "`docker network ls -qf label=bcompose="$p_project"`" ]; then
                docker network create --label bcompose="$p_project" \
                    -- "$p_project"
            fi
        fi

        if (( `array_size p_more_services` )); then
            for sv in ${p_more_services[@]+"${p_more_services[@]}"}; do
                declare -n s=$sv
                cid=`cid "${s[name]}" "${s[name]}"`
                if ! [ "$cid" ]; then
                    start_svc_container "$sv"
                fi
            done
        fi

        if [ "${p_app[http]}" ]; then
            if ! [ "`cid haproxy haproxy`" ]; then
                docker build -t bcompose-haproxy \
                             -f "$g_bc_dir/Dockerfile-haproxy" \
                             "$g_bc_dir"
                start_haproxy_container
            fi
        fi

        for (( i = 1; i <= "${p_app[replicas]}"; i++ )); do
            if [ "${p_app[http]}" ]; then
                r=`haproxy_cmd "disable server ${p_app[name]}/s$i"`
                if [ "$r" ]; then
                    printf '%s\n' "$r"
                fi
                if [ -v p_upstream[@] ]; then
                    cid=`cid "${p_upstream[name]}" "${p_upstream[name]}-$i"`
                    if [ "$cid" ]; then
                        docker stop -- "$cid"
                    fi
                fi
                cid=`cid "${p_app[name]}" "${p_app[name]}-$i"`
                if [ "$cid" ]; then
                    docker stop -- "$cid"
                fi

                if [ -v p_upstream[@] ]; then
                    start_svc_container p_upstream "$i"
                fi
                start_svc_container p_app "$i"
                r=`haproxy_cmd "enable server ${p_app[name]}/s$i"`
                if [ "$r" ]; then
                    printf '%s\n' "$r"
                fi

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
                if [ -v p_upstream[@] ]; then
                    cid=`cid "${p_upstream[name]}" "${p_upstream[name]}-$i"`
                    if [ "$cid" ]; then
                        docker stop -- "$cid"
                    fi
                fi
                cid=`cid "${p_app[name]}" "${p_app[name]}-$i"`
                if [ "$cid" ]; then
                    docker stop -- "$cid"
                fi

                if [ -v p_upstream[@] ]; then
                    start_svc_container p_upstream "$i"
                fi
                start_svc_container p_app "$i"
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
