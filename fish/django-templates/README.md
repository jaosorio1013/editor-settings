# Django Scaffolding — Fish Functions

Funciones Fish para scaffoldear proyectos Django modernos alineados con el skill `/django`.

---

## Requisitos previos

- `fish` (shell)
- `uv` (gestor de Python)
- `bun` (solo para `django_setup_frontend`)

Las funciones se cargan automáticamente porque están en `~/.config/fish/functions/`.

---

## Comandos

### `django_start_project [nombre]`

Crea un proyecto Django con estructura moderna.

```fish
# En directorio vacío
django_start_project

# O con nombre (crea la carpeta)
django_start_project mi_proyecto
```

**Genera:**
- `apps/core/` — `BaseModel` con soft delete, managers `objects` y `all_objects`
- `apps/accounts/` — App lista para custom User
- `templates/cotton/` — Estructura para componentes cotton (ui/, layout/, forms/)
- `static/{css,js,images}/` — Assets
- `tests/` — Para pytest
- `.env` — Con `SECRET_KEY` real, `DEBUG=true`, SQLite por defecto
- `.env.example` — Plantilla para producción (con PostgreSQL comentado)
- `.gitignore` — Python + Django + uv + IDE + testing
- `pytest.ini` — Configuración de pytest
- `nixpacks.toml` — Config de deploy para Dockploy/Nixpacks
- Parchea `config/settings.py`:
  - Carga variables desde `.env` con `python-dotenv`
  - `SECRET_KEY` desde env (falla si no está)
  - `DEBUG` desde env (default `false`)
  - `ALLOWED_HOSTS` desde env
  - `DATABASES` configurable vía env (SQLite default, PostgreSQL opcional)
  - Agrega `django_cotton`, `apps.core`, `apps.accounts` a `INSTALLED_APPS`
  - Configura `TEMPLATES['DIRS']` y `STATICFILES_DIRS`

**Siguientes pasos:**
```fish
uv run python manage.py migrate
uv run python manage.py runserver
```

---

### `django_start_app <nombre>`

Crea una app con estructura de carpetas moderna (NO archivos planos).

```fish
django_start_app evaluations
```

**Genera:**
```
apps/evaluations/
├── __init__.py
├── apps.py          # CamelCase automático (EvaluationsConfig)
├── urls.py
├── models/
│   └── __init__.py
├── admin/
│   └── __init__.py
├── views/
│   └── __init__.py
├── services/
│   └── __init__.py
├── dtos/
│   └── __init__.py
├── seeders/
│   └── __init__.py
└── domain/
    └── __init__.py
```

Y la agrega automáticamente a `INSTALLED_APPS` en `config/settings.py`.

---

### `django_setup_frontend`

Instala el stack frontend en un proyecto ya creado.

```fish
django_setup_frontend
```

**Requiere:** estar en la raíz del proyecto (donde está `manage.py`).

**Instala vía `bun`:**
- Tailwind CSS v4
- Preline UI

**Copia:**
- `package.json` — Scripts `build` y `watch` para Tailwind
- `static/css/main.css` — Imports de Tailwind + Preline + tema custom
- `static/js/preline_init.js` — `HSStaticMethods.autoInit()` + listener `htmx:afterSwap`
- `templates/base.html` — Layout base con HTMX, Alpine.js, Preline

**Comandos útiles después:**
```fish
bun run build   # build CSS una vez
bun run watch   # watch mode
```

---

### `django_test [args]`

Alias para correr pytest a través de `uv`.

```fish
django_test                # todos los tests
django_test -k test_models # filtrar por nombre
django_test --lf           # solo los que fallaron
```

---

## Arquitectura de archivos

Las funciones están separadas de los templates:

```
~/.config/fish/
├── functions/
│   ├── django_start_project.fish
│   ├── django_start_app.fish
│   ├── django_test.fish
│   └── django_setup_frontend.fish
└── django-templates/
    ├── core/
    │   ├── models_base.py
    │   ├── models_init.py
    │   └── apps.py
    ├── accounts/
    │   └── apps.py
    ├── frontend/
    │   ├── base.html
    │   ├── main.css
    │   ├── package.json
    │   └── preline_init.js
    ├── patch_settings.py        # Script Python que parchea settings.py
    ├── add_installed_app.py     # Script Python que agrega a INSTALLED_APPS
    ├── app_urls.py              # Template urls.py para apps
    ├── env.example
    ├── gitignore
    ├── pytest.ini
    └── nixpacks.toml
```

**Ventaja:** los templates son archivos reales. Los editás con tu IDE, con syntax highlighting, ruff, pyright. No hay strings embebidos en Fish.

---

## Tips

- **Crear superuser rápido:** `uv run python manage.py createsuperuser`
- **Shell con todo cargado:** `uv run python manage.py shell`
- **Formato automático:** `ruff format .` y `ruff check --select I --fix .`
- **Si cambiás un template base** (ej: `models_base.py`), la próxima app que crees usa la versión actualizada.
