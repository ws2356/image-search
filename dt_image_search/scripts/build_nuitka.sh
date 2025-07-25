#!/bin/bash
set -eu

script_path="$0"
if [[ "$script_path" != /* ]]; then
  script_path="$(pwd)/$script_path"
fi
script_dir="$(dirname "$script_path")"
cd "$script_dir/../.."

python -m nuitka \
  --standalone \
  --enable-plugin=pyside6 \
  --windows-icon-from-ico=dt_image_search/resources/icon.ico \
  --windows-company-name="Song Wan" \
  --windows-product-name="DTImageSearch" \
  --windows-file-version="1.0.0" \
  --output-dir=build \
  --output-filename=DTImageSearch \
  --include-package=opentelemetry.context \
  --include-package=opentelemetry.trace \
  --include-package=opentelemetry.metrics \
  --include-package=opentelemetry._logs \
  --include-package=opentelemetry.sdk \
  --include-package=opentelemetry.sdk.metrics \
  --include-package=opentelemetry.sdk._logs \
  --include-package=opentelemetry.exporter.otlp.proto.http.trace_exporter \
  --include-package=opentelemetry.exporter.otlp.proto.http.metric_exporter \
  --include-package=opentelemetry.exporter.otlp.proto.http._log_exporter \
  --include-package=dt_image_search \
  --windows-console-mode=force \
  --jobs=8 \
  --include-package-data=open_clip \
  --include-package-data=dt_image_search \
  dt_image_search/__main__.py
