#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    content = path.read_text()
    count = content.count(old)
    if count != 1:
        raise SystemExit(f"expected one match in {path}, found {count}")
    path.write_text(content.replace(old, new))


novnc_root = Path("/usr/share/novnc")

# noVNC normally waits one second before recognizing a stationary touch. A
# shorter delay makes the resulting left-button hold feel like direct touch,
# while still preserving quick taps and drag gesture detection.
replace_once(
    novnc_root / "core/input/gesturehandler.js",
    "const GH_LONGPRESS_TIMEOUT = 1000;",
    "const GH_LONGPRESS_TIMEOUT = 150;",
)

# Stock noVNC maps a touch hold to VNC right-click. scrcpy interprets
# right-click as Android BACK, so Android never receives a held primary touch.
# Keep the primary button down from longpress start until gestureend instead.
replace_once(
    novnc_root / "core/rfb.js",
    """                        } else {
                            this._fakeMouseMove(ev, pos.x, pos.y);
                            this._handleMouseButton(pos.x, pos.y, 0x4);
                        }
                        break;
                    case 'twodrag':""",
    """                        } else {
                            this._fakeMouseMove(ev, pos.x, pos.y);
                            // Dedicated Android direct-touch profile: hold the
                            // primary button instead of emitting right-click.
                            this._handleMouseButton(pos.x, pos.y, 0x1);
                        }
                        break;
                    case 'twodrag':""",
)
