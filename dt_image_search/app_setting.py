from PySide6.QtCore import QCoreApplication
from dt_image_search.build_flavor import get_build_type

def initialize_app_settings():
    QCoreApplication.setOrganizationName("net.boldman")
    _build_type = get_build_type()
    _app_display_name = "imagesearch-dev" if _build_type == "dev" else "imagesearch"
    QCoreApplication.setApplicationName(_app_display_name)
