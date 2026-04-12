import unittest
from unittest.mock import MagicMock, patch
import os
import tempfile
import shutil
from pathlib import Path
import sqlite3
import sys
from types import ModuleType

def mock_module(name):
    m = ModuleType(name)
    sys.modules[name] = m
    return m

# Mocking dependencies before importing modules that use them
mock_open_clip = mock_module('open_clip')
mock_open_clip.get_tokenizer = MagicMock()
mock_open_clip.create_model_and_transforms = MagicMock()
mock_faiss = mock_module('faiss')
mock_torch = mock_module('torch')
mock_torch.cuda = MagicMock()
mock_torch.cuda.is_available.return_value = False
mock_torch.inference_mode = MagicMock()
mock_torch.set_grad_enabled = MagicMock()

mock_torchvision = mock_module('torchvision')
mock_torchvision_transforms = mock_module('torchvision.transforms')

mock_numpy = mock_module('numpy')
mock_numpy.float32 = float
mock_numpy.int64 = int
mock_numpy.random = MagicMock()
mock_numpy.array = lambda x, dtype=None: x
mock_numpy.concatenate = lambda x, axis=0: x[0] if x else []

mock_pil = mock_module('PIL')
mock_pil.Image = MagicMock()
mock_pil.ImageFile = MagicMock()
mock_pil_image = mock_module('PIL.Image')

mock_pyside6 = mock_module('PySide6')
mock_pyside6_core = mock_module('PySide6.QtCore')
mock_pyside6_core.QStandardPaths = MagicMock()
mock_pyside6_core.QStandardPaths.writableLocation.return_value = tempfile.gettempdir()
mock_pyside6_core.Signal = MagicMock()
mock_pyside6_core.QObject = MagicMock()
mock_pyside6_gui = mock_module('PySide6.QtGui')
mock_pyside6_widgets = mock_module('PySide6.QtWidgets')

mock_otel = mock_module('opentelemetry')
mock_otel.trace = MagicMock()
mock_otel.metrics = MagicMock()
mock_otel._logs = MagicMock()

mock_otel_context = mock_module('opentelemetry.context')
mock_otel_contextvars = mock_module('opentelemetry.context.contextvars_context')

mock_otel_sdk = mock_module('opentelemetry.sdk')
mock_otel_sdk_resources = mock_module('opentelemetry.sdk.resources')
mock_otel_sdk_resources.Resource = MagicMock()

mock_otel_sdk_trace = mock_module('opentelemetry.sdk.trace')
mock_otel_sdk_trace.TracerProvider = MagicMock()

mock_otel_sdk_trace_export = mock_module('opentelemetry.sdk.trace.export')
mock_otel_sdk_trace_export.ConsoleSpanExporter = MagicMock()
mock_otel_sdk_trace_export.BatchSpanProcessor = MagicMock()

mock_otel_sdk_metrics = mock_module('opentelemetry.sdk.metrics')
mock_otel_sdk_metrics.MeterProvider = MagicMock()
mock_otel_sdk_metrics.Counter = MagicMock()
mock_otel_sdk_metrics.UpDownCounter = MagicMock()
mock_otel_sdk_metrics.Histogram = MagicMock()
mock_otel_sdk_metrics.ObservableCounter = MagicMock()
mock_otel_sdk_metrics.ObservableUpDownCounter = MagicMock()
mock_otel_sdk_metrics.ObservableGauge = MagicMock()
mock_otel_sdk_metrics.PeriodicExportingMetricReader = MagicMock()

mock_otel_sdk_metrics_export = mock_module('opentelemetry.sdk.metrics.export')
mock_otel_sdk_metrics_export.PeriodicExportingMetricReader = MagicMock()
mock_otel_sdk_metrics_export.ConsoleMetricExporter = MagicMock()
mock_otel_sdk_metrics_export.AggregationTemporality = MagicMock()

mock_otel_sdk_logs = mock_module('opentelemetry.sdk._logs')
mock_otel_sdk_logs.LoggerProvider = MagicMock()
mock_otel_sdk_logs.LoggingHandler = MagicMock()

mock_otel_sdk_logs_export = mock_module('opentelemetry.sdk._logs.export')
mock_otel_sdk_logs_export.BatchLogRecordProcessor = MagicMock()

mock_otel_exporter = mock_module('opentelemetry.exporter')
mock_otel_exporter_otlp = mock_module('opentelemetry.exporter.otlp')
mock_otel_exporter_otlp_proto = mock_module('opentelemetry.exporter.otlp.proto')
mock_otel_exporter_otlp_proto_http = mock_module('opentelemetry.exporter.otlp.proto.http')

