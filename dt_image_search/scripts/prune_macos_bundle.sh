#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    exit 0
fi

APP_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path) APP_PATH="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ "$APP_PATH" != /* ]]; then
    APP_PATH="$(pwd)/$APP_PATH"
fi

[[ -n "$APP_PATH" ]] || { echo "Error: --app-path is required" >&2; exit 1; }
[[ -d "$APP_PATH" ]] || { echo "Error: .app not found: $APP_PATH" >&2; exit 1; }

TRANSFORMERS_MODELS_DIR="$APP_PATH/Contents/Resources/transformers/models"
if [[ ! -d "$TRANSFORMERS_MODELS_DIR" ]]; then
    exit 0
fi

KEEP_TRANSFORMERS_MODEL_DIRS=(
    auto
    bert
    clip
    encoder_decoder
    roberta
    xlm_roberta
)

echo "Pruning transformers model families in: $APP_PATH"
for dir in "$TRANSFORMERS_MODELS_DIR"/*; do
    [[ -d "$dir" ]] || continue
    dir_name="$(basename "$dir")"
    keep_dir=false
    for keep_name in "${KEEP_TRANSFORMERS_MODEL_DIRS[@]}"; do
        if [[ "$dir_name" == "$keep_name" ]]; then
            keep_dir=true
            break
        fi
    done

    if [[ "$keep_dir" == false ]]; then
        rm -rf "$dir"
    fi
done
