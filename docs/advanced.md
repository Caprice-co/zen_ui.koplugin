---
title: Advanced
category: Advanced
summary: Access metadata extraction, OPDS enhancements, refresh behavior, custom icons, logs, gestures, and plugin tools.
settingsPath: Zen UI > Advanced
order: 70
---

![Zen UI settings](/images/zen_ui/zen_settings.png)

## Overview

Advanced settings expose maintenance and lower-level behavior. They include metadata extraction, OPDS enhancements, partial refresh, custom icons, hidden file visibility, debug logging, gesture reset, plugin management, and patch management.

## Options

- Extract metadata and cover images for books in the current directory.
- Enable Zen OPDS enhancements.
- Toggle partial page refresh.
- Allow custom user icons to override bundled Zen UI icons.
- Show hidden and unsupported files outside the home folder.
- Toggle KOReader verbose debug logging.
- Clear gestures while preserving reader top-right bookmark.
- Open KOReader plugin and patch management tools.

## OPDS

![OPDS catalog](/images/zen_ui/opds.png)

![OPDS context menu](/images/zen_ui/opds_context.png)

Enable **Advanced > Zen OPDS** to apply Zen UI styling to the OPDS catalog browser. The OPDS view inherits the same styling as your library — rounded corners, list and mosaic view, items per page, and other layout options all carry over. Each book in the catalog shows its cover.

You can also set a default OPDS catalog so OPDS opens directly inside it when launched, skipping the catalog list.

Tap and hold any item to open the OPDS context menu for per-item actions.

| Setting | Description |
| --- | --- |
| Zen OPDS | Enables Zen UI OPDS enhancements, including cover art, list/mosaic view, hold menu, and navigation changes. Inherits library layout styling (rounded corners, view mode, items per page). |
| Default catalog | Sets a default OPDS catalog that opens directly when launching OPDS. |

## Custom Icons
To enable custom icons, first enable the setting in Advanced > Allow custom icons. Then place your icons in the `/koreader/icons` folder. Any icon that Zen UI uses will prefer the icons placed in the `/koreader/icons` folder when enabled. There will be a custom icon pack loader in the future. 
> Note: Any icons placed directly inside the Zen UI plugin i.e `/koreader/plugins/zen_ui.koplugin/icons` folder will be erased on updates so don't put your custom icons here.

## Setting reference

| Setting | Description |
| --- | --- |
| Advanced > Extract metadata | Extracts and caches book metadata and cover images for the current directory. |
| Advanced > Zen OPDS | Enables Zen UI OPDS enhancements, including cover art, list view, hold menu, and navigation changes. |
| Advanced > Partial pages refresh | Enables partial page repaint behavior. |
| Advanced > Allow custom icons | Lets KOReader user icons override bundled Zen UI icons, with fallback to bundled and built-in icons. |
| Advanced > Show hidden files | Shows hidden and unsupported files outside the home folder and hides them again when disabled. |
| Advanced > Debug logging | Toggles KOReader debug and verbose debug settings. |
| Advanced > Clear all gestures | Clears file manager and reader gestures, then sets reader top-right tap to toggle bookmark. |
| Advanced > Plugin management | Opens KOReader plugin management. |
| Advanced > Patch management | Opens KOReader patch management when available. |