mock_otel_exporter_otlp_proto_http_trace = mock_module('opentelemetry.exporter.otlp.proto.http.trace_exporter')
mock_otel_exporter_otlp_proto_http_trace.OTLPSpanExporter = MagicMock()

mock_otel_exporter_otlp_proto_http_metric = mock_module('opentelemetry.exporter.otlp.proto.http.metric_exporter')
mock_otel_exporter_otlp_proto_http_metric.OTLPMetricExporter = MagicMock()

mock_otel_exporter_otlp_proto_http_log = mock_module('opentelemetry.exporter.otlp.proto.http._log_exporter')
mock_otel_exporter_otlp_proto_http_log.OTLPLogExporter = MagicMock()

mock_requests = mock_module('requests')
mock_hf_xet = mock_module('hf_xet')
# Mock is_cn to avoid region detection issues
mock_bm_sys = mock_module('dt_image_search.tools.bm_sys')
mock_bm_sys.is_cn = MagicMock(return_value=False)
# Mock status_bar_messenger
mock_status_bar_messenger = MagicMock()
sys.modules['dt_image_search.base.status_bar_messenger'] = MagicMock(status_bar_messenger=mock_status_bar_messenger)

from dt_image_search.bm_context import BMContext
import dt_image_search.model.dts_db as dts_db
import dt_image_search.model.dts_fs as dts_fs_mod
import dt_image_search.index.dts_index as dts_index
from dt_image_search.model.dts_folder import Folder
from dt_image_search.model.dts_file import File

