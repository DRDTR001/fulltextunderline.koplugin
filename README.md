# Full Text Underline

**Language**

- 🇺🇸 English (Current)
- 🇨🇳 [简体中文](README.zh-CN.md)

Full Text Underline is a KOReader plugin that draws configurable reading lines beneath visible text in reflowable documents without modifying the book or changing its layout.

## Features

- Solid lines
- Dashed lines
- Dotted lines（dotted lines are best visible at thickness level 2 or above)
- Full-width mode
- Text-width mode
- Adjustable underline position
- Adjustable underline length
- Adjustable line thickness
- Optional heading underlines
- Per-book settings
- Plugin defaults for new books
- KOReader Reading Profile integration
- English and Simplified Chinese interface


# Screenshots

## Underline Styles

| Solid | Dashed | Dotted |
|---|---|---|
| ![Solid](screenshots/实线.png) | ![Dashed](screenshots/虚线.png) | ![Dotted](screenshots/点线.png) |


## Text-width Mode

![Text-width Mode](screenshots/文字跟随.png)


## Interface

English interface:

![English Interface](screenshots/英文.png)


Chinese interface:

![Chinese Interface](screenshots/中文.png)



# Compatibility

Tested on:

- Kindle
- Kobo
- Android KOReader


Versions:

- Recommended: KOReader v2026.07.1 or later
- Tested: KOReader v2026.07.1


The plugin is intended for reflowable CRengine documents such as EPUB.

It is not intended for PDF or other fixed-layout documents.



# Installation

1. Download `fulltextunderline-v1.0.0.zip` from the GitHub Releases page.

2. Extract the archive.

3. Copy the resulting `fulltextunderline.koplugin` directory to:

   ```text
   koreader/plugins/
   ```

4. Restart KOReader.
5. Open a reflowable book and select **Full Text Underline** from the typesetting menu.

To update, exit KOReader and replace the existing plugin directory with the directory from the new release.

## Usage

### Enable

Turns the reading lines on or off for the current book.

### Line Style

- **Solid** — continuous horizontal lines.
- **Dashed** — clearly separated dash segments.
- **Dotted** — evenly spaced dots that follow the selected thickness.

### Underline Mode

- **Full-width Lines** — every detected visual text line is underlined across the full content width.
- **Text-width Lines** — each underline follows the bounding width of that visual text line.

### Underline Position

Moves only the rendered line up or down. It does not move text, change line spacing, or repaginate the document.

### Underline Length

Symmetrically lengthens or shortens both ends of the line. The saved range is `-20` to `+20`; `0` preserves the base line geometry.

### Line Thickness

Adjusts solid, dashed, and dotted lines together from level `1` through `6`.

### Underline Headings

Headings are excluded by default. Enable this option to draw lines beneath detected headings as well.

### Book Settings

Changes made from the menu are saved for the current book. A book with its own saved settings is not changed when plugin defaults are updated later.

### Plugin Defaults

Under **More Settings**, select **Set Current Settings as Default** to use the current underline configuration for newly opened books. Existing per-book settings remain untouched.

### Reading Profile

When a KOReader Reading Profile contains Full Text Underline fields, loading that profile applies them as the highest-priority runtime configuration. Profile values are not automatically written back to per-book settings or plugin defaults.

## Configuration Priority

```text
Reading Profile
      ↓
Current Book
      ↓
Plugin Defaults
      ↓
Built-in Defaults
```

The plugin keeps internal configuration values independent from translated interface labels, so switching KOReader's language does not alter saved settings.

## Internationalization

English is the source language. Simplified Chinese translations are provided in `locale/zh_CN/`. KOReader v2026.07.1 does not automatically scan plugin-local translation catalogs, so the plugin loads its compiled catalog through KOReader's own `gettext.loadMO()` API. Unsupported languages fall back to English.

## Limitations

- The plugin only draws into the current ReaderView buffer; it does not edit or annotate the EPUB.
- It does not change text layout, font size, line spacing, margins, or pagination.
- It currently targets reflowable CRengine documents.
- Visual placement depends on the text screen boxes supplied by the installed KOReader version.

## Known Issues

- Some very old KOReader versions do not provide the ReaderView behavior required by the plugin and may display no lines.
- Device fonts and rendering scale can affect the visually preferred position and thickness; both are adjustable from the menu.

## Uninstall or Roll Back

Exit KOReader, remove `koreader/plugins/fulltextunderline.koplugin`, and restart KOReader. To roll back, replace the directory with one from an earlier release. Book files are never modified.

## License

Full Text Underline is released under the [GNU Affero General Public License v3.0](LICENSE), matching the license family of the KOReader APIs it integrates with.

## Suggested GitHub Topics

`koreader` · `koreader-plugin` · `kindle` · `kobo` · `ebook` · `lua` · `epub` · `reader`

