#!/usr/bin/env bash
set -euo pipefail

this_file=$0
if [[ "$this_file" != /* ]]; then
    this_file="$(pwd)/$this_file"
fi
this_dir="$(dirname "$this_file")"
project_root="${this_dir}/../.."

pyside6-uic "$project_root/dt_image_search/view/dts_mainwindow.ui" -o  "$project_root/dt_image_search/view/dts_mainwindow_ui.py"