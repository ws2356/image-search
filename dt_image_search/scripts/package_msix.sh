#!/usr/bin/env bash
set -eu
script_path="$0"
if [[ "$script_path" != /* ]]; then
  script_path="$(pwd)/$script_path"
fi
script_dir="$(dirname "$script_path")"
cd "$script_dir/../.."

mkdir -p DTImageSearchApp
rm -rf DTImageSearchApp/*

mv "build/__main__.dist" DTImageSearchApp/dt_image_search
cp dt_image_search/resources/AppxManifest.xml DTImageSearchApp/

cp dt_image_search/resources/appicon.iconset/icon_512x512@2x.png DTImageSearchApp/icon.png
