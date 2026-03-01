import unittest
from unittest.mock import MagicMock, patch
import numpy as np
import os
import sys

# Mocking dependencies before importing the module under test
# This is necessary because dts_index.py has top-level code that might fail if dependencies are missing or if it tries to load models.
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
sys.modules['dt_image_search.telemetry.telemetry_client'] = MagicMock()
mock_perf = MagicMock()
mock_perf.perffunc = lambda x: x
sys.modules['dt_image_search.tools.dts_perf'] = mock_perf

# Now we can import the module
from dt_image_search.index import dts_index
from dt_image_search.bm_context import BMContext

class TestDTSIndex(unittest.TestCase):
    def setUp(self):
        self.ctx = MagicMock(spec=BMContext)
        self.ctx.model_name = "ViT-B-32"
        self.ctx.pretrained_model = "laion2b_s34b_b79k"

    @patch('os.path.exists')
    def test_create_index_if_needed_new(self, mock_exists):
        mock_exists.return_value = False
        index_path = "dummy_path.faiss"
        
        # Reset mock to clear any calls during import
        mock_faiss.IndexFlatIP.reset_mock()
        mock_faiss.IndexIDMap2.reset_mock()
        mock_faiss.write_index.reset_mock()
        
        dts_index.create_index_if_needed(index_path)
        
        mock_faiss.IndexFlatIP.assert_called_once_with(512)
        mock_faiss.IndexIDMap2.assert_called_once()
        mock_faiss.write_index.assert_called_once()

    @patch('os.path.exists')
    def test_create_index_if_needed_exists(self, mock_exists):
        mock_exists.return_value = True
        index_path = "dummy_path.faiss"
        
        mock_faiss.IndexFlatIP.reset_mock()
        
        dts_index.create_index_if_needed(index_path)
        
        mock_faiss.IndexFlatIP.assert_not_called()

    @patch('dt_image_search.index.dts_index._query_internal')
    @patch('dt_image_search.index.dts_index.create_db_conn')
    @patch('dt_image_search.index.dts_index.get_files_by_clip_indices')
    def test_query_index(self, mock_get_files, mock_create_db_conn, mock_query_internal):
        # Setup mocks
        mock_query_internal.return_value = [[1, 0.9], [2, 0.8]]
        mock_conn = MagicMock()
        mock_create_db_conn.return_value.__enter__.return_value = mock_conn
        
        mock_file1 = MagicMock()
        mock_file2 = MagicMock()
        mock_get_files.return_value = [mock_file1, mock_file2]
        
        # Execute
        results = dts_index.query_index(self.ctx, 123, "dummy_path.faiss", "query text")
        
        # Verify
        self.assertEqual(len(results), 2)
        self.assertEqual(results[0][0], mock_file1)
        self.assertEqual(results[0][1], 0.9)
        mock_query_internal.assert_called_once_with("dummy_path.faiss", "query text", dts_index.TOP_K * 5)
        mock_get_files.assert_called_once_with(mock_conn, 123, [1, 2])
    @patch('dt_image_search.index.dts_index._query_internal')
    @patch('dt_image_search.index.dts_index.create_db_conn')
    @patch('dt_image_search.index.dts_index.get_files_by_clip_indices')
    def test_query_index_deduplication(self, mock_get_files, mock_create_db_conn, mock_query_internal):
        # Setup mocks with duplicate IDs
        mock_query_internal.return_value = [[1, 0.9], [1, 0.8], [2, 0.7]]
        mock_conn = MagicMock()
        mock_create_db_conn.return_value.__enter__.return_value = mock_conn
        
        mock_file1 = MagicMock()
        mock_file2 = MagicMock()
        # get_files_by_clip_indices should be called with unique IDs [1, 2]
        mock_get_files.return_value = [mock_file1, mock_file2]
        # Execute
        results = dts_index.query_index(self.ctx, 123, "dummy_path.faiss", "query text")
        # Verify deduplication (only 2 results)
        self.assertEqual(len(results), 2)
        self.assertEqual(results[0][0], mock_file1)
        self.assertEqual(results[1][0], mock_file2)
        mock_get_files.assert_called_once_with(mock_conn, 123, [1, 2])

    @patch('dt_image_search.index.dts_index._get_index')
    @patch('dt_image_search.index.dts_index._get_model')
    def test_query_internal(self, mock_get_model, mock_get_index):
        # Setup mocks
        mock_index = MagicMock()
        mock_get_index.return_value = mock_index
        
        mock_model = MagicMock()
        mock_tokenizer = MagicMock()
        mock_get_model.return_value = (mock_model, None, mock_tokenizer)
        
        mock_tokens = MagicMock()
        mock_tokenizer.return_value.to.return_value = mock_tokens
        
        mock_features = MagicMock()
        mock_model.encode_text.return_value = mock_features
        mock_features.norm.return_value = mock_features
        mock_features.__truediv__.return_value = mock_features
        
        mock_vector = np.array([[0.1, 0.2]])
        mock_features.cpu.return_value.numpy.return_value = mock_vector
        
        mock_index.search.return_value = (np.array([[0.9]]), np.array([[101]]))
        
        # Execute
        results = dts_index._query_internal("dummy_path.faiss", "query text", 5)
        
        # Verify
        self.assertEqual(results, [[101, 0.9]])
        mock_index.search.assert_called_once()
        mock_model.encode_text.assert_called_once_with(mock_tokens)
    @patch('dt_image_search.index.dts_index._get_index')
    @patch('dt_image_search.index.dts_index._get_model')
    def test_query_internal_sorting(self, mock_get_model, mock_get_index):
        # Setup mocks
        mock_index = MagicMock()
        mock_get_index.return_value = mock_index
        
        mock_model = MagicMock()
        mock_tokenizer = MagicMock()
        mock_get_model.return_value = (mock_model, None, mock_tokenizer)
        
        mock_tokens = MagicMock()
        mock_tokenizer.return_value.to.return_value = mock_tokens
        
        mock_features = MagicMock()
        mock_model.encode_text.return_value = mock_features
        mock_features.norm.return_value = mock_features
        mock_features.__truediv__.return_value = mock_features
        
        mock_vector = np.array([[0.1, 0.2]])
        mock_features.cpu.return_value.numpy.return_value = mock_vector
        
        # Return unsorted results to test sorting logic
        mock_index.search.return_value = (np.array([[0.8, 0.9]]), np.array([[102, 101]]))
        
        # Execute
        results = dts_index._query_internal("dummy_path.faiss", "query text", 5)
        
        # Verify sorting (highest score first)
        self.assertEqual(results, [[101, 0.9], [102, 0.8]])

if __name__ == '__main__':
    unittest.main()
