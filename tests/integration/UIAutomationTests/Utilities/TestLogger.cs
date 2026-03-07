using System;
using System.IO;

namespace UIAutomationTests.Utilities
{
    public static class TestLogger
    {
        private static string _logFilePath;

        public static void Initialize(string logDirectory)
        {
            var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
            var fileName = $"integration_test_log_{timestamp}.txt";
            _logFilePath = Path.Combine(logDirectory, fileName);

            // Ensure directory exists
            Directory.CreateDirectory(logDirectory);

            Log("Logger Initialized");
        }

        public static void Log(string message, bool? isPass = null)
        {
            var status = isPass.HasValue ? (isPass.Value ? "[PASS]" : "[FAIL]") : "[INFO]";
            var logEntry = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {status} {message}";

            try
            {
                File.AppendAllText(_logFilePath, logEntry + Environment.NewLine);
                Console.WriteLine(logEntry);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Failed to write to log file: {ex.Message}");
            }
        }
    }
}
