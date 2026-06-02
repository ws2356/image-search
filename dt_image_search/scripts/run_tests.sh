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

unit_and_functional_tests=(
  tests/unit/test_instant_share_contracts.py
  tests/unit/test_instant_share_client.py
  tests/unit/test_instant_share_session.py
  tests/unit/test_instant_share_delivery.py
  tests/unit/test_instant_share_receiver.py
  tests/unit/test_instant_share_lifecycle_notifications.py
  tests/unit/test_instant_share_runtime.py
  tests/unit/test_instant_share_sender_validation.py
  tests/unit/test_instant_share_telemetry.py
  tests/unit/test_mobile_apple_mobile_device_support.py
  tests/unit/test_dts_index.py
  tests/unit/test_browse_controller_mobile_folder.py
  tests/unit/test_dts_db_folder_path_variants.py
  tests/unit/test_index_worker.py
  tests/unit/test_incremental_index_worker.py
  tests/unit/test_mobile_folder_controller.py
  tests/unit/test_mobile_backup_state_machine.py
  tests/unit/test_mobile_dialogs.py
  tests/unit/test_mainwindow_section_expansion.py
  tests/unit/test_mobile_pairing_discovery.py
  tests/unit/test_mobile_pairing_service.py
  tests/unit/test_mobile_pairing_session.py
  tests/unit/test_mobile_transfer_service.py
  tests/unit/test_mobile_transport_manager.py
  tests/unit/test_mobile_transport_router.py
  tests/unit/test_mobile_usb_tunnel.py
  tests/unit/test_mobile_usb_ws_adapter.py
  tests/unit/test_feature_flags.py
  tests/unit/test_pil_image_support.py
  tests/unit/test_fs_image_list_model.py
  tests/unit/test_thumbnail_job.py
  tests/unit/test_crash_support.py
  tests/unit/test_runtime_metadata.py
  tests/unit/test_search_controller.py
  tests/functional/test_mobile_backup_flow.py
  tests/functional/test_usb_handshake_pc_side.py
  tests/functional/test_instant_share_e2e.py
  tests/functional/test_crash_recovery_harness.py
)
 # tests/functional/test_app_flow.py

has_failed=false
for test in "${unit_and_functional_tests[@]}"; do
  if ! $python_bin "$test"; then
    has_failed=true
  fi
done

# Run UI tests only on Windows os
# if [[ "$OSTYPE" == "msys" ]]; then
#   if [ "$need_build" = true ]; then
#       echo "Building app with PyInstaller..."
#       pyinstaller dt_image_search/DTImageSearch.spec --noconfirm --clean
#   fi
# 
#   bash "$this_dir/uitest_bootstrap.sh"
#   bash "$this_dir/uitest_start.sh"
# else
#     echo "Skipping UI tests on non-Windows OS"
# fi
# 
if [ "$has_failed" = true ]; then
  echo "Some tests failed. Please check the output above for details."
  exit 1
else
  echo "All tests passed successfully."
fi
