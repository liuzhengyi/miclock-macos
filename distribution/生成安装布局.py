#!/usr/bin/env python3
"""Write reproducible Finder icon positions without opening the user's Finder.

Build dependency: ds_store 1.3.2 (Apache/MIT), installed in an isolated build
environment. No app installation, user preferences or login items are touched.
"""
import sys
from pathlib import Path
from ds_store import DSStore
from mac_alias import Alias

root = Path(sys.argv[1])
background = root / ".background" / "install.png"
alias = Alias.for_file(str(background))
icon_options = {
    "viewOptionsVersion": 1,
    "backgroundType": 2,
    "backgroundColorRed": 0.98,
    "backgroundColorGreen": 0.98,
    "backgroundColorBlue": 0.98,
    "backgroundImageAlias": alias.to_bytes(),
    "iconSize": 96.0,
    "gridSpacing": 100.0,
    "gridOffsetX": 0.0,
    "gridOffsetY": 0.0,
    "scrollPositionX": 0.0,
    "scrollPositionY": 0.0,
    "textSize": 13.0,
    "labelOnBottom": True,
    "showItemInfo": False,
    "showIconPreview": True,
    "arrangeBy": "none",
}
window_options = {
    "WindowBounds": "{{200, 150}, {640, 400}}",
    "ShowToolbar": False,
    "ShowStatusBar": False,
    "ShowSidebar": False,
    "ShowTabView": False,
    "ContainerShowSidebar": False,
    "SidebarWidth": 0,
}
with DSStore.open(str(root / ".DS_Store"), "w+") as store:
    store["."]["bwsp"] = window_options
    store["."]["icvp"] = icon_options
    store["."]["vSrn"] = ("long", 1)
    store["."]["icvl"] = ("type", b"icnv")
    store["MicLock.app"]["Iloc"] = (165, 205)
    store["Applications"]["Iloc"] = (475, 205)
