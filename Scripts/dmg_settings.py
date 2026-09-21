import os

app_path = defines.get("app", "OneGram.app")
app_name = os.path.basename(app_path)
format = defines.get("format", "ULMO")

files = [app_path]
symlinks = {"Applications": "/Applications"}

icon_locations = {
    app_name: (140, 165),
    "Applications": (400, 165),
}

background_color = "#ffffff"
icon_size = 128
text_size = 14
label_pos = "bottom"
window_rect = ((200, 200), (540, 380))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
grid_offset = (0, 0)