class TestAppFlow(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.app_data_path = Path(self.test_dir) / "app_data"
        self.app_data_path.mkdir(parents=True, exist_ok=True)
        
        # Mock BMContext
        self.ctx = BMContext(
            version=1,
            subfolder="test",
            model_name="ViT-B-32",
            pretrained_model="laion2b_s34b_b79k",
            offline_mode=True,
            model_file_info_url="http://example.com/model.bin"
        )
        
        # Patch get_app_data_path in dts_fs and modules that imported it
        self.patcher_app_data_db = patch.object(dts_db, 'get_app_data_path', return_value=self.app_data_path)
        self.mock_get_app_data_path_db = self.patcher_app_data_db.start()
        
        self.patcher_app_data_index = patch.object(dts_index, 'get_app_data_path', return_value=self.app_data_path)
        self.mock_get_app_data_path_index = self.patcher_app_data_index.start()
        self.patcher_app_data = patch.object(dts_fs_mod, 'get_app_data_path', return_value=self.app_data_path)
        self.mock_get_app_data_path = self.patcher_app_data.start()

        # Mock database schema loading
        self.schema_sql = """
        CREATE TABLE IF NOT EXISTS folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT UNIQUE NOT NULL,
            status INTEGER NOT NULL DEFAULT 0,
            added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL,
            folder_id INTEGER NOT NULL,
            clip_index INTEGER,
            status INTEGER NOT NULL DEFAULT 0,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(folder_id) REFERENCES folders(id)
        );
        CREATE TABLE IF NOT EXISTS app_config (
            key CHAR(128) NOT NULL PRIMARY KEY,
            value TEXT NOT NULL
        ) WITHOUT ROWID;
        """
        self.patcher_schema = patch('importlib.resources.files')
        self.mock_files = self.patcher_schema.start()
        self.mock_files.return_value.joinpath.return_value.read_text.return_value = self.schema_sql

        # Mock events in dts_index
        self.patcher_model_downloaded = patch.object(dts_index, 'model_downloaded_event')
        self.mock_model_downloaded = self.patcher_model_downloaded.start()
        
        self.patcher_model_loaded = patch.object(dts_index, '_model_loaded_event')
        self.mock_model_loaded = self.patcher_model_loaded.start()

        # Mock process pool to run synchronously
        self.patcher_pool = patch.object(dts_index, '_get_process_pool')
        self.mock_get_pool = self.patcher_pool.start()
        self.mock_pool = MagicMock()
        self.mock_get_pool.return_value = self.mock_pool
        
        # Mock model and tokenizer
        self.mock_model = MagicMock()
        self.mock_preprocess = MagicMock()
        self.mock_tokenizer = MagicMock()
        self.patcher_get_model = patch.object(dts_index, '_get_model', return_value=(self.mock_model, self.mock_preprocess, self.mock_tokenizer))
        self.mock_get_model = self.patcher_get_model.start()

        # Mock faiss index
        self.mock_faiss_index = MagicMock()
        self.patcher_get_index = patch.object(dts_index, '_get_index', return_value=self.mock_faiss_index)
        self.mock_get_index = self.patcher_get_index.start()
        
        # Mock faiss.write_index and faiss.read_index
        self.patcher_faiss_write = patch.object(mock_faiss, 'write_index', create=True)
        self.mock_faiss_write = self.patcher_faiss_write.start()
        self.patcher_faiss_read = patch.object(mock_faiss, 'read_index', create=True)
        self.mock_faiss_read = self.patcher_faiss_read.start()

    def tearDown(self):
        self.patcher_app_data_db.stop()
        self.patcher_app_data_index.stop()
        self.patcher_schema.stop()
        self.patcher_model_downloaded.stop()
        self.patcher_model_loaded.stop()
        self.patcher_pool.stop()
        self.patcher_get_model.stop()
        self.patcher_get_index.stop()
        self.patcher_faiss_write.stop()
        self.patcher_faiss_read.stop()
        shutil.rmtree(self.test_dir)

    def test_app_flow(self):
        # 1. Connect to database
        with dts_db.create_db_conn(self.ctx) as conn:
            # 2. Add a folder to the index
            folder_path = "/path/to/images"
            folder = dts_db.insert_folder(conn, folder_path)
            self.assertIsNotNone(folder)
            self.assertEqual(folder.path, folder_path)
            
            # 3. Add some dummy files to the database
            file_paths = [
                f"{folder_path}/image1.jpg",
                f"{folder_path}/image2.jpg",
                f"{folder_path}/image3.jpg"
            ]
            for path in file_paths:
                dts_db.insert_file(conn, path, folder.id)
            
            pending_files = dts_db.get_pending_files_for_folder(conn, folder.id)
            self.assertEqual(len(pending_files), 3)

        # 4. Mock the indexing process
        # Mock process_image_batch_persistent result
        mock_batch_tensor = MagicMock()
        mock_valid_files = pending_files
        mock_deleted_files = []
        mock_invalid_files = []
        
        mock_future = MagicMock()
        mock_future.result.return_value = (mock_batch_tensor, mock_valid_files, mock_deleted_files, mock_invalid_files)
        self.mock_pool.submit.return_value = mock_future
        
        # Mock model.encode_image
        mock_features = MagicMock()
        mock_features.norm.return_value = mock_features
        mock_features.cpu.return_value.numpy.return_value = MagicMock() # np.random.rand(3, 512)
        self.mock_model.encode_image.return_value = mock_features
        
        # 5. Build index
        index_path = dts_index.index_path_for_folder(self.ctx, folder)
        # We need to mock os.path.exists for the index file to avoid create_index_if_needed issues
        with patch('os.path.exists', side_effect=lambda p: True if p == index_path else os.path.exists(p)):
            progress_gen = dts_index.build_index(self.ctx, index_path, folder.id)
            for progress in progress_gen:
                self.assertTrue(progress['batch_result'])
        
        # 6. Verify files are marked as indexed in DB
        with dts_db.create_db_conn(self.ctx) as conn:
            pending_files_after = dts_db.get_pending_files_for_folder(conn, folder.id)
            self.assertEqual(len(pending_files_after), 0)
            
            cursor = conn.execute("SELECT count(*) FROM files WHERE status = 1")
            self.assertEqual(cursor.fetchone()[0], 3)

        # 7. Search for a query
        query_text = "a cat"
        
        # Mock tokenizer and model.encode_text
        mock_tokens = MagicMock()
        mock_open_clip.get_tokenizer.return_value = self.mock_tokenizer
        self.mock_tokenizer.return_value = mock_tokens
        mock_tokens.to.return_value = mock_tokens
        
        mock_text_features = MagicMock()
        mock_text_features.norm.return_value = mock_text_features
        mock_text_features.cpu.return_value.numpy.return_value = MagicMock() # np.random.rand(1, 512)
        self.mock_model.encode_text.return_value = mock_text_features
        
        # Mock faiss search result
        # indices[0] should contain the file ids (which we used as clip_index)
        mock_indices = [[pending_files[0].id, pending_files[1].id]]
        mock_scores = [[0.9, 0.8]]
        self.mock_faiss_index.search.return_value = (mock_scores, mock_indices)
        
        results = dts_index.query_index(self.ctx, folder.id, index_path, query_text)
        
        self.assertEqual(len(results), 2)
        self.assertEqual(results[0][0], pending_files[0].path)
        self.assertEqual(results[1][0], pending_files[1].path)

if __name__ == '__main__':
    unittest.main()
