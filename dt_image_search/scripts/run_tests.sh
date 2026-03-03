#!/bin/bash

level="${1:-INFO}"

export PYTHONPATH=$PYTHONPATH:.

# python3 -m pytest tests/unit/test_dts_db.py
python3 -m pytest -s --log-cli-level=$level tests/unit/test_dts_index.py
python3 -m pytest -s --log-cli-level=$level tests/unit/test_search_controller.py
python3 -m pytest -s --log-cli-level=$level tests/functional/test_app_flow.py

exit 0
pyinstaller dt_image_search/DTImageSearch.spec --noconfirm --clean

node_modules/.bin/appium || true

python3 tests/integration/test_golden_path_appium.py