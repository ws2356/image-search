using System;
using System.Diagnostics;
using System.IO;
using FlaUI.Core;
using FlaUI.UIA3;
using Application = FlaUI.Core.Application;

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
            var program = Path.Combine(projectRoot, "dist", "DTImageSearch", "DTImageSearch.exe");

            var startInfo = new ProcessStartInfo
            {
                FileName = program,
                Arguments = "",
                WorkingDirectory = projectRoot,
                // 关键点：对于自动化测试，通常建议设为 false，除非你的程序必须依赖 Shell 启动
                UseShellExecute = false, 
                RedirectStandardError = true, // 开启重定向以便捕获崩溃原因
                RedirectStandardOutput = true
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
            
            if (_process != null)
            {
                try
                {
                    if (!_process.HasExited)
                    {
                        _process.Kill();
                    }
                }
                catch (Exception)
                {
                    // Ignore errors during process cleanup (e.g. process already exited or not associated)
                }
                finally
                {
                    _process.Dispose();
                }
            }
        }
    }
}
