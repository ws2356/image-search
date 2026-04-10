from dt_image_search.mobile.mobile_pairing_session import MobilePairingSessionDraft, MobilePlatform, MobileSourceType

__all__ = [
    "MobileFolderCoordinator",
    "MobilePairingSessionDraft",
    "MobilePlatform",
    "MobileSourceType",
]


def __getattr__(name: str):
    if name == "MobileFolderCoordinator":
        from dt_image_search.mobile.mobile_folder_controller import MobileFolderCoordinator

        return MobileFolderCoordinator
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
