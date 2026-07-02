"""
Pytest configuration for snapshot tests.
Sets up Qt application and snapshot directories.
"""

import os
import sys

import pytest

# Add the project root to Python path
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)


@pytest.fixture(scope="session")
def qapp_instance():
    """Create a single QApplication instance for all snapshot tests."""
    from PySide6.QtWidgets import QApplication

    app = QApplication.instance()
    if app is None:
        app = QApplication([])
    return app


@pytest.fixture
def snapshot_dir():
    """Return the snapshot directory path."""
    return os.path.join(os.path.dirname(__file__), "__Snapshots__")
