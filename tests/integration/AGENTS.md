# Integration tests for dt_image_search
Integration tests should carry on actual user flows by interacting with the app UI using test framework - FlaUI.

## Environment
- Only need to be able to run on Windows
- Use python3.10
- The latest stable version of FlaUI (@agents, determine this)
- C#: latest stable version compatible with FlaUI (@agents, determine this)

## Prerequisite code changes for UI testing
1. [√] For all the UI controls in this app, add Accessibility attributes (if not already there) for ease of locating UI elements during UI testing. The format of the value of accessibility attributes is `<page_id>_<control_id>`. `<page_id>` and `<control_id>` can be transformed from the logic name of page or control, e.g. 'browse_page', 'add_folder_button'. Notice that snake case is used.
2. [√] Add custom logic to skip file selecting when `Add Folder` button is clicked - when `UI_TEST=1` and `TEST_FOLDER` are passed in as environments, skip the File selecting dialog when `Add Folder` is clicked, instead use the `TEST_FOLDER` variable directly to continue the flow.

## For all cases
1. Pass in an environment variable `UI_TEST=1` for mocking parts of the UI flow that are hard to implement.

## Case 1 - Golden Path
1. Pass in environment variable `TEST_FOLDER=<project root>/tests/assets/test-folder` so we can skip the 'File Selecting' part and use that `test-folder` for testing.
2. If the BrowseController's folder list already contains an item `test-folder`, then `right-click` that item to open the context menu and select the `Remove Folder` button to remove it first.
3. Click the `Add Folder` button in the BrowseController page to add a folder.
4. Wait for the status bar to show a message `Indexing completed: xxxx` which means the contents of the folder has been indexed completed.
5. Click the search field and then type one name (without file suffix) of the files in the `test-folder` directory.
6. Wait for the search results to appear in the image list of the Search page.
7. Right-click the first item in the search results and then select `Copy File Path`
8. Assert that the filename part (last path segment without file suffix) of the string in the system paste board is equal to the search string that was typed in the search field. The assert result should be recorded in a log file in `tests/integration` folder. Auto rotate the log file by date and time of test. If one test failed, continue to the rest of the steps instead of exiting immediately.
9. Send a `Esc` key or click the `X` button in the search field to exit from search mode
10. Repeat steps 5~9 for each file in the `test-folder`.
