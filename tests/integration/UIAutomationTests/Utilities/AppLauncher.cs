using System;
using System.Diagnostics;
using System.IO;
using FlaUI.Core;
using FlaUI.UIA3;

namespace UIAutomationTests.Utilities
{
    public class AppLauncher : IDisposable
    {
        public Application App { get; private set; }
        public AutomationBase Automation { get; private set; }
        private Process _process;

        public void Launch()
        {
            var projectRoot = FindProjectRoot();
            var pythonPath = "python";

            var startInfo = new ProcessStartInfo
            {
                FileName = pythonPath,
                Arguments = "-m dt_image_search",
                WorkingDirectory = projectRoot,
                UseShellExecute = false
            };

            startInfo.EnvironmentVariables["UI_TEST"] = "1";
            var testFolder = Path.Combine(projectRoot, "tests", "assets", "test-folder");
            startInfo.EnvironmentVariables["TEST_FOLDER"] = testFolder;

            try
            {
                _process = Process.Start(startInfo);
                App = Application.Attach(_process);
                Automation = new UIA3Automation();
            }
            catch (Exception ex)
            {
                throw new Exception($"Failed to launch application. Root: {projectRoot}, TestFolder: {testFolder}. Error: {ex.Message}", ex);
            }
        }

        private string FindProjectRoot()
        {
            var currentDir = AppDomain.CurrentDomain.BaseDirectory;
            var directory = new DirectoryInfo(currentDir);

            while (directory != null)
            {
                if (Directory.Exists(Path.Combine(directory.FullName, "dt_image_search")) && 
                    File.Exists(Path.Combine(directory.FullName, "README.md")))
                {
                    return directory.FullName;
                }
                directory = directory.Parent;
            }

            throw new DirectoryNotFoundException("Could not find project root directory.");
        }

        public void Dispose()
        {
            Automation?.Dispose();
            App?.Close();
            
            if (_process != null && !_process.HasExited)
            {
                _process.Kill();
                _process.Dispose();
            }
        }
    }
}
