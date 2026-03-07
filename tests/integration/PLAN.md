# Integration Testing Plan for dt_image_search

This document outlines the detailed plan to implement and execute the integration tests for the `dt_image_search` application on Windows, adhering to the requirements specified in `AGENTS.md`.

## 1. Goal and Scope
The goal is to perform end-to-end integration testing by simulating actual user flows using the **FlaUI** UI testing framework. These tests are strictly designed for the **Windows** environment.

## 2. Environment & Tech Stack Setup
- **OS Requirement**: Windows ONLY.
- **App Environment**: Python 3.10 (to run the `dt_image_search` target application).
- **Testing Framework**: C# with .NET 8.0 (Latest stable LTS compatible with FlaUI).
- **UI Automation Library**: FlaUI (specifically the `FlaUI.UIA3` package, latest stable version v4.0.0+).
- **Test Runner**: NUnit or xUnit (to be configured in the C# test project).

## 3. Preparation & Prerequisites Verification
The application code already contains necessary testing hooks:
1. **Accessibility Attributes**: UI controls are identified using the `<page_id>_<control_id>` format (e.g., `browse_page_add_folder_button`).
2. **Test Hooks**: Environment variables `UI_TEST=1` and `TEST_FOLDER` are supported to bypass standard OS file selection dialogs and mock hard-to-automate UI components.

## 4. Test Infrastructure Implementation
1. **Create C# Test Project**: Initialize a new .NET test project inside the `tests/integration/` directory (e.g., `tests/integration/UIAutomationTests`).
2. **Add NuGet Packages**: Install `FlaUI.UIA3` and `FlaUI.Core`.
3. **App Launcher Utility**: Write a C# setup method to spawn the Python process (`python -m dt_image_search` or main.py) and inject the required environment variables:
   - `UI_TEST=1`
   - `TEST_FOLDER=<absolute_path_to_project_root>/tests/assets/test-folder`
4. **Logger**: Implement a custom file logger to output assertion results into dynamically named log files (`tests/integration/integration_test_log_{yyyyMMdd_HHmmss}.txt`).

## 5. Test Case 1: Golden Path Execution
The automated script will execute the following sequence:

1. **Initialization**:
   - Start the application with `UI_TEST=1` and `TEST_FOLDER` environment variables.
   - Attach FlaUI to the application window.

2. **Clean State Check**:
   - Locate the folder list in the `BrowseController`.
   - If `test-folder` is already present:
     - Simulate a `Right-Click` on the `test-folder` item.
     - Click the `Remove Folder` context menu item.

3. **Add Test Folder**:
   - Locate and click the `Add Folder` button.
   - *Note: The file selection dialog is automatically bypassed by the app's internal mock logic.*

4. **Await Indexing**:
   - Poll the application's status bar text.
   - Wait until the text matches the pattern `Indexing completed: *`.

5. **Search and Verification Loop**:
   - Programmatically read the contents of `<project root>/tests/assets/test-folder` to get a list of test files.
   - For each file in the test folder:
     1. Extract the filename without the extension.
     2. Locate the Search field, click it, and type the extracted filename.
     3. Wait for the image list in the Search page to populate with results.
     4. `Right-Click` the first result item.
     5. Select `Copy File Path` from the context menu.
     6. Read the clipboard content using C# interop.
     7. **Assert**: Verify that the filename part of the copied path matches the search string.
     8. **Log**: Write the assertion result (Pass/Fail) to the timestamped log file. **Do not fail the entire test suite on a single assertion failure; continue to the next file.**
     9. Send an `Esc` keystroke (or click the `X` clear button) to reset the search field.

6. **Teardown**:
   - Close the application gracefully and clean up the FlaUI automation instances.

## Scripting
- **Bootstrap Bash script**: Add a bash script named `uitest_bootstrap.sh` in folder `dts_image_search/scripts`, which would install all the dependencies including C#, FlaUI, etc.
- **Start Bash script**: Add a bash script named `uitest_start.sh` in folder `dts_image_search/scripts`, which would kick off the ui automation tests.