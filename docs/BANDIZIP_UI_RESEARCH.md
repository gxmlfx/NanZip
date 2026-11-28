# Bandizip UI Research

Research date: 2026-11-28

Important: this research uses **official web screenshots only**. The locally installed Bandizip app was not opened or captured.

## Sources

- Bandizip macOS screenshot page: https://www.bandisoft.com/bandizip.mac/screenshots/
- macOS compression options screenshot: https://www.bandisoft.com/bandizip.mac/screenshots/imgs/01_new_archive_more_en.png
- macOS preferences screenshot: https://www.bandisoft.com/bandizip.mac/screenshots/imgs/02_settings_en.png
- Bandizip Windows screenshot page: https://www.bandisoft.com/bandizip/screenshots/
- Windows main screen: https://www.bandisoft.com/bandizip/screenshots/imgs.en/01.png
- Windows create archive: https://www.bandisoft.com/bandizip/screenshots/imgs.en/03.png
- Windows archive browsing: https://www.bandisoft.com/bandizip/screenshots/imgs.en/05.png
- Windows extraction progress: https://www.bandisoft.com/bandizip/screenshots/imgs.en/06.png
- Windows context menu and preview: https://www.bandisoft.com/bandizip/screenshots/imgs.en/07.png

## Layout observations

### Main screen

- Two large primary actions: open an existing archive and create a new archive.
- Dense desktop application rather than a large marketing-style dashboard.
- Status/help area remains at the bottom.

### Archive browsing

- A compact icon command bar across the top.
- Left-side archive/folder tree.
- Central dense file table with columns for name, packed size, original size and file type.
- Bottom status strip reports selected item count, packed/original sizes and archive size.
- Search and sorting are always close to the file table.

### Create archive

- The dialog is divided into:
  1. files to add;
  2. total size and add/remove actions;
  3. archive settings;
  4. test/delete-source/per-file options;
  5. Start/Cancel actions.
- Archive settings are presented as labeled rows: filename, format, password, split volume and compression level.
- Advanced options are secondary and collapsed.

### Extraction

- Overall and current-item progress are shown separately.
- Current archive path is visible while extraction runs.
- Pause and stop are prominent.
- The archive list remains visible behind the progress panel.

### Context menu and preview

- Extraction destinations are grouped into simple actions.
- Preview entries are nested near extraction actions.
- The menu stays compact rather than exposing all archive commands at the first level.

## NanZip adaptation

NanZip now follows the same information hierarchy without copying Bandizip artwork or exact layout:

- Two-action landing screen.
- Icon command bar for Open, Extract, New, Add, Replace, Delete and Test.
- Left archive tree and central multi-column file table.
- Bottom selection/original/packed/archive statistics.
- Dedicated New Archive page with an input table and labeled settings grid.
- Liquid Glass surfaces on macOS 26/27 and material fallback on macOS 14–25.
- Finder actions remain grouped under a single `NanZip` submenu.
