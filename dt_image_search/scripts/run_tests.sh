#!/bin/bash

set -euo pipefail

this_scrit="$0"
if [[ "$this_scrit" != /* ]]; then
  this_scrit="$(pwd)/$this_scrit"
fi
this_dir="$(dirname "$this_scrit")"

level=INFO
need_build=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --build)
      need_build=true
      shift
      ;;
    --log-level)
      level="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done


export PYTHONPATH=${PYTHONPATH:-}${PYTHONPATH:+:}.

echo "PYTHONPATH set to: $PYTHONPATH"

python_bin=python
if ! command -v $python_bin &> /dev/null; then
    echo "$python_bin could not be found, trying python..."
    python_bin=python3
    if ! command -v $python_bin &> /dev/null; then
        echo "Neither python nor python3 could be found. Please install Python and ensure it's in your PATH."
        exit 1
    fi
fi

export IS_TESTING=true

$python_bin -m pytest -s --log-cli-level=$level tests/unit/test_dts_index.py
$python_bin -m pytest -s --log-cli-level=$level tests/unit/test_search_controller.py
$python_bin -m pytest -s --log-cli-level=$level tests/functional/test_app_flow.py
$python_bin -m pytest -s --log-cli-level=$level tests/functional/test_mobile_backup_flow.py

if [ "$need_build" = true ]; then
    echo "Building app with PyInstaller..."
    pyinstaller dt_image_search/DTImageSearch.spec --noconfirm --clean
fi

bash "$this_dir/uitest_bootstrap.sh"
bash "$this_dir/uitest_start.sh"