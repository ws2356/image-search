#!/usr/bin/env bash
set -euo pipefail

this_file="${BASH_SOURCE[0]}"
this_dir="$(dirname "$this_file")"

environment=
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)
            environment="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [ "$environment" != "dev" ] && [ "$environment" != "prod" ]; then
    echo "Usage: $0 --env <dev|prod>"
    exit 1
fi

cd "$this_dir/../.."

set -a; . "$this_dir/.env.$environment"; set +a
python -m dt_image_search.scripts.instant_share_agent_main --force-enable --log-level DEBUG