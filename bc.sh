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
    [image]=
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
        --image)
            n_cur_svc[image]=$2
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
        --args)
            declare -n n_args=${n_cur_svc[args]}
            while [ $# -gt 0 ]; do
                case "$1" in
                    --name | --image | --context | --same-context | --dockerfile | --same-dockerfile | --build-arg | --same-build-args | --same-args | --cmd | --same-cmd | --http | --replicas | --restart-on-up | --upstream | --service)
                        break
                        ;;
                    --args) g_args+=("$1"); shift;;
                    --) g_args+=("$1"); shift; break;;
                    *) n_args+=("$1"); g_args+=("$1"); shift;;
                esac
            done
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
        --cmd)
            declare -n n_cmd=${n_cur_svc[cmd]}
            while [ $# -gt 0 ]; do
                case "$1" in
                    --name | --image | --context | --same-context | --dockerfile | --same-dockerfile | --build-arg | --same-build-args | --args | --same-args | --same-cmd | --http | --replicas | --restart-on-up | --upstream | --service)
                        break
                        ;;
                    --cmd) g_args+=("$1"); shift;;
                    --) g_args+=("$1"); shift; break;;
                    *) n_cmd+=("$1"); g_args+=("$1"); shift;;
                esac
            done
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
        --restart-on-up)
            if [ "$cur_svc" = p_app ]; then
                printf '%s\n' "$0: $1 can not be specified for an app" >&2
                exit 1
            fi
            if [ "$cur_svc" = p_upstream ]; then
                printf '%s\n' "$0: $1 can not be specified for upstream" >&2
                exit 1
            fi
            n_cur_svc[restart_on_up]=1
            g_args+=("$1")
            shift
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
                [image]=
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
            n_cur_svc[image]=
            n_cur_svc[context]=.
            n_cur_svc[dockerfile]=
            n_cur_svc[restart_on_up]=

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
        if [ "$i" ]; then
            args+=(--network-alias "${s[name]}-$i")
        fi
    fi
    if [ "$i" ]; then
        args+=(-e i="$i")
    fi
    local image
    image=`svc_image "$sv"`
    local -n p_cmd=${s[cmd]}
    local cmd=(
        docker create
        -l bcompose="$p_project"
        -l bcompose-service="${s[name]}"
        -l bcompose-container="${s[name]}${i:+-"$i"}"
        ${args[@]+"${args[@]}"}
        "$image"
        ${p_cmd[@]+"${p_cmd[@]}"}
    )
    c "${cmd[@]}"
    "${cmd[@]}"
    local cid
    cid=`"${cmd[@]}"`
    docker start "$cid"
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
    local cmd=(
        docker create
        -l bcompose="$p_project"
        -l bcompose-service=haproxy
        -l bcompose-container=haproxy
        --network "$p_project"
        --network-alias haproxy
        -e SERVER_NAME="${p_app[name]}"
        -e REPLICAS="${p_app[replicas]}"
        ${args[@]+"${args[@]}"}
        -v "$g_bc_dir"/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
        bcompose-haproxy
    )
    c "${cmd[@]}"
    local cid
    cid=`"${cmd[@]}"`
    if [ "$p_haproxy_network" ]; then
        docker network connect "$p_haproxy_network" "$cid"
    fi
    docker start "$cid"
}

svc_image() {
    local sv=$1
    [ "$sv" = s ] || local -n s=$sv
    if [ "${s[image]}" ]; then
        printf '%s\n' "${s[image]}"
        return
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
    printf '%s\n' "$image"
}

