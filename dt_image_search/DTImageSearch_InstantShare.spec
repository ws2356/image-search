# -*- mode: python ; coding: utf-8 -*-
import json
import os
import plistlib
import sys
import tempfile
from pathlib import Path
from PyInstaller.utils.hooks import collect_data_files, collect_all, copy_metadata

sys.path.insert(0, os.path.abspath("."))


# 2. 放弃 collect_data_files，改用手动、精准的元组配对数据收集
# 定义好源资源的根路径
src_resources_dir = Path("resources")

datas = [
    # 明确复制图标和必备文件，且明确指定在包内的存放路径
    (str(src_resources_dir / "net.boldman.ausearch.instantshare.plist"), ".")
]

if sys.platform == "win32":
    platform_resource_includes = [
        "*.msi",
        "*.inf",
        "*.cat",
        "*.sys",
        "*.dll",
    ]
    datas += collect_data_files("dt_image_search.resources", includes=platform_resource_includes)

build_type = os.environ.get("DTIS_BUILD_TYPE", "prod").strip().lower()
if build_type not in {"prod", "dev"}:
    raise ValueError(f"Unsupported DTIS_BUILD_TYPE: {build_type!r}. Expected 'prod' or 'dev'.")
revision = os.environ.get("DTIS_REVISION", "").strip()
app_name = "SnapGet" if build_type == "prod" else f"SnapGet-{build_type}"
bundle_identifier = "vip.wansong.dtimagesearch.instantshare" if build_type == "prod" else f"vip.wansong.dtimagesearch.instantshare.{build_type}"
build_vars_dir = Path(tempfile.mkdtemp(prefix=f"dtis_build_vars_{build_type}"))
build_vars_path = build_vars_dir / "build_vars"
build_vars_path.write_text(
    json.dumps({"build_type": build_type, "revision": revision}),
    encoding="utf-8",
)
datas += [(str(build_vars_path), "dt_image_search/resources")]

# UPX is disabled on macOS: UPX modifies Mach-O headers in a way that breaks
# code signatures and notarization.  Enable it only on non-macOS platforms.
upx_enabled = sys.platform != "darwin"
excludes = ["torchvision", "torch", "transformers", "faiss-cpu", "tensorflow", "hf-get", "huggingface_hub", "pymobiledevice3"]
if sys.platform == "darwin":
    excludes += [
        "IPython",
        "jedi",
    ]

a = Analysis(
    ['scripts/instant_share_agent_main.py'],
    pathex=[],
    datas=datas,
    hiddenimports=[
        'AppKit',
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
    icon='resources/instantshare.icns',
    bundle_identifier=bundle_identifier,
    info_plist=plistlib.loads(
        Path("dt_image_search/resources/AppInfoInstantShare.plist").read_bytes()
    ),
)
