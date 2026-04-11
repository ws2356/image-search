from abc import ABC, abstractmethod
from typing import Optional, Tuple
from pathlib import Path
from PySide6.QtCore import Qt
from dt_image_search.base.image_list_model import ImageListModel


class ImageNavigator(ABC):
    """Abstract interface for image navigation."""
    
    @abstractmethod
    def get_current_image(self) -> Optional[str]:
        """Get the path of the current image."""
        pass
    
    @abstractmethod
    def get_next_image(self) -> Optional[str]:
        """Get the path of the next image, or None if at the end."""
        pass
    
    @abstractmethod
    def get_previous_image(self) -> Optional[str]:
        """Get the path of the previous image, or None if at the beginning."""
        pass
    
    @abstractmethod
    def move_to_next(self) -> bool:
        """Move to the next image. Returns True if successful, False if at the end."""
        pass
    
    @abstractmethod
    def move_to_previous(self) -> bool:
        """Move to the previous image. Returns True if successful, False if at the beginning."""
        pass
    
    @abstractmethod
    def get_navigation_info(self) -> Tuple[int, int]:
        """Get current position and total count as (current_index, total_count)."""
        pass
    
    @abstractmethod
    def has_navigation(self) -> bool:
        """Return True if navigation is available (more than one image)."""
        pass


class ModelBasedNavigator(ImageNavigator):
    """Navigator implementation that wraps an ImageListModel.
    
    This navigator uses the provided ImageListModel to navigate through images
    in the order they appear in the model. This is efficient since it doesn't
    need to search through the model to find the initial position.
    """
    
    def __init__(self, model: ImageListModel, initial_index: int = 0):
        """Initialize the navigator with a model and starting index.
        
        Args:
            model: The ImageListModel to navigate through
            initial_index: The index of the image to start at (0-based)
        """
        self.model = model
        self.current_index = min(max(0, initial_index), model.rowCount() - 1) if model.rowCount() > 0 else 0
    
    def get_current_image(self) -> Optional[str]:
        """Get the path of the current image."""
        if 0 <= self.current_index < self.model.rowCount():
            index = self.model.index(self.current_index)
            return index.data(Qt.UserRole)
        return None
    
    def get_next_image(self) -> Optional[str]:
        """Get the path of the next image, or None if at the end."""
        next_index = self.current_index + 1
        if next_index < self.model.rowCount():
            index = self.model.index(next_index)
            return index.data(Qt.UserRole)
        return None
    
    def get_previous_image(self) -> Optional[str]:
        """Get the path of the previous image, or None if at the beginning."""
        prev_index = self.current_index - 1
        if prev_index >= 0:
            index = self.model.index(prev_index)
            return index.data(Qt.UserRole)
        return None
    
    def move_to_next(self) -> bool:
        """Move to the next image. Returns True if successful, False if at the end."""
        if self.current_index + 1 < self.model.rowCount():
            self.current_index += 1
            return True
        return False
    
    def move_to_previous(self) -> bool:
        """Move to the previous image. Returns True if successful, False if at the beginning."""
        if self.current_index > 0:
            self.current_index -= 1
            return True
        return False
    
    def get_navigation_info(self) -> Tuple[int, int]:
        """Get current position and total count as (current_index, total_count)."""
        return self.current_index, self.model.rowCount()
    
    def has_navigation(self) -> bool:
        """Return True if navigation is available (more than one image)."""
        return self.model.rowCount() > 1


class FolderBasedNavigator(ImageNavigator):
    """Navigator implementation that navigates through images in a folder.
    
    This navigator scans the filesystem to find all images in the same folder
    as the provided image path, then allows navigation through them.
    """
    
    def __init__(self, image_path: str, initial_index: int = None):
        """Initialize the navigator with an image path and optional starting index.
        
        Args:
            image_path: Path to the initial image
            initial_index: Optional index to start at. If None, will search for
                          the image_path in the folder to determine the index.
        """
        self.current_path = Path(image_path)
        self.image_files = []
        self.current_index = 0
        self._initial_index_provided = initial_index is not None
        
        self._load_folder_images()
        
        # If an initial index is provided, use it (with bounds checking)
        if initial_index is not None:
            self.current_index = min(max(0, initial_index), len(self.image_files) - 1) if self.image_files else 0
    
    def _load_folder_images(self):
        """Load all image files from the current image's folder."""
        if not self.current_path.exists():
            return
        
        # Get all image files in the same directory
        image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tiff', '.webp', '.heic', '.heif'}
        folder = self.current_path.parent
        
        image_files = []
        for ext in image_extensions:
            image_files.extend(folder.glob(f"*{ext}"))
            image_files.extend(folder.glob(f"*{ext.upper()}"))
        
        # Sort the files and find the current index (only if initial_index wasn't provided)
        self.image_files = sorted([str(f) for f in image_files])
        
        # Find the current image in the list if no initial index was provided in constructor
        if not self._initial_index_provided:
            try:
                self.current_index = self.image_files.index(str(self.current_path))
            except ValueError:
                # If current file not found in list, add it and set as current
                self.image_files.insert(0, str(self.current_path))
                self.current_index = 0
    
    def get_current_image(self) -> Optional[str]:
        """Get the path of the current image."""
        if 0 <= self.current_index < len(self.image_files):
            return self.image_files[self.current_index]
        return None
    
    def get_next_image(self) -> Optional[str]:
        """Get the path of the next image, or None if at the end."""
        next_index = self.current_index + 1
        if next_index < len(self.image_files):
            return self.image_files[next_index]
        return None
    
    def get_previous_image(self) -> Optional[str]:
        """Get the path of the previous image, or None if at the beginning."""
        prev_index = self.current_index - 1
        if prev_index >= 0:
            return self.image_files[prev_index]
        return None
    
    def move_to_next(self) -> bool:
        """Move to the next image. Returns True if successful, False if at the end."""
        if self.current_index + 1 < len(self.image_files):
            self.current_index += 1
            return True
        return False
    
    def move_to_previous(self) -> bool:
        """Move to the previous image. Returns True if successful, False if at the beginning."""
        if self.current_index > 0:
            self.current_index -= 1
            return True
        return False
    
    def get_navigation_info(self) -> Tuple[int, int]:
        """Get current position and total count as (current_index, total_count)."""
        return self.current_index, len(self.image_files)
    
    def has_navigation(self) -> bool:
        """Return True if navigation is available (more than one image)."""
        return len(self.image_files) > 1
