#!/bin/bash
# usage: shoot.sh name...   -> /tmp/seam-tree/v6/<name>.png (2x, trimmed, cropped to the screen)
cd /tmp/seam-tree/v6
for n in "$@"; do
  chromium --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1400,900 --screenshot=/tmp/seam-tree/v6/$n.png file:///tmp/seam-tree/v6/$n.html 2>/dev/null
  magick $n.png -fuzz 3% -trim +repage -crop 2316x+0+0 +repage $n.png
done
