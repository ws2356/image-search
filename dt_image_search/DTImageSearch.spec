# -*- mode: python ; coding: utf-8 -*-
import os
import sys
from PyInstaller.utils.hooks import collect_data_files, collect_all

sys.path.insert(0, os.path.abspath("."))
datas = collect_data_files("dt_image_search.model")
datas += collect_data_files("open_clip", includes=["bpe_simple_vocab_16e6.txt.gz", "model_configs/ViT-B-32*"])


debugpy_datas, debugpy_binaries, debugpy_hiddenimports = collect_all("debugpy")
datas += debugpy_datas

debugpy_hiddenimports += [
    "xmlrpc",
    "xmlrpc.server",
    "xmlrpc.client",
    "queue",
    "select",
    "selectors",
    "multiprocessing.connection",

a = Analysis(
    ['__main__.py'],
    pathex=[],
    binaries=debugpy_binaries,
    datas=datas,
    hiddenimports=debugpy_hiddenimports,
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
    name='DTImageSearch',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
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
    upx=True,
    upx_exclude=[],
    name='DTImageSearch',
)
app = BUNDLE(
    coll,
    name='DTImageSearch.app',
    icon='dt_image_search/resources/appicon.icns',
    bundle_identifier='vip.wansong.dtimagesearch',
)
