import logging
from PySide6.QtCore import QCoreApplication, QStandardPaths
from dt_image_search.build_flavor import get_build_type

def initialize_app_settings(app_name: str):

    QCoreApplication.setOrganizationName("net.boldman")
    _build_type = get_build_type()
    _app_display_name = f"{app_name}-dev" if _build_type == "dev" else app_name
    QCoreApplication.setApplicationName(_app_display_name)
