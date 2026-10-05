# Unit tests for the Qt-free search orchestration service.
# Heavy deps (torch/faiss/open_clip/PySide6...) are stubbed the same way as
# tests/unit/test_dts_index.py so dts_index can be imported.
import sys
from unittest.mock import MagicMock

noop_decorator = lambda f: f

mock_faiss = MagicMock()
mock_open_clip = MagicMock()
mock_torch = MagicMock()

sys.modules['faiss'] = mock_faiss
sys.modules['open_clip'] = mock_open_clip
sys.modules['torch'] = mock_torch
sys.modules['torchvision'] = MagicMock()
sys.modules['torchvision.transforms'] = MagicMock()
sys.modules['hf_xet'] = MagicMock()
sys.modules['PySide6'] = MagicMock()
sys.modules['PySide6.QtCore'] = MagicMock()
sys.modules['PySide6.QtWidgets'] = MagicMock()
sys.modules['PySide6.QtGui'] = MagicMock()
sys.modules['requests'] = MagicMock()
sys.modules['psutil'] = MagicMock()
sys.modules['watchdog'] = MagicMock()
sys.modules['watchdog.observers'] = MagicMock()
sys.modules['watchdog.events'] = MagicMock()
sys.modules['opentelemetry'] = MagicMock()
sys.modules['opentelemetry.trace'] = MagicMock()
sys.modules['opentelemetry.sdk'] = MagicMock()
sys.modules['opentelemetry.sdk.trace'] = MagicMock()
sys.modules['opentelemetry.sdk.trace.export'] = MagicMock()
sys.modules['opentelemetry.exporter.otlp.proto.http.trace_exporter'] = MagicMock()
sys.modules['opentelemetry.sdk.resources'] = MagicMock()
sys.modules['opentelemetry.metrics'] = MagicMock()
sys.modules['opentelemetry.sdk.metrics'] = MagicMock()
sys.modules['opentelemetry.sdk.metrics.export'] = MagicMock()
sys.modules['opentelemetry.exporter.otlp.proto.http.metric_exporter'] = MagicMock()
sys.modules['opentelemetry._logs'] = MagicMock()
sys.modules['opentelemetry.sdk._logs'] = MagicMock()
sys.modules['opentelemetry.sdk._logs.export'] = MagicMock()
sys.modules['opentelemetry.exporter.otlp.proto.http._log_exporter'] = MagicMock()
sys.modules['opentelemetry.instrumentation'] = MagicMock()
sys.modules['opentelemetry.context'] = MagicMock()
sys.modules['opentelemetry.context.contextvars_context'] = MagicMock()
sys.modules['PIL'] = MagicMock()
sys.modules['PIL.Image'] = MagicMock()
sys.modules['PIL.ImageFile'] = MagicMock()
sys.modules['pc_common.telemetry.telemetry_client'] = MagicMock()
mock_perf = MagicMock()
mock_perf.perffunc = noop_decorator
sys.modules['dt_image_search.tools.dts_perf'] = mock_perf
sys.modules['pc_common.telemetry.telemetry_client'].with_trace = lambda _: noop_decorator

import unittest
from unittest.mock import MagicMock, patch

from dt_image_search.model.dts_folder import Folder
from dt_image_search.search.search_service import search_folders, ModelNotReadyError

SERVICE = 'dt_image_search.search.search_service'


def _folder(fid, path):
    return Folder(id=fid, path=path, status=2, added_at="2026-01-01T00:00:00")


def _folders_ctx(*folders):
    conn = MagicMock()
    with patch(f'{SERVICE}.create_db_conn', return_value=conn), \
         patch(f'{SERVICE}.get_all_folders', return_value=list(folders)):
        yield conn


class TestSearchFolders(unittest.TestCase):
    @patch(f'{SERVICE}.Path', MagicMock())
    @patch(f'{SERVICE}.get_model_state', return_value='ready')
    def test_merges_results_across_folders_desc_by_score(self, _mock_state):
        f1, f2 = _folder("1", "/a"), _folder("2", "/b")
        conn = MagicMock()
        with patch(f'{SERVICE}.create_db_conn', return_value=conn), \
             patch(f'{SERVICE}.get_all_folders', return_value=[f1, f2]), \
             patch(f'{SERVICE}.index_path_for_folder', side_effect=lambda folder: f"{folder.path}.faiss"), \
             patch(f'{SERVICE}.query_index', side_effect=[
                 [(MagicMock(id="f1"), 0.5), (MagicMock(id="f2"), 0.9)],
                 [(MagicMock(id="f3"), 0.7)],
             ]):
            results = search_folders(ctx=MagicMock(), query="cat")

        self.assertEqual([r[0].id for r in results], ["f2", "f3", "f1"])
        self.assertEqual([r[1] for r in results], [0.9, 0.7, 0.5])

    @patch(f'{SERVICE}.Path', MagicMock())
    @patch(f'{SERVICE}.get_model_state', return_value='ready')
    def test_truncates_to_top_k(self, _mock_state):
        f1 = _folder("1", "/a")
        conn = MagicMock()
        items = [(MagicMock(id=f"f{i}"), float(i)) for i in range(150)]
        with patch(f'{SERVICE}.create_db_conn', return_value=conn), \
             patch(f'{SERVICE}.get_all_folders', return_value=[f1]), \
             patch(f'{SERVICE}.index_path_for_folder', return_value="/a.faiss"), \
             patch(f'{SERVICE}.query_index', return_value=items), \
             patch(f'{SERVICE}.TOP_K', 100):
            results = search_folders(ctx=MagicMock(), query="cat")

        self.assertEqual(len(results), 100)
        self.assertEqual(results[0][1], 149.0)
        self.assertEqual(results[-1][1], 50.0)

    @patch(f'{SERVICE}.Path', MagicMock())
    @patch(f'{SERVICE}.get_model_state', return_value='ready')
    def test_no_folders_returns_empty(self, _mock_state):
        conn = MagicMock()
        with patch(f'{SERVICE}.create_db_conn', return_value=conn), \
             patch(f'{SERVICE}.get_all_folders', return_value=[]):
            results = search_folders(ctx=MagicMock(), query="cat")

        self.assertEqual(results, [])

    @patch(f'{SERVICE}.get_model_state', return_value='loading')
    def test_model_loading_raises_model_not_ready(self, _mock_state):
        with patch(f'{SERVICE}.create_db_conn', MagicMock()):
            with self.assertRaises(ModelNotReadyError) as cm:
                search_folders(ctx=MagicMock(), query="cat")

        self.assertEqual(cm.exception.state, 'loading')

    @patch(f'{SERVICE}.get_model_state', return_value='failed')
    def test_model_failed_raises_model_not_ready(self, _mock_state):
        with patch(f'{SERVICE}.create_db_conn', MagicMock()):
            with self.assertRaises(ModelNotReadyError) as cm:
                search_folders(ctx=MagicMock(), query="cat")

        self.assertEqual(cm.exception.state, 'failed')


if __name__ == '__main__':
    unittest.main()