svc_by_name() {
    local n=$1
    if [ "${p_app[name]}" = "$n" ]; then
        echo p_app
        return
    fi
    if [ -v p_upstream[@] ] && [ "${p_upstream[name]}" = "$n" ]; then
        echo p_upstream
        return
    fi
    if (( `array_size p_more_services` )); then
        local sv
        for sv in ${p_more_services[@]+"${p_more_services[@]}"}; do
            declare -n s=$sv
            if [ "${s[name]}" = "$n" ]; then
                printf '%s\n' "$sv"
                return
            fi
        done
    fi
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

h() {
    echo
    tput setaf 3
    printf '> %s\n' "$*"
    tput sgr0
}

c() {
    tput setaf 8
    printf '$ %s\n' "$*"
    tput sgr0
}

case "$1" in
    ps)
        docker ps -f label=bcompose="$p_project"
        ;;

    pull)
        if [ "${p_app[image]}" ]; then
            h "pull ${p_app[image]}"
            docker pull -- "${p_app[image]}"
        fi

        if [ -v p_upstream[@] ] && [ "${p_upstream[image]}" ]; then
            h "pull ${p_upstream[image]}"
            docker pull -- "${p_upstream[image]}"
        fi

        if (( `array_size p_more_services` )); then
            declare -n s
            for s in ${p_more_services[@]+"${p_more_services[@]}"}; do
                if [ "${s[image]}" ]; then
                    h "pull ${s[image]}"
                    docker pull -- "${s[image]}"
                fi
            done
        fi
        ;;

    build)
        if ! [ "${p_app[image]}" ]; then
            h "build $p_project"
            declare -n build_args=${p_app[build_args]}
            cmd=(
                docker build
                -t "$p_project"
                -f "${p_app[dockerfile]}"
                ${build_args[@]+"${build_args[@]}"}
                "${p_app[context]}"
            )
            c "${cmd[@]}"
            "${cmd[@]}"
        fi

        if [ -v p_upstream[@] ] \
        && ! [ "${p_upstream[image]}" ] \
        && { [ "${p_upstream[dockerfile]}" != "${p_app[dockerfile]}" ] \
        || [ "${!p_upstream[build_args]}" != "${!p_app[build_args]}" ]; }; then
            h "build $p_project-${p_upstream[name]}"
            declare -n build_args=${p_upstream[build_args]}
            cmd=(
                docker build
                -t "$p_project-${p_upstream[name]}"
                -f "${p_upstream[dockerfile]}"
                ${build_args[@]+"${build_args[@]}"}
                "${p_upstream[context]}"
            )
            c "${cmd[@]}"
            "${cmd[@]}"
        fi

        if (( `array_size p_more_services` )); then
            declare -n s
            for s in ${p_more_services[@]+"${p_more_services[@]}"}; do
                if ! [ "${s[image]}" ] \
                && { [ "${s[dockerfile]}" != "${p_app[dockerfile]}" ] \
                || [ "${!s[build_args]}" != "${!p_app[build_args]}" ]; }; then
                    h "build $p_project-${s[name]}"
                    declare -n build_args=${s[build_args]}
                    cmd=(
                        docker build
                        -t "$p_project-${s[name]}"
                        -f "${s[dockerfile]}"
                        ${build_args[@]+"${build_args[@]}"}
                        "${s[context]}"
                    )
                    c "${cmd[@]}"
                    "${cmd[@]}"
                fi
            done
        fi
        ;;

    up)
        if [ "${p_app[http]}" ] || (( `array_size p_more_services` )); then
            if ! [ "`docker network ls -qf label=bcompose="$p_project"`" ]; then
                h create network "$p_project"
                docker network create --label bcompose="$p_project" \
                    -- "$p_project"
            fi
        fi

        if (( `array_size p_more_services` )); then
            for sv in ${p_more_services[@]+"${p_more_services[@]}"}; do
                declare -n s=$sv
                if [ "${s[restart_on_up]}" ]; then
                    cid=`cid "${s[name]}" "${s[name]}"`
                    if [ "$cid" ]; then
                        h "stop ${s[name]}"
                        docker stop -- "$cid"
                    fi

                    h "start ${s[name]}"
                    start_svc_container "$sv"
                else
                    cid=`cid "${s[name]}" "${s[name]}"`
                    if ! [ "$cid" ]; then
                        h "start ${s[name]}"
                        start_svc_container "$sv"
                    fi
                fi
            done
        fi

        if [ "${p_app[http]}" ]; then
            if ! [ "`cid haproxy haproxy`" ]; then
                docker build -t bcompose-haproxy \
                             -f "$g_bc_dir/Dockerfile-haproxy" \
                             "$g_bc_dir"
                h start haproxy
                start_haproxy_container
            fi
        fi

        for (( i = 1; i <= "${p_app[replicas]}"; i++ )); do
            if [ "${p_app[http]}" ]; then
                h "disable ${p_app[name]}-$i"
                r=`haproxy_cmd "disable server ${p_app[name]}/s$i"`
                if [ "$r" ]; then
                    printf '%s\n' "$r"
                fi

                if [ -v p_upstream[@] ]; then
                    cid=`cid "${p_upstream[name]}" "${p_upstream[name]}-$i"`
                    if [ "$cid" ]; then
                        h "stop ${p_upstream[name]}-$i"
                        docker stop -- "$cid"
                    fi
                fi

                cid=`cid "${p_app[name]}" "${p_app[name]}-$i"`
                if [ "$cid" ]; then
                    h "stop ${p_app[name]}-$i"
                    docker stop -- "$cid"
                fi

                if [ -v p_upstream[@] ]; then
                    h "start ${p_upstream[name]}-$i"
                    start_svc_container p_upstream "$i"
                fi

                h "start ${p_app[name]}-$i"
                start_svc_container p_app "$i"

                h "enable ${p_app[name]}-$i"
                r=`haproxy_cmd "enable server ${p_app[name]}/s$i"`
                if [ "$r" ]; then
                    printf '%s\n' "$r"
                fi

                h wait for status up
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
                        h "stop ${p_upstream[name]}-$i"
                        docker stop -- "$cid"
                    fi
                fi

                cid=`cid "${p_app[name]}" "${p_app[name]}-$i"`
                if [ "$cid" ]; then
                    h "stop ${p_app[name]}-$i"
                    docker stop -- "$cid"
                fi

                if [ -v p_upstream[@] ]; then
                    h "start ${p_upstream[name]}-$i"
                    start_svc_container p_upstream "$i"
                fi

                h "start ${p_app[name]}-$i"
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

    run)
        shift
        run_args=()
        p_needs=()
        while [ $# -gt 0 ]; do
            case "$1" in
                -h) cat <<USAGE
