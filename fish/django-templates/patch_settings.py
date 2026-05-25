import re
import sys
from pathlib import Path

settings_path = Path("config/settings.py")
if not settings_path.exists():
    print("ERROR: config/settings.py not found", file=sys.stderr)
    sys.exit(1)

content = settings_path.read_text()

# Add imports
if "import os" not in content:
    content = "import os\n" + content
if "from dotenv import load_dotenv" not in content:
    lines = content.split("\n")
    import_idx = 0
    for i, line in enumerate(lines):
        if line.startswith("import ") or line.startswith("from "):
            import_idx = i + 1
    lines.insert(import_idx, "from dotenv import load_dotenv")
    content = "\n".join(lines)

# Add load_dotenv after BASE_DIR
if "load_dotenv" not in content:
    content = content.replace(
        "BASE_DIR = Path(__file__).resolve().parent.parent",
        "BASE_DIR = Path(__file__).resolve().parent.parent\nload_dotenv(BASE_DIR / \".env\")",
    )

# Replace SECRET_KEY
content = re.sub(
    r"SECRET_KEY = .+",
    'SECRET_KEY = os.environ.get("SECRET_KEY")\nif not SECRET_KEY:\n    raise ValueError("SECRET_KEY must be set in environment")',
    content,
)

# Replace DEBUG
content = re.sub(
    r"DEBUG = .+",
    'DEBUG = os.environ.get("DEBUG", "false").lower() == "true"',
    content,
)

# Replace ALLOWED_HOSTS
content = re.sub(
    r"ALLOWED_HOSTS = \[.*?\]",
    'ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")',
    content,
)

# Replace DATABASES
db_block = """DATABASES = {
    "default": {
        "ENGINE": os.getenv("DB_ENGINE", "django.db.backends.sqlite3"),
        "NAME": os.getenv("DB_NAME", str(BASE_DIR / "db.sqlite3")),
        "USER": os.getenv("DB_USER", ""),
        "PASSWORD": os.getenv("DB_PASSWORD", ""),
        "HOST": os.getenv("DB_HOST", ""),
        "PORT": os.getenv("DB_PORT", ""),
    }
}"""
content = re.sub(r"DATABASES = \{.*?\}", db_block, content, flags=re.DOTALL)

# Add apps to INSTALLED_APPS
new_apps = ['"django_cotton"', '"apps.core"', '"apps.accounts"']
for app in new_apps:
    if app not in content:
        # Try double quotes first
        content = content.replace(
            '    "django.contrib.staticfiles",',
            f'    "django.contrib.staticfiles",\n    {app},',
        )
        # Then single quotes
        content = content.replace(
            "    'django.contrib.staticfiles',",
            f"    'django.contrib.staticfiles',\n    {app.replace(chr(34), chr(39))},",
        )

# Add TEMPLATES DIRS
content = content.replace(
    '            "DIRS": [],',
    '            "DIRS": [BASE_DIR / "templates"],',
)
content = content.replace(
    "            'DIRS': [],",
    "            'DIRS': [BASE_DIR / 'templates'],",
)

# Add STATICFILES_DIRS
if "STATICFILES_DIRS" not in content:
    content = content.replace(
        'STATIC_URL = "static/"',
        'STATIC_URL = "static/"\nSTATICFILES_DIRS = [BASE_DIR / "static"]',
    )
    content = content.replace(
        "STATIC_URL = 'static/'",
        "STATIC_URL = 'static/'\nSTATICFILES_DIRS = [BASE_DIR / 'static']",
    )

settings_path.write_text(content)
print("Settings updated")
