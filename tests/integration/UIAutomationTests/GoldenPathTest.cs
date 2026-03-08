using System.IO;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using NUnit.Framework;
using UIAutomationTests.Utilities;

namespace UIAutomationTests
{
    [TestFixture]
    [NonParallelizable]
    public class GoldenPathTest : BaseTest
    {
        private Window _mainWindow;

        private string? testFolderPath = Environment.GetEnvironmentVariable("TEST_FOLDER");
        private string[] _testFiles = new string[]
        {
            "red.png",
            "yellow.png",
            "green.png",
            "blue.png",
        };

        [Test]
        public void GoldenPath_EndToEnd()
        {
            Assert.That(testFolderPath, Is.Not.Null.And.Not.Empty, "TEST_FOLDER environment variable must be set for the test to run.");
            InitializeMainWindow();
            Thread.Sleep(10000);
            EnsureCleanState();
            Thread.Sleep(3000);
            AddTestFolder();
            WaitForIndexingCompletion("Indexing completed");
            VerifySearchFunctionality();
        }

        [Test]
        public void TestIncrementialIndexing()
        {
            // Wait for the system to be fully ready before starting the test
            // This is a temporary workaround to avoid test failures due to the system not being ready.
            // Otherwise, the right click context menu for removing the test folder may not appear, causing the test to fail.
            Thread.Sleep(30000);
            Assert.That(testFolderPath, Is.Not.Null.And.Not.Empty, "TEST_FOLDER environment variable must be set for the test to run.");
            InitializeMainWindow();
            Thread.Sleep(10000);
            EnsureCleanState();
            Thread.Sleep(3000);
            AddTestFolder();
            WaitForIndexingCompletion("Indexing completed");
            GeneratePureColorImagesForTest();
            WaitForIndexingCompletion("Incremental updating index completed");
            VerifySearchFunctionality();
            RemoveTestFiles();
        }

        private void InitializeMainWindow()
        {
            _mainWindow = AppLauncher.App.GetMainWindow(AppLauncher.Automation);
            Assert.That(_mainWindow, Is.Not.Null, "Main Window not found");
            TestLogger.Log("Main window attached.");
        }

        private void EnsureCleanState()
        {
            TestLogger.Log("Checking for existing test-folder...");

            var browseLeftPanel = _mainWindow.FindFirstDescendant(cf => cf.ByAutomationId("browseLeftPanel", PropertyConditionFlags.MatchSubstring));
            Assert.That(browseLeftPanel, Is.Not.Null, "Browse left panel not found");
            
            var folderList = browseLeftPanel.FindFirstDescendant(
                cf => cf.ByControlType(ControlType.Tree));
            Assert.That(folderList, Is.Not.Null, "Folder list not found in left panel");

            var testFolderItem = folderList.FindFirstDescendant(cf => cf.ByName("test-folder"));
            if (testFolderItem != null)
            {
                TestLogger.Log("Found existing test-folder. Removing it.");
                testFolderItem.Focus();
                testFolderItem.RightClick();
                Thread.Sleep(3000); // Wait for context menu to appear
                
                var removeButton = _mainWindow.FindFirstDescendant(cf => cf.ByName("Remove Folder"))?.AsButton() 
                                    ?? AppLauncher.Automation.GetDesktop().FindFirstDescendant(cf => cf.ByName("Remove Folder"));
                Assert.That(removeButton, Is.Not.Null, "Remove Folder button not found");

                if (removeButton != null)
                {
                    removeButton.Click();
                }
            }
        }

        private void AddTestFolder()
        {
            TestLogger.Log("Adding test folder...");
            var addButton = _mainWindow.FindFirstDescendant(cf => cf.ByAutomationId("browsePageAddFolderButton", PropertyConditionFlags.MatchSubstring))?.AsButton();
            Assert.That(addButton, Is.Not.Null, "Add Folder button not found");
            addButton.Invoke();
        }

