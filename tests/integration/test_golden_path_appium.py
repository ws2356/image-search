import unittest
import os
import subprocess
import time
import pyperclip # Need to install this or use Appium clipboard
from appium import webdriver
from appium.options.mac import Mac2Options
from appium.webdriver.common.appiumby import AppiumBy
import selenium
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver import ActionChains

class TestGoldenPathAppium(unittest.TestCase):
    def setUp(self):
        self.test_folder = os.path.abspath("tests/assets/test-folder")
        # Ensure test folder exists with dummy image (reuse from previous test logic if needed)
        if not os.path.exists(self.test_folder):
            os.makedirs(self.test_folder)
        
        # Create dummy image if missing (since we are testing end-to-end)
        dummy_path = os.path.join(self.test_folder, "test_image.jpg")
        if not os.path.exists(dummy_path):
            from PIL import Image
            img = Image.new('RGB', (100, 100), color = 'red')
            img.save(dummy_path)

        # Kill app if running to ensure fresh launch with new environment variables
        os.system("pkill -f DTImageSearch")
        
        app_path = os.path.abspath("dist/DTImageSearch.app")
        
        options = Mac2Options()
        options.bundle_id = "vip.wansong.dtimagesearch" # As defined in spec
        options.app = app_path
        options.system_port = 10100

        options.environment = {
            "UI_TEST": "1",
            "TEST_FOLDER": self.test_folder,
            "HF_HUB_OFFLINE": "1" # Use cached model
        }
        
        print("Connecting to Appium...")
        self.driver = webdriver.Remote("http://127.0.0.1:4723", options=options)
        print("App launched!")

    def tearDown(self):
        if hasattr(self, 'driver'):
            self.driver.quit()

    def test_golden_path(self):
        driver = self.driver
        
        # Helper to find element by accessibility id
        def find_access_id(aid):
            return WebDriverWait(driver, 10).until(
                EC.presence_of_element_located((AppiumBy.ACCESSIBILITY_ID, aid))
            )

        def wait_for_status_message_contains(text, timeout=100):
            start_time = time.time()
            while time.time() - start_time < timeout:
                try:
                    els = driver.find_elements(AppiumBy.IOS_PREDICATE, f"title CONTAINS '{text}'")
                    if els:
                        return True
                except Exception as e:
                    print(f"Error occurred while waiting for status message: {e}")
                time.sleep(10)
            return False

        # find a widge with title 'test-folder' that is a child of a widge with identifier "browse_page_folder_tree_view"
        folder_tree = find_access_id("browse_page_folder_tree_view")
        try:
            test_folder = folder_tree.find_element(AppiumBy.ACCESSIBILITY_ID, "test-folder")
            if not (not test_folder):
                # right click it and select "Remove Folder" item in the context menu to ensure it's not there before we add it
                actions = ActionChains(driver)
                actions.move_to_element(test_folder)
                actions.context_click()
                actions.perform()
                time.sleep(3)
                remove_menu = driver.find_element(AppiumBy.ACCESSIBILITY_ID, "Remove Folder")
                if remove_menu:
                    # Move to the menu item before clicking to avoid "Element is not interactable" error
                    actions = ActionChains(driver)
                    actions.move_to_element(remove_menu).click().perform()
                    time.sleep(3)
        except selenium.common.exceptions.NoSuchElementException as e:
            print("Test folder not found in tree, which is expected if it's not added yet.")

        print("Step 1: Add Folder")
        add_btn = find_access_id("browse_page_add_folder_button")
        add_btn.click()
        
        print("Step 2: Wait for Indexing")
        if not wait_for_status_message_contains("Indexing completed", timeout=600):
            raise TimeoutError("Indexing completion message not found in status bar within timeout")
            
        print("Step 3: Search")
        search_input = find_access_id("browse_page_search_input")
        search_input.send_keys("red")
        
        print("Step 4: Check Results")
        # Wait for result list to populate
        # The list is "search_page_image_list_view"
        # We want to check if it has children (cells)
        time.sleep(5) # Wait for search
        
        # Access the list
        result_list = find_access_id("search_page_image_list_view")
        # Get children?
        # In Mac2Driver, list items are usually children
        # We can try to click the first child
        
        # Let's assume the first item is clickable.
        # We need to Right Click.
        # Actions API
        
        # Find the first item (heuristic: it's inside the list)
        # Or just right click the center of the list if items fill it?
        # Better: find children of list
        # items = result_list.find_elements(AppiumBy.XPATH, "//*") # Might be slow
        
        # Attempt to click relative to list top-left
        actions = ActionChains(driver)
        actions.move_to_element(result_list)
        # Move a bit inside (e.g. 20, 20)
        actions.move_by_offset(20, 20)
        actions.context_click()
        actions.perform()
        print("Right clicked")
        
        time.sleep(1)
        
        print("Step 5: Select 'Copy File Path'")
        # Context menu should appear. It's usually a new window or overlay.
        # Find element named "Copy File Path"
        copy_menu = driver.find_element(AppiumBy.ACCESSIBILITY_ID, "Copy File Path") # Assuming menu item has name/title
        # If not accessibility id, try name
        if not copy_menu:
             copy_menu = driver.find_element(AppiumBy.NAME, "Copy File Path")
             
        copy_menu.click()
        
        print("Step 6: Verify Clipboard")
        # We need to read clipboard from host
        # pyperclip runs on host (where python script runs)
        # Appium runs on host too.
        # But clipboard is shared? Yes, Mac clipboard is global.
        
        import pyperclip
        clipped = pyperclip.paste()
        print(f"Clipboard: {clipped}")
        
        assert "test_image.jpg" in clipped
        print("SUCCESS!")

if __name__ == "__main__":
    unittest.main()