Usage: $0 [ARG...] run [RUN_ARG...] SERVICE COMMAND [ARG...]
USAGE
                    exit
                    ;;
                --needs)
                    p_needs+=("$2")
                    shift 2
                    ;;
                --add-host | -a | --attach | --blkio-weight | --blkio-weight-device | --cap-add | --cap-drop | --cgroup-parent | --cidfile | --cpu-period | --cpu-quota | --cpu-rt-period | --cpu-rt-runtime | -c | --cpu-shares | --cpus | --cpuset-cpus | --cpuset-mems | --detach-keys | --device | --device-cgroup-rule | --device-read-bps | --device-read-iops | --device-write-bps | --device-write-iops | --dns | --dns-option | --dns-search | --entrypoint | -e | --env | --env-file | --expose | --group-add | --health-cmd | --health-interval | --health-retries | --health-start-period | --health-timeout | -h | --hostname | --ip | --ip6 | --ipc | --isolation | --kernel-memory | -l | --label | --label-file | --link | --link-local-ip | --log-driver | --log-opt | --mac-address | -m | --memory | --memory-reservation | --memory-swap | --memory-swappiness | --mount | --name | --network | --network-alias | --oom-score-adj | --pid | --pids-limit | -p | --publish | --restart | --runtime | --security-opt | --shm-size | --stop-signal | --stop-timeout | --storage-opt | --sysctl | --tmpfs | --ulimit | -u | --user | --userns | --uts | -v | --volume | --volume-driver | --volumes-from | -w | --workdir)
                    run_args+=("$1" "$2")
                    shift 2
                    ;;
                --)
                    shift
                    break
                    ;;
                -*)
                    run_args+=("$1")
                    shift
                    ;;
                *) break;;
            esac
        done
        p_service=$1
        shift

        args=()
        if (( `array_size p_needs` )); then
            args+=(--network "$p_project")
            if ! [ "`docker network ls -qf label=bcompose="$p_project"`" ]; then
                h create network "$p_project"
                docker network create --label bcompose="$p_project" \
                    -- "$p_project"
            fi
        fi

        for sn in ${p_needs[@]+"${p_needs[@]}"}; do
            sv=`svc_by_name "$sn"`
            declare -n s=$sv
            if [ "${s[name]}" = "${p_app[name]}" ]; then
                printf '%s\n' "$0: can't need app" >&2
                exit 1
            fi
            if [ -v p_upstream[@] ] \
            && [ "${s[name]}" = "${p_upstream[name]}" ]; then
                printf '%s\n' "$0: can't need upstream" >&2
                exit 1
            fi
            cid=`cid "${s[name]}" "${s[name]}"`
            if ! [ "$cid" ]; then
                h "start ${s[name]}"
                start_svc_container "$sv"
            fi
        done

        sv=`svc_by_name "$p_service"`
        image=`svc_image "$sv"`
        h run
        cmd=(
            docker run ${run_args[@]+"${run_args[@]}"}
            ${args[@]+"${args[@]}"}
            "$image" "$@"
        )
        c "${cmd[@]}"
        "${cmd[@]}"
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
