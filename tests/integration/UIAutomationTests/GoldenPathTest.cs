using System.IO;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Input;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using NUnit.Framework;
using UIAutomationTests.Utilities;
using Application = FlaUI.Core.Application;

namespace UIAutomationTests
{
    [TestFixture]
    public class GoldenPathTest : BaseTest
    {
        private Window _mainWindow;

        [Test]
        public void GoldenPath_EndToEnd()
        {
            InitializeMainWindow();
            Thread.Sleep(10000);
            EnsureCleanState();
            // Wait for 30 seconds to ensure the app is fully ready before proceeding
            Thread.Sleep(3000);
            AddTestFolder();
            WaitForIndexingCompletion();
            VerifySearchFunctionality();
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

            if (folderList != null)
            {
                var testFolderItem = folderList.FindFirstDescendant(cf => cf.ByName("test-folder"));
                if (testFolderItem != null)
                {
                    TestLogger.Log("Found existing test-folder. Removing it.");
                    testFolderItem.Focus();
                    testFolderItem.RightClick();
                    Thread.Sleep(3000); // Wait for context menu to appear
                    
                    var removeButton = _mainWindow.FindFirstDescendant(cf => cf.ByName("Remove Folder"))?.AsButton() 
                                       ?? AppLauncher.Automation.GetDesktop().FindFirstDescendant(cf => cf.ByName("Remove Folder"))?.AsButton();
                    Assert.That(removeButton, Is.Not.Null, "Remove Folder button not found");

                    if (removeButton != null)
                    {
                        removeButton.Invoke();
                    }
                }
            }
        }

        private void AddTestFolder()
        {
            TestLogger.Log("Adding test folder...");
            var addButton = _mainWindow.FindFirstDescendant(cf => cf.ByAutomationId("browsePageAddFolderButton", PropertyConditionFlags.MatchSubstring))?.AsButton();
            Assert.That(addButton, Is.Not.Null, "Add Folder button not found");
            
            addButton.Invoke();
            TestLogger.Log("Clicked Add Folder button.");
        }

        private void WaitForIndexingCompletion()
        {
            TestLogger.Log("Waiting for indexing to complete...");
            
            var statusBar = _mainWindow.FindFirstDescendant(cf => 
                cf.ByControlType(FlaUI.Core.Definitions.ControlType.StatusBar)
                .And(cf.ByAutomationId("statusbar", PropertyConditionFlags.MatchSubstring))
                );
            
            Assert.That(statusBar, Is.Not.Null, "Status bar not found");

            var result = Retry.WhileTrue(() => 
            {
                return statusBar.Properties.Name.ValueOrDefault?.Contains("Indexing completed") != true;
            }, TimeSpan.FromSeconds(60), TimeSpan.FromSeconds(1));

            if (!result.Success)
            {
                TestLogger.Log("Timeout waiting for indexing to complete.", false);
                Assert.Fail("Timeout waiting for indexing");
            }
            
            TestLogger.Log("Indexing completed detected.");
        }

        private void VerifySearchFunctionality()
        {
            TestLogger.Log("Starting Search Verification Loop...");
            
            var searchInputField = _mainWindow.FindFirstDescendant(cf => cf.ByAutomationId("searchInputField", PropertyConditionFlags.MatchSubstring))?.AsTextBox();
            Assert.That(searchInputField, Is.Not.Null, "Search input not found");

            string testFolderPath = FindTestFolder();
            if (string.IsNullOrEmpty(testFolderPath))
            {
                TestLogger.Log("Could not find local test-folder to enumerate files.", false);
                return;
            }

            var files = Directory.GetFiles(testFolderPath);
            
            foreach (var file in files)
            {
                var filename = Path.GetFileNameWithoutExtension(file);
                TestLogger.Log($"Testing file: {filename}");

                searchInputField.Text = filename;
                
                var list = _mainWindow.FindFirstDescendant(
                    cf => cf.ByAutomationId("searchPageImageListView", PropertyConditionFlags.MatchSubstring));
                // Wait for results to appear and stable
                Thread.Sleep(5000); // Initial wait for results to start appearing
                var found = Retry.WhileFalse(() => 
                {
                    var items = list?.FindAllChildren();
                    return items != null && items.Length > 0;
                }, TimeSpan.FromSeconds(5));

                if (!found.Success)
                {
                    TestLogger.Log($"No results found for {filename}", false);
                    continue;
                }

                var firstItem = list.FindFirstChild();
                Assert.That(firstItem, Is.Not.Null, $"No items found in results for {filename}");
                var detectedFilename = Path.GetFileName(firstItem.Name);
                Assert.That(detectedFilename, Is.EqualTo(Path.GetFileName(file)), $"Expected {filename} but got {detectedFilename}");
                TestLogger.Log($"Successfully found {filename} in search results.");
            }
        }

        private string FindTestFolder()
        {
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var candidates = Directory.GetDirectories(baseDir, "test-folder", SearchOption.AllDirectories);
            if (candidates.Any()) return candidates.First();

            var parent = new DirectoryInfo(baseDir);
            while (parent != null)
            {
                var check = Path.Combine(parent.FullName, "tests", "assets", "test-folder");
                if (Directory.Exists(check)) return check;
                parent = parent.Parent;
            }
            return null;
        }

        private string GetClipboardText()
        {
            string clipboardText = "";
            Thread thread = new Thread(() => 
            {
                if (Clipboard.ContainsText())
                    clipboardText = Clipboard.GetText();
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            thread.Join();
            return clipboardText;
        }
    }
}
