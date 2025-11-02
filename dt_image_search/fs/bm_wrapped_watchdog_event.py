from watchdog.events import FileSystemEvent

class WrappedWatchdogEvent:
    def __init__(self, event: FileSystemEvent):
        self.event = event
    
    @property
    def event_type(self) -> str:
        return self.event.event_type

    @property
    def src_path(self) -> str:
        from dt_image_search.tools.dts_util import back_slash_to_forward_slash
        return back_slash_to_forward_slash(self.event.src_path)

    @property
    def dest_path(self) -> str:
        from dt_image_search.tools.dts_util import back_slash_to_forward_slash
        return back_slash_to_forward_slash(self.event.dest_path) if hasattr(self.event, 'dest_path') else ''

    @property
    def is_directory(self) -> bool:
        return self.event.is_directory