        private void WaitForIndexingCompletion(string expectedStatus = "Indexing completed")
        {
            TestLogger.Log("Waiting for indexing to complete...");
            
            var statusBar = _mainWindow.FindFirstDescendant(cf => 
                cf.ByControlType(ControlType.StatusBar)
                .And(cf.ByAutomationId("statusbar", PropertyConditionFlags.MatchSubstring))
                );
            Assert.That(statusBar, Is.Not.Null, "Status bar not found");

            var result = Retry.WhileTrue(() => 
            {
                return statusBar.Properties.Name.ValueOrDefault?.Contains(expectedStatus) != true;
            }, TimeSpan.FromSeconds(60), TimeSpan.FromSeconds(1));

            Assert.That(result.Success, Is.True, $"{expectedStatus} not detected within the expected time.");
            TestLogger.Log("Indexing completed detected.");
        }

        private void VerifySearchFunctionality()
        {
            TestLogger.Log("Starting Search Verification Loop...");
            
            var searchInputField = _mainWindow.FindFirstDescendant(cf => cf.ByAutomationId("searchInputField", PropertyConditionFlags.MatchSubstring))?.AsTextBox();
            Assert.That(searchInputField, Is.Not.Null, "Search input not found");

            var files = Directory.GetFiles(testFolderPath);
            Assert.That(files.Length, Is.GreaterThan(0), "No files found in test folder for search verification.");
            
            foreach (var file in files)
            {
                var filename = Path.GetFileNameWithoutExtension(file);
                TestLogger.Log($"Testing file: {filename}");

                searchInputField.Text = filename;
                // Wait for results to appear and stable
                Thread.Sleep(5000); // Initial wait for results to start appearing
                
                var list = _mainWindow.FindFirstDescendant(
                    cf => cf.ByAutomationId("searchPageImageListView", PropertyConditionFlags.MatchSubstring));
                var found = Retry.WhileFalse(() => 
                {
                    var items = list?.FindAllChildren();
                    return items != null && items.Length > 0;
                }, TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(1));
                Assert.That(found.Success, $"Search results did not appear for {filename} within the expected time.");

                var firstItem = list.FindFirstChild();
                Assert.That(firstItem, Is.Not.Null, $"No items found in results for {filename}");
                var detectedFilename = Path.GetFileName(firstItem.Name);
                Assert.That(detectedFilename, Is.EqualTo(Path.GetFileName(file)), $"Expected {filename} but got {detectedFilename}");
                TestLogger.Log($"Successfully found {filename} in search results.");
            }
        }

        private void GeneratePureColorImagesForTest()
        {
            foreach (var color in _testFiles)
            {
                var filePath = Path.Combine(testFolderPath, color);
                if (File.Exists(filePath))
                {
                    TestLogger.Log($"Test image already exists: {filePath}");
                    continue;
                }

                var bitmap = new Bitmap(100, 100);
                using (var g = Graphics.FromImage(bitmap))
                {
                    switch (color)
                    {
                        case "red.png":
                            g.Clear(Color.Red);
                            break;
                        case "yellow.png":
                            g.Clear(Color.Yellow);
                            break;
                        case "green.png":
                            g.Clear(Color.Green);
                            break;
                        case "blue.png":
                            g.Clear(Color.Blue);
                            break;
                    }
                }
                bitmap.Save(filePath, System.Drawing.Imaging.ImageFormat.Png);
                TestLogger.Log($"Generated test image: {filePath}");
            }
        }

        private void RemoveTestFiles()
        {
            foreach (var color in _testFiles)
            {
                var filePath = Path.Combine(testFolderPath, color);
                if (File.Exists(filePath))
                {
                    try
                    {
                        File.Delete(filePath);
                        TestLogger.Log($"Deleted test image: {filePath}");
                    }
                    catch (Exception ex)
                    {
                        TestLogger.Log($"Failed to delete test image: {filePath}. Error: {ex.Message}");
                    }
                }
            }
        }
    }
}
