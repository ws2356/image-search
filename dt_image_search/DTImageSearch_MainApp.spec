# -*- mode: python ; coding: utf-8 -*-
import json
import os
import plistlib
import sys
import tempfile
from pathlib import Path
from PyInstaller.utils.hooks import collect_data_files, collect_all, copy_metadata

sys.path.insert(0, os.path.abspath("."))
datas = collect_data_files("dt_image_search.model")
platform_resource_includes = [
    "resources/ios_bitten_apple_gray.png",
    "resources/icon.png",
    "resources/appicon.icns",
]
if sys.platform == "win32":
    platform_resource_includes += [
        "resources/*.msi",
        "resources/*.inf",
        "resources/*.cat",
        "resources/*.sys",
        "resources/*.dll",
    ]
datas += collect_data_files("dt_image_search", includes=platform_resource_includes)
datas += collect_data_files("open_clip", includes=["bpe_simple_vocab_16e6.txt.gz", "model_configs/ViT-B-32*", "model_configs/xlm-roberta-base-ViT-B-32*"])
datas += copy_metadata('hf_xet')
heif_datas, heif_binaries, heif_hiddenimports = collect_all("pillow_heif")
datas += heif_datas

build_type = os.environ.get("DTIS_BUILD_TYPE", "prod").strip().lower()
if build_type not in {"prod", "dev"}:
    raise ValueError(f"Unsupported DTIS_BUILD_TYPE: {build_type!r}. Expected 'prod' or 'dev'.")
revision = os.environ.get("DTIS_REVISION", "").strip()
app_name = "AuSearch" if build_type == "prod" else f"AuSearch-{build_type}"
bundle_identifier = "vip.wansong.dtimagesearch" if build_type == "prod" else f"vip.wansong.dtimagesearch.{build_type}"
build_vars_dir = Path(tempfile.mkdtemp(prefix=f"dtis_build_vars_{build_type}"))
build_vars_path = build_vars_dir / "build_vars"
build_vars_path.write_text(
    json.dumps({"build_type": build_type, "revision": revision}),
    encoding="utf-8",
)
datas += [(str(build_vars_path), "dt_image_search/resources")]

upx_enabled = sys.platform != "darwin"
excludes = []
if sys.platform == "darwin":
    excludes += [
        "IPython",
        "jedi",
        "timm",
    ]

a = Analysis(
    ['__main__.py'],
    pathex=[],
    binaries=heif_binaries,
    datas=datas,
    hiddenimports=[
        'hf_xet',
        'pymobiledevice3.exceptions',
        'pymobiledevice3.usbmux',
        'AppKit',
        *heif_hiddenimports,
        'SystemConfiguration',
        'CFNetwork',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=excludes,
    noarchive=False,
    optimize=1,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name=app_name,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=upx_enabled,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=upx_enabled,
    upx_exclude=[],
    name=app_name,
)
app = BUNDLE(
    coll,
    name=f"{app_name}.app",
    icon='resources/appicon.icns',
    bundle_identifier=bundle_identifier,
    info_plist=plistlib.loads(
        Path("dt_image_search/resources/AppInfo.plist").read_bytes()
    ),
)
