export PYTHONPATH=$PYTHONPATH:.

# python3 -m pytest tests/unit/test_dts_db.py
python3 -m pytest -s --log-cli-level=INFO tests/unit/test_dts_index.py
python3 -m pytest -s --log-cli-level=INFO tests/unit/test_search_controller.py
python3 -m pytest -s --log-cli-level=INFO tests/functional/test_app_flow.py