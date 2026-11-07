# DMG Resources

Finder background assets and frozen layout spec for the JPtheCat installer DMG.

## Layout

- View mode: icon view
- Toolbar/status bar: hidden
- Arrangement: not arranged
- Window bounds size: 735x510
- Icon size: 112
- Text size: 14
- `JPtheCat.app` position: 250,205
- `Applications` position: 470,205
- Install UX: drag `JPtheCat.app` to the `Applications` symlink

## Assets

| File | Dimensions | Source |
| --- | --- | --- |
| `background.png` | 720x450 | 1x downsample of `../../../web/public/dmg-bg.png` |
| `background@2x.png` | 1440x900 | Copy of `../../../web/public/dmg-bg.png` |

The source image is an opaque 72 dpi PNG. Keep the center visually quiet so the Finder icons and
labels remain readable.

## Regeneration

```bash
cd mac
sips -z 450 720 ../web/public/dmg-bg.png --out scripts/dmg-resources/background.png
cp ../web/public/dmg-bg.png scripts/dmg-resources/background@2x.png
sips -g pixelWidth -g pixelHeight -g dpiWidth -g dpiHeight -g hasAlpha \
  scripts/dmg-resources/background.png \
  scripts/dmg-resources/background@2x.png
```
