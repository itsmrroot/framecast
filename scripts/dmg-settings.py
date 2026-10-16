# dmgbuild settings for the Framecast installer disk image. Used by scripts/make-dmg.sh.
import os.path

app = defines["app"]
app_name = os.path.basename(app)

volume_name = "Framecast"
format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("icon")
background = defines["background"]

window_rect = ((200, 160), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
icon_size = 112
text_size = 13
arrange_by = None
icon_locations = {app_name: (170, 190), "Applications": (490, 190)}
hide_extensions = [app_name]
