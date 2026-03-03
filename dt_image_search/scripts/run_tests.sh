#!/bin/bash

set -euo pipefail

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

# python3 -m pytest tests/unit/test_dts_db.py
python3 -m pytest -s --log-cli-level=$level tests/unit/test_dts_index.py
python3 -m pytest -s --log-cli-level=$level tests/unit/test_search_controller.py
python3 -m pytest -s --log-cli-level=$level tests/functional/test_app_flow.py

if [ "$need_build" = true ]; then
    echo "Building app with PyInstaller..."
    pyinstaller dt_image_search/DTImageSearch.spec --noconfirm --clean
fi

python3 tests/integration/test_golden_path_appium.py