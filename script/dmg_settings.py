import os

app = defines["app"]
background = defines["background"]
format = "ULFO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
window_rect = ((180, 140), (720, 460))
icon_locations = {"VideoVault.app": (190, 218), "Applications": (530, 218)}
icon_size = 96
text_size = 14
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
include_icon_view_settings = True
include_list_view_settings = False
iconview_options = {"arrange_by": "none"}
