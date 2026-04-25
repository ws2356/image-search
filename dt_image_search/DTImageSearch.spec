# -*- mode: python ; coding: utf-8 -*-
import os
import plistlib
import sys
import tempfile
from pathlib import Path
from PyInstaller.utils.hooks import collect_data_files, collect_all, copy_metadata

sys.path.insert(0, os.path.abspath("."))
datas = collect_data_files("dt_image_search.model")
datas += collect_data_files("dt_image_search", includes=["resources/*.msi", "resources/*.inf", "resources/*.cat", "resources/*.sys", "resources/*.dll", "resources/ios_bitten_apple_gray.png"])
datas += collect_data_files("open_clip", includes=["bpe_simple_vocab_16e6.txt.gz", "model_configs/ViT-B-32*", "model_configs/xlm-roberta-base-ViT-B-32*"])
datas += copy_metadata('hf_xet')
heif_datas, heif_binaries, heif_hiddenimports = collect_all("pillow_heif")
datas += heif_datas
pmd_datas, pmd_binaries, pmd_hiddenimports = collect_all("pymobiledevice3")
datas += pmd_datas

build_type = os.environ.get("DTIS_BUILD_TYPE", "prod").strip().lower()
if build_type not in {"prod", "dev"}:
    raise ValueError(f"Unsupported DTIS_BUILD_TYPE: {build_type!r}. Expected 'prod' or 'dev'.")
app_name = "AuSearch" if build_type == "prod" else f"AuSearch-{build_type}"
bundle_identifier = "vip.wansong.dtimagesearch" if build_type == "prod" else f"vip.wansong.dtimagesearch.{build_type}"
build_vars_path = Path(tempfile.gettempdir()) / f"dtis_build_vars_{build_type}"
build_vars_path.write_text(f"build_type={build_type}\n", encoding="utf-8")
datas += [(str(build_vars_path), "dt_image_search/resources")]

# UPX is disabled on macOS: UPX modifies Mach-O headers in a way that breaks
# code signatures and notarization.  Enable it only on non-macOS platforms.
upx_enabled = sys.platform != "darwin"

a = Analysis(
    ['__main__.py'],
    pathex=[],
    binaries=heif_binaries + pmd_binaries,
    datas=datas,
    hiddenimports=[
        'hf_xet',
        *heif_hiddenimports,
        *pmd_hiddenimports,
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
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
