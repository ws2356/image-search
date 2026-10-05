# Unit tests for the shared indexing pipeline bootstrap/cleanup sequence.
# Heavy deps stubbed so dt_image_search.index.dts_index etc. import cheaply.
import sys
import unittest
from unittest.mock import MagicMock

noop_decorator = lambda f: f

sys.modules['faiss'] = MagicMock()
sys.modules['open_clip'] = MagicMock()
sys.modules['torch'] = MagicMock()
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

from dt_image_search import app_bootstrap

TARGETS = [
    ('dt_image_search.index.dts_model_downloader', 'init', 'model_downloader_init'),
    ('dt_image_search.index.dts_index', 'init', 'index_init'),
    ('dt_image_search.index.incremental_index_worker', 'init_incremental_index_workers', 'inc_init'),
    ('dt_image_search.index.index_worker', 'init_index_workers', 'idx_init'),
    ('dt_image_search.fs.bm_fs_monitor', 'start_watch', 'start_watch'),
    ('dt_image_search.fs.bm_fs_monitor', 'stop_watch', 'stop_watch'),
    ('dt_image_search.index.incremental_index_worker', 'deinit_incremental_index_workers', 'inc_deinit'),
    ('dt_image_search.index.index_worker', 'deinit_index_workers', 'idx_deinit'),
]


class TestInitIndexingPipeline(unittest.TestCase):
    def test_init_sequence_in_legacy_order(self):
        calls = []
        patches = []
        for module, attr, tag in TARGETS:
            p = patch(f'{module}.{attr}', side_effect=lambda *a, tag=tag: calls.append(tag))
            p.start()
            patches.append(p)

        try:
            app_bootstrap.init_indexing_pipeline(ctx=MagicMock())
        finally:
            for p in patches:
                p.stop()

        self.assertEqual(calls, ['model_downloader_init', 'index_init', 'inc_init', 'idx_init', 'start_watch'])

    def test_skip_model_init_skips_both_model_calls(self):
        calls = []
        patches = []
        for module, attr, tag in TARGETS:
            p = patch(f'{module}.{attr}', side_effect=lambda *a, tag=tag: calls.append(tag))
            p.start()
            patches.append(p)

        try:
            app_bootstrap.init_indexing_pipeline(ctx=MagicMock(), skip_model_init=True)
        finally:
            for p in patches:
                p.stop()

        self.assertEqual(calls, ['inc_init', 'idx_init', 'start_watch'])

    def test_deinit_sequence_reversed(self):
        calls = []
        patches = []
        for module, attr, tag in TARGETS:
            p = patch(f'{module}.{attr}', side_effect=lambda *a, tag=tag: calls.append(tag))
            p.start()
            patches.append(p)

        try:
            app_bootstrap.deinit_indexing_pipeline()
        finally:
            for p in patches:
                p.stop()

        self.assertEqual(calls, ['stop_watch', 'inc_deinit', 'idx_deinit'])


if __name__ == "__main__":
    unittest.main()
