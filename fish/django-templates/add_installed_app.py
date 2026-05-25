import re
import sys
from pathlib import Path

if len(sys.argv) < 2:
    print("Usage: add_installed_app.py <app_name>", file=sys.stderr)
    sys.exit(1)

app_name = sys.argv[1]
settings_path = Path("config/settings.py")
if not settings_path.exists():
    print("ERROR: config/settings.py not found", file=sys.stderr)
    sys.exit(1)

content = settings_path.read_text()
app_entry = f'"apps.{app_name}"'

if app_entry in content:
    print(f"App {app_name} already in INSTALLED_APPS")
    sys.exit(0)

# Insert after apps.accounts (or apps.core if accounts not present)
marker = '    "apps.accounts",'
if marker in content:
    content = content.replace(marker, f'{marker}\n    {app_entry},')
else:
    marker = '    "apps.core",'
    if marker in content:
        content = content.replace(marker, f'{marker}\n    {app_entry},')
    else:
        marker = '    "django.contrib.staticfiles",'
        content = content.replace(marker, f'{marker}\n    {app_entry},')

settings_path.write_text(content)
print(f"Added apps.{app_name} to INSTALLED_APPS")
