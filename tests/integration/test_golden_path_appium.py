import unittest
import os
import time
import pyperclip
from appium import webdriver
# 关键修改：使用 WindowsOptions 替代 Mac2Options
from appium.options.windows import WindowsOptions
from appium.webdriver.common.appiumby import AppiumBy
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver import ActionChains
import selenium

class TestGoldenPathAppiumWindows(unittest.TestCase):
    def setUp(self):
        # 1. 路径处理（Windows 使用反斜杠，建议用 abspath）
        self.test_folder = os.path.abspath("tests\\assets\\test-folder")
        if not os.path.exists(self.test_folder):
            os.makedirs(self.test_folder)
        
        dummy_path = os.path.join(self.test_folder, "test_image.jpg")
        if not os.path.exists(dummy_path):
            from PIL import Image
            img = Image.new('RGB', (100, 100), color='red')
            img.save(dummy_path)

        # 2. 清理进程 (Windows 下使用 taskkill)
        os.system("taskkill /F /IM DTImageSearch.exe /T 2>nul")
        
        # 3. 配置 Windows Driver 选项
        app_path = os.path.abspath("dist/DTImageSearch/DTImageSearch.exe")

        print(f"app_path: {app_path}")
        
        options = WindowsOptions()
        options.app = app_path
        options.set_capability("ms:waitForAppLaunch", "100")
        options.set_capability("appium:newCommandTimeout", 100)
        # Windows 环境下通常不需要 bundle_id，直接指定可执行文件路径即可
        
        # 环境变量在 Windows Driver 中可能无法直接通过 options 传入
        # 如果你的 App 依赖这些，建议通过 os.environ 设置或 App 启动参数
        os.environ["UI_TEST"] = "1"
        os.environ["TEST_FOLDER"] = self.test_folder
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["QT_ACCESSIBILITY"] = "1"

        print("Connecting to Windows App Driver...")
        # 默认端口通常是 4723 (Appium Server) 或 4724 (直接连 WAD)
        self.driver = webdriver.Remote("http://127.0.0.1:4723", options=options)
        print("App launched!")

    def tearDown(self):
        if hasattr(self, 'driver'):
            self.driver.quit()

    def test_golden_path(self):
        driver = self.driver
        
        def wait_element(name, timeout: float = 10):
            return WebDriverWait(driver, timeout=timeout).until(
                EC.presence_of_element_located((AppiumBy.XPATH, f"//*[contains(@Name, '{name}')]"))
            )

        # Windows 下没有 IOS_PREDICATE，改用 Name 或 RuntimeId 属性
        def wait_for_status_message_contains(text, timeout=100):
            start_time = time.time()
            while time.time() - start_time < timeout:
                try:
                    # Windows Driver 常用 Name 属性匹配显示的文本
                    # 或者使用 XPath 查找包含特定文本的元素
                    els = driver.find_elements(AppiumBy.XPATH, f"//*[contains(@Name, '{text}')]")
                    if els:
                        return True
                except Exception as e:
                    print(f"Waiting for status: {e}")
                time.sleep(5)
            return False

        print("Step 1: Check/Remove existing folder")
        folder_tree = wait_element("browse_page_folder_tree_view")
        time.sleep(5)
        try:
            # 在 Windows 中，树节点可能需要先展开
            test_folder = folder_tree.find_element(AppiumBy.NAME, "test-folder")
            if test_folder:
                actions = ActionChains(driver)
                actions.context_click(test_folder).perform()
                time.sleep(1)
                # Windows 的右键菜单通常是顶级窗口，可能需要重新切回 root 寻找
                remove_menu = driver.find_element(AppiumBy.NAME, "Remove Folder")
                remove_menu.click()
                time.sleep(2)
        except Exception as e:
            print(f"Test folder not found, proceeding..., {e}")

        print("Step 2: Add Folder")
        add_btn = wait_element("browse_page_add_folder_button")
        add_btn.click()
        
        print("Step 3: Wait for Indexing")
        if not wait_for_status_message_contains("Indexing completed", timeout=300):
            raise TimeoutError("Indexing timeout")
            
        print("Step 4: Search")
        search_input = find_access_id("browse_page_search_input")
        search_input.send_keys("red")
        
        print("Step 5: Check Results & Context Menu")
        time.sleep(3)
        result_list = find_access_id("search_page_image_list_view")
        
        # Windows 的 ActionChains 更加依赖坐标
        actions = ActionChains(driver)
        # 移动到结果列表左上角并偏移，模拟右键第一个元素
        actions.move_to_element_with_offset(result_list, 50, 50).context_click().perform()
        
        print("Step 6: Select 'Copy File Path'")
        time.sleep(1)
        # Windows 下菜单项通常可以通过 Name 找到
        copy_menu = driver.find_element(AppiumBy.NAME, "Copy File Path")
        copy_menu.click()
        
        print("Step 7: Verify Clipboard")
        time.sleep(1)
        clipped = pyperclip.paste()
        print(f"Clipboard content: {clipped}")
        
        self.assertIn("test_image.jpg", clipped)
        print("SUCCESS!")

if __name__ == "__main__":
    unittest.main()