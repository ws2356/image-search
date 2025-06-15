# -*- mode: python ; coding: utf-8 -*-

import os
import sys
from PyInstaller.utils.hooks import collect_data_files, copy_metadata
import sysconfig
import glob


# Find the Python shared library path dynamically
libdir = sysconfig.get_config_var("LIBDIR")
version = sysconfig.get_config_var("VERSION")
libname = f"libpython{version}.dylib"

# Look for the dylib in the expected location
candidate = os.path.join(libdir, libname)
if not os.path.exists(candidate):
    # Fallback: search recursively in libdir
    matches = glob.glob(os.path.join(libdir, "**", libname), recursive=True)
    candidate = matches[0] if matches else None

if candidate is None or not os.path.exists(candidate):
    raise FileNotFoundError(f"Could not locate {libname} in {libdir} or subdirectories")

print(f"✅ Found {libname} at: {candidate}")


# Ensure your package is importable during spec execution
sys.path.insert(0, os.path.abspath("."))

# Collect data files (e.g., your db_schema.sql)
datas = collect_data_files("dt_image_search.model")
# datas += copy_metadata('PySide6')

# Include your project folder in search path
pathex = [os.path.abspath(".")]

#hiddenimports=[
#        'PySide6',
#        'PySide6.QtCore',
#        'PySide6.QtWidgets',
#        'PySide6.QtGui',
#        'PySide6.QtSvg',  # if you use it
#    ]

binaries=[
        (candidate, 'Contents/Frameworks'),
    ]

a = Analysis(
    ['dt_image_search/main.py'],
    pathex=pathex,
    binaries=binaries,
    datas=datas,
    hiddenimports=[],
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
    exclude_binaries=False,
    name='DTImageSearch',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,          # 🚫 no terminal
    mac_bundle=True,        # ✅ generate proper .app bundle
    argv_emulation=True,    # ✅ support drag-and-drop files from Finder
    icon='resources/appicon.icns',  # optional .icns icon (must be real path)
)

#coll = COLLECT(
#    exe,
#    a.binaries,
#    a.datas,
#    strip=False,
#    upx=True,
#    name='DTImageSearch',
#)

app = BUNDLE(
    exe,
    name='DTImageSearch.app',
    icon='resources/appicon.icns',  # optional .icns icon (must be real path)
    bundle_identifier='vip.songwan.dtimagesearch',  # optional
    info_plist=None,  # or path to custom plist
    binaries=binaries
)