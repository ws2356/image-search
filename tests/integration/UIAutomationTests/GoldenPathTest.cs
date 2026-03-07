using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows.Forms;
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
            EnsureCleanState();
            AddTestFolder();
            WaitForIndexingCompletion();
            VerifySearchFunctionality();
        }

        private void InitializeMainWindow()
        {
            _mainWindow = AppLauncher.App.GetMainWindow(AppLauncher.Automation);
            Assert.IsNotNull(_mainWindow, "Main Window not found");
            TestLogger.Log("Main window attached.");
        }

        private void EnsureCleanState()
        {
            TestLogger.Log("Checking for existing test-folder...");
            
            var folderList = _mainWindow.FindFirstDescendant(cf => cf.ByAutomationId("browse_page_folder_list"))?.AsListBox();
            
            if (folderList != null)
            {
                var testFolderItem = folderList.Items.FirstOrDefault(i => i.Name.Contains("test-folder"));
                if (testFolderItem != null)
                {
                    TestLogger.Log("Found existing test-folder. Removing it.");
                    testFolderItem.RightClick();
                    
                    var removeButton = _mainWindow.FindFirstDescendant(cf => cf.ByName("Remove Folder"))?.AsButton() 
                                       ?? AppLauncher.Automation.GetDesktop().FindFirstDescendant(cf => cf.ByName("Remove Folder"))?.AsButton();

                    if (removeButton != null)
                    {
                        removeButton.Invoke();
                        TestLogger.Log("Clicked Remove Folder.");
                        Retry.WhileTrue(() => folderList.Items.Any(i => i.Name.Contains("test-folder")), TimeSpan.FromSeconds(2));
                    }
                    else
                    {
                        TestLogger.Log("Could not find Remove Folder button.", false);
                    }
                }
            }
        }

        private void AddTestFolder()
        {
            TestLogger.Log("Adding test folder...");
            var addButton = _mainWindow.FindFirstDescendant(cf => cf.ByAutomationId("browse_page_add_folder_button"))?.AsButton();
            Assert.IsNotNull(addButton, "Add Folder button not found");
            
            addButton.Invoke();
            TestLogger.Log("Clicked Add Folder button.");
        }

        private void WaitForIndexingCompletion()
        {
            TestLogger.Log("Waiting for indexing to complete...");
            
            var statusBar = _mainWindow.FindFirstDescendant(cf => cf.ByControlType(ControlType.StatusBar)) 
                            ?? _mainWindow.FindFirstDescendant(cf => cf.ByAutomationId("status_bar"));
            
            Assert.IsNotNull(statusBar, "Status bar not found");

            var success = Retry.WhileTrue(() => 
            {
                var text = statusBar.Name;
                if (string.IsNullOrEmpty(text))
                {
                    var textElement = statusBar.FindFirstDescendant(cf => cf.ByControlType(ControlType.Text));
                    text = textElement?.Name ?? "";
                }
                
                return text.Contains("Indexing completed");
            }, TimeSpan.FromSeconds(60), TimeSpan.FromMilliseconds(500));

            if (!success)
            {
                TestLogger.Log("Timeout waiting for indexing to complete.", false);
                Assert.Fail("Timeout waiting for indexing");
            }
            
            TestLogger.Log("Indexing completed detected.");
        }

        private void VerifySearchFunctionality()
        {
            TestLogger.Log("Starting Search Verification Loop...");
            
            var searchInput = _mainWindow.FindFirstDescendant(cf => cf.ByAutomationId("search_page_search_input"))?.AsTextBox();
            Assert.IsNotNull(searchInput, "Search input not found");

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

                searchInput.Text = filename;
                
                var list = _mainWindow.FindFirstDescendant(cf => cf.ByAutomationId("search_page_image_list"));
                var found = Retry.WhileTrue(() => 
                {
                    var items = list?.FindAllChildren();
                    return items != null && items.Length > 0;
                }, TimeSpan.FromSeconds(5));

                if (!found)
                {
                    TestLogger.Log($"No results found for {filename}", false);
                    continue;
                }

                var firstItem = list.FindFirstChild();
                firstItem.RightClick();

                var copyButton = AppLauncher.Automation.GetDesktop().FindFirstDescendant(cf => cf.ByName("Copy File Path"))?.AsButton();
                
                if (copyButton != null)
                {
                    copyButton.Invoke();
                    
                    string clipboardText = GetClipboardText();
                    bool match = clipboardText.Contains(filename);
                    TestLogger.Log($"Clipboard: '{clipboardText}', Expected to contain: '{filename}'", match);
                }
                else
                {
                    TestLogger.Log("Copy File Path menu item not found", false);
                }

                Keyboard.Type(VirtualKeyShort.ESCAPE);
                searchInput.Text = "";
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
