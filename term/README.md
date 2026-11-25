# Terminal palette

`0nhooyr.terminal` explicitly sets all 16 ANSI colors to standard sRGB values.
The profile stores compact archived color objects; this table records their
six-digit hex values.

After editing the profile, run `./term/generate.pl` on macOS. It compacts the
profile's colors as sRGB, refreshes this table, and generates the VS Code and
TextMate themes from `theme.json.in`. Edit that template to change theme rules;
edit the Terminal profile to change the palette.

| Color | Regular | Bright |
|---|---|---|
| Black | `#000000` | `#5C5C5C` |
| Red | `#B60000` | `#B60000` |
| Green | `#0A5C07` | `#0A5C07` |
| Yellow | `#CC0077` | `#FFFF00` |
| Blue | `#0000B3` | `#0000B3` |
| Magenta | `#6E066E` | `#6E066E` |
| Cyan | `#0A4045` | `#0A4045` |
| White | `#FFFFFF` | `#FFFFFF` |

Bright yellow is reserved for match highlighting and selection, always as a
background with black text. Regular yellow is available for foreground text.
