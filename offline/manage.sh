#!/usr/bin/env bash

set -Eeuo pipefail

OFFLINE_ROOT="$(
    readlink -f \
        "$(dirname "${BASH_SOURCE[0]}")/.."
)"

export OFFLINE_ROOT

# shellcheck disable=SC1091
source "$OFFLINE_ROOT/offline/lib/common.sh"

# shellcheck disable=SC1091
source "$OFFLINE_ROOT/offline/lib/gpu.sh"

# shellcheck disable=SC1091
source "$OFFLINE_ROOT/offline/lib/accept.sh"

offline_require_installation

case "${1:-}" in
    start)
        offline_compose \
            up \
            -d \
            --pull never \
            --wait

        echo \
            "OFFLINE START PASS"
        ;;

    stop)
        offline_compose down

        echo \
            "OFFLINE STOP PASS"
        ;;

    restart)
        offline_compose down

        offline_compose \
            up \
            -d \
            --pull never \
            --wait

        echo \
            "OFFLINE RESTART PASS"
        ;;

    status)
        offline_compose ps
        ;;

    logs)
        offline_compose logs \
            --tail="${TAIL:-200}" \
            -f \
            "${2:-chatbot}"
        ;;

    reindex)
        echo \
            "Stopping client-facing services..."

        offline_compose \
            stop proxy chatbot

        restore_services() {
            offline_compose \
                up \
                -d \
                chatbot \
                proxy \
                --pull never \
                --wait \
                >/dev/null 2>&1 \
                || true
        }

        trap \
            restore_services \
            EXIT HUP INT TERM

        offline_compose \
            up \
            -d \
            postgres \
            --pull never \
            --wait

        offline_compose \
            --profile tools \
            run \
            --rm \
            index-knowledge

        offline_compose \
            up \
            -d \
            chatbot \
            proxy \
            --pull never \
            --wait

        trap - \
            EXIT HUP INT TERM

        echo \
            "OFFLINE REINDEX PASS"
        ;;

    verify)
        offline_verify
        ;;

    accept)
        offline_accept
        ;;

    gpu)
        case "${2:-}" in
            enable)
                offline_gpu_enable \
                    "${3:-}"
                ;;

            disable)
                offline_gpu_disable
                ;;

            status)
                offline_gpu_status
                ;;

            *)
                offline_die \
                    "usage: $0 gpu {enable ADDON_DIR|disable|status}"
                ;;
        esac
        ;;

    *)
        cat >&2 <<EOF
usage: $0 COMMAND

commands:
  start
  stop
  restart
  status
  logs [service]
  reindex
  verify
  accept
  gpu enable ADDON_DIR
  gpu disable
  gpu status
EOF
        exit 2
        ;;
esac
