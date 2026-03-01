import os
import sys
import unittest
from unittest.mock import MagicMock, patch

# Add project root to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

# Mock decorators before importing SearchController
def mock_decorator(fn):
    return fn

# We need to mock these before SearchController is imported
mock_debounce_mod = MagicMock()
mock_debounce_mod.debounce = lambda wait: mock_decorator
sys.modules['dt_image_search.tools.dts_debounce'] = mock_debounce_mod

mock_perf_mod = MagicMock()
mock_perf_mod.perffunc = mock_decorator
sys.modules['dt_image_search.tools.dts_perf'] = mock_perf_mod

# Mock PySide6 to avoid issues in headless environment or if not installed
# Mock heavy dependencies and PySide6
class MockModule(MagicMock):
    def __getattr__(self, name):
        return MagicMock()

heavy_modules = [
    'PySide6', 'PySide6.QtCore', 'PySide6.QtGui', 'PySide6.QtWidgets',
    'torch', 'torchvision', 'torchvision.transforms', 'numpy', 'faiss',
    'open_clip', 'hf_xet', 'psutil', 'watchdog', 'watchdog.observers',
    'watchdog.events', 'opentelemetry', 'opentelemetry.trace', 'opentelemetry.sdk',
    'opentelemetry.sdk.resources', 'opentelemetry.sdk.trace', 'opentelemetry.sdk.trace.export',
    'opentelemetry.exporter', 'opentelemetry.exporter.otlp', 'opentelemetry.exporter.otlp.proto',
    'opentelemetry.exporter.otlp.proto.http', 'opentelemetry.exporter.otlp.proto.http.trace_exporter',
    'opentelemetry.exporter.otlp.proto.http.metric_exporter', 'opentelemetry.exporter.otlp.proto.http.log_exporter',
    'opentelemetry.exporter.otlp.proto.http._log_exporter', 'opentelemetry.instrumentation',
    'opentelemetry.context', 'opentelemetry.context.contextvars_context', 'opentelemetry.metrics',
    'opentelemetry.sdk.metrics', 'opentelemetry.sdk.metrics.export', 'opentelemetry._logs',
    'opentelemetry.sdk._logs', 'opentelemetry.sdk._logs.export',
]

for mod in heavy_modules:
    sys.modules[mod] = MockModule()

# Mock internal modules that might cause issues
internal_mocks = [
    'dt_image_search.tools.dts_debounce',
    'dt_image_search.tools.dts_perf',
    'dt_image_search.tools.dts_dispatcher',
    'dt_image_search.telemetry.telemetry_client',
    'dt_image_search.base.status_bar_messenger',
    'dt_image_search.index.dts_index',
    'dt_image_search.view.dts_image_viewer', 'dt_image_search.view.image_navigator',
    'dt_image_search.base.image_list_model',
    'dt_image_search.browse.folder_list_model',
    'dt_image_search.base.FolderTreeModel',
    'dt_image_search.model.dts_db',
    'dt_image_search.model.dts_fs',
    'dt_image_search.bm_context',
]

for mod in internal_mocks:
    sys.modules[mod] = MagicMock()

# Setup specific mocks for decorators
sys.modules['dt_image_search.tools.dts_debounce'].debounce = lambda wait: mock_decorator
sys.modules['dt_image_search.tools.dts_perf'].perffunc = mock_decorator

# Now import SearchController
from dt_image_search.search.SearchController import SearchController
from dt_image_search.model.dts_folder import Folder

class TestSearchController(unittest.TestCase):
    def setUp(self):
        self.mock_ctx = MagicMock()
        # Mock ImageListModel to avoid Qt issues
        with patch('dt_image_search.search.SearchController.ImageListModel') as mock_model_cls:
            self.mock_image_list_model = mock_model_cls.return_value
            self.controller = SearchController(self.mock_ctx)
            # Initialize imageListModel
            self.controller.image_list_model()
            self.controller.is_active = True
            # Manually set _is_active because we might have issues with property setters in mocked classes
            # But SearchController inherits from BaseController which is NOT mocked.
            self.controller.is_active = True

    @patch('dt_image_search.search.SearchController.create_db_conn')
    @patch('dt_image_search.search.SearchController.get_all_folders')
    @patch('dt_image_search.search.SearchController.query_index')
    @patch('dt_image_search.search.SearchController.dispatcher')
    @patch('dt_image_search.search.SearchController.status_bar_messenger')
    @patch('dt_image_search.search.SearchController.log')
    @patch('dt_image_search.search.SearchController.index_path_for_folder')
    @patch('pathlib.Path.exists')
    def test_on_search_query_non_empty(self, mock_exists, mock_index_path, mock_log, mock_status_bar, mock_dispatcher, mock_query_index, mock_get_folders, mock_db_conn):
        # Setup
        mock_exists.return_value = True
        mock_index_path.return_value = "/mock/index/path"
        
        mock_folder = Folder(id="1", path="/mock/folder", status=2, added_at="2023-01-01")
        mock_get_folders.return_value = [mock_folder]
        
        mock_query_index.return_value = [("/mock/image.jpg", 0.9)]
        
        # Mock dispatcher.post to execute immediately
        mock_dispatcher.post.side_effect = lambda f: f()
        
        # Execute
        self.controller.on_search_query("test query")
        
        # Verify
        mock_status_bar.show_status_message.emit.assert_any_call("Searching for: test query")
        mock_query_index.assert_called_once_with(ctx=self.mock_ctx, folder_id="1", index_path="/mock/index/path", query_text="test query")
        self.mock_image_list_model.load_images.assert_called_once_with([("/mock/image.jpg", 0.9)])
        mock_status_bar.show_status_message.emit.assert_any_call("Search completed with 1 results.")

    @patch('dt_image_search.search.SearchController.create_db_conn')
    @patch('dt_image_search.search.SearchController.get_all_folders')
    @patch('dt_image_search.search.SearchController.dispatcher')
    @patch('dt_image_search.search.SearchController.status_bar_messenger')
    @patch('dt_image_search.search.SearchController.log')
    def test_on_search_query_empty(self, mock_log, mock_status_bar, mock_dispatcher, mock_get_folders, mock_db_conn):
        # Setup
        mock_get_folders.return_value = []
        mock_dispatcher.post.side_effect = lambda f: f()
        
        # Execute
        self.controller.on_search_query("")
        
        # Verify
        mock_status_bar.show_status_message.emit.assert_any_call("Searching for: ")
        self.mock_image_list_model.load_images.assert_called_with([])
        mock_status_bar.show_status_message.emit.assert_any_call("Search completed with 0 results.")

    def test_is_active_setter(self):
        # Test that setting is_active to False calls on_detach
        self.controller.is_active = False
        self.mock_image_list_model.on_detach.assert_called_once()

if __name__ == '__main__':
    unittest.main()
