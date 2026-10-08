# Frozen-build compatibility shim between transformers (>=4.57) and PyInstaller.
#
# Why: transformers' `utils/auto_docstring` derives model names from the module
# source path and assumes `.../<x>/models/<file>` depth. In a PyInstaller bundle
# modules expose short paths (e.g. "transformers/modeling_layers.py"), so the
# unconditional `path.split(os.path.sep)[-3]` raises IndexError while the
# XLM-Roberta text model is being imported. Shimming the depth check to return
# the documented "no model name" outcome (None) keeps the model load working in
# packaged builds; unpackaged runs keep stock behavior.
# Author: ws2356, 2026-10-09
import inspect
import os
import sys


def is_transformers_models_module_path(path: str | None) -> bool:
    """True when obj's source path follows `.../<x>/models/<file>` depth."""
    if path is None:
        return False
    parts = path.split(os.path.sep)
    return len(parts) >= 3 and parts[-3] == "models"


def install_transformers_pyinstaller_compat() -> None:
    """Install the shim once, before the first torch/open_clip import."""
    if not getattr(sys, "frozen", False):
        return
    # import_module: `from transformers.utils import auto_docstring` resolves to
    # the re-exported decorator function, not the submodule, in transformers 4.57.
    import importlib

    auto_docstring = importlib.import_module("transformers.utils.auto_docstring")

    if getattr(auto_docstring.get_model_name, "_frozen_compat_installed", False):
        return

    _original_get_model_name = auto_docstring.get_model_name

    def get_model_name_frozen_compat(obj):
        if not is_transformers_models_module_path(inspect.getsourcefile(obj)):
            return None
        return _original_get_model_name(obj)

    get_model_name_frozen_compat._frozen_compat_installed = True
    auto_docstring.get_model_name = get_model_name_frozen_compat

