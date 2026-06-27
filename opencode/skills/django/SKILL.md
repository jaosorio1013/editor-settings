---
name: django
description: >
  Guía para proyectos Django modernos. Patrones universales (BaseModel, settings por ambiente,
  DDT HTMX-safe, EncryptedCharField, rate limiting, django-q2), patrones condicionales
  (domain layer, snapshot, singleton cache, calculator, conditional constraints),
  stack frontend (django-cotton + Preline UI + HTMX + Alpine.js), y auditoría de proyectos.
license: Apache-2.0
metadata:
  author: gentleman-programming
  version: "3.1"
---

## When to Use

- Iniciando un proyecto Django desde cero
- Revisando un proyecto en curso para verificar patrones
- Auditando un proyecto para identificar qué falta
- Configurando linting, testing, o tooling
- Decidiendo stack frontend (HTMX vs API vs SPA) para un proyecto Django
- Configurando django-cotton + Preline UI + Tailwind CSS

## Estructura de app moderna

**NO usar archivos únicos** (`models.py`, `admin.py`, `seeders.py`) porque crecen mucho y son difíciles de mantener.

**SIEMPRE usar carpetas**:

```
app/
├── __init__.py
├── apps.py
├── admin/
│   ├── __init__.py
│   ├── evaluation_admin.py
│   ├── user_admin.py
│   └── ...
├── models/
│   ├── __init__.py
│   ├── base.py           # BaseModel, managers
│   ├── user.py
│   ├── organization.py
│   └── ...
├── services/
│   ├── __init__.py
│   ├── evaluation_service.py
│   └── ...
├── dtos/
│   ├── __init__.py
│   ├── evaluation_dto.py
│   └── ...
├── seeders/
│   ├── __init__.py
│   ├── evaluation_seeder.py
│   └── ...
├── domain/              # Lógica pura, sin imports Django
│   ├── __init__.py
│   └── evaluation_logic.py
├── views/
│   ├── __init__.py
│   └── evaluation_views.py
├── urls.py
└── apps.py
```

### Cuándo usar cada directorio

| Directorio | Propósito | Cuándo usarlo |
|-----------|----------|-------------|
| `models/` | Modelos Django | **SIEMPRE** - más de 2 modelos |
| `admin/` | Configuración admin | **SIEMPRE** - más de 2 modelos |
| `services/` | Lógica de negocio | **DEPENDE** - si hay orchestration |
| `dtos/` | Data Transfer Objects | **DEPENDE** - si hay API |
| `seeders/` | Datos de prueba | **DEPENDE** - si hay data seeding |
| `domain/` | Lógica pura (testeable) | **DEPENDE** - si hay lógica compleja |
| `views/` | Vistas (si hay muchas) | **DEPENDE** - más de 5 vistas |

---

## Categorización de patrones

| Categoría | Descripción | Ejemplo |
|----------|------------|---------|
| **SIEMPRE** | Patrones universales que aplican a cualquier proyecto Django | BaseModel con soft delete, settings seguros |
| **DEPENDE** | Opciones que dependen del contexto del proyecto | Multitenant, Evaluation con is_global |
| **NO VA** | Específicos de este projeto (tests-360 SaaS) | TenantMiddleware, Assignment con roles |

---

## Patrones que SIEMPRE aplican

### 1. BaseModel con soft delete universal

Todos los modelos heredan de `BaseModel`. Siempre dos managers: `objects` (activos) y `all_objects` (todos).

```python
# apps/core/models/base.py
class SoftDeleteQuerySet(models.QuerySet):
    def delete(self):
        return self.update(deleted_at=timezone.now())

    def hard_delete(self):
        return super().delete()

    def restore(self):
        return self.update(deleted_at=None)

class SoftDeleteManager(models.Manager):
    def get_queryset(self):
        return SoftDeleteQuerySet(self.model, using=self._db).filter(deleted_at__isnull=True)

class GlobalManager(models.Manager):
    def get_queryset(self):
        return SoftDeleteQuerySet(self.model, using=self._db)

class BaseModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True, editable=False)

    objects = SoftDeleteManager()
    all_objects = GlobalManager()

    class Meta:
        abstract = True
        ordering = ["-created_at"]

    def delete(self, *args, **kwargs):
        self.deleted_at = timezone.now()
        self.save(update_fields=["deleted_at", "updated_at"])

    def hard_delete(self, *args, **kwargs):
        super().delete()

    def restore(self):
        self.deleted_at = None
        self.save(update_fields=["deleted_at", "updated_at"])
```

```python
# apps/core/models/__init__.py
from apps.core.models.base import BaseModel, SoftDeleteManager, GlobalManager

__all__ = ["BaseModel", "SoftDeleteManager", "GlobalManager"]
```

### 2. Settings seguros

- `DEBUG` nunca hardcodeado. Default: `False`.
- `SECRET_KEY` siempre desde `os.environ` (explota si no está).
- `.env` en `.gitignore`, `.env.example` versionado.

```python
# config/settings.py
import os
from pathlib import Path
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

SECRET_KEY = os.environ.get("SECRET_KEY")
if not SECRET_KEY:
    raise ValueError("SECRET_KEY must be set in environment")

DEBUG = os.environ.get("DEBUG", "false").lower() == "true"

ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")

# Database - configurable via env (SQLite default, PostgreSQL for production)
DATABASES = {
    "default": {
        "ENGINE": os.getenv("DB_ENGINE", "django.db.backends.sqlite3"),
        "NAME": os.getenv("DB_NAME", str(BASE_DIR / "db.sqlite3")),
        "USER": os.getenv("DB_USER", ""),
        "PASSWORD": os.getenv("DB_PASSWORD", ""),
        "HOST": os.getenv("DB_HOST", ""),
        "PORT": os.getenv("DB_PORT", ""),
    }
}
```

```bash
# .env.example
SECRET_KEY=your-secret-key-here
DEBUG=false
ALLOWED_HOSTS=localhost,127.0.0.1

# SQLite (desarrollo local - default)
DB_ENGINE=django.db.backends.sqlite3
DB_NAME=db.sqlite3

# PostgreSQL (producción)
# DB_ENGINE=django.db.backends.postgresql
# DB_NAME=tests360
# DB_USER=postgres
# DB_PASSWORD=***
# DB_HOST=localhost
# DB_PORT=5432
```

### 3. Settings por ambiente (base → local → production)

Proyectos reales necesitan configuraciones distintas para desarrollo local, staging, y producción. Un solo `settings.py` con `if DEBUG` es frágil.

**Estructura recomendada:**

```
config/
├── settings/
│   ├── __init__.py   # Auto-detecta ambiente y carga el módulo correcto
│   ├── base.py        # Config común a todos los ambientes
│   ├── local.py       # Desarrollo: DEBUG=True, SQLite, console email
│   └── production.py  # Producción: DEBUG=False, PostgreSQL, HSTS, Sentry
├── urls.py
└── wsgi.py
```

```python
# config/settings/__init__.py
import os
import importlib

ENVIRONMENT = os.environ.get("DJANGO_ENVIRONMENT", "local")
_module = importlib.import_module(f"config.settings.{ENVIRONMENT}")
globals().update({k: v for k, v in _module.__dict__.items() if not k.startswith("_")})
```

```python
# config/settings/base.py
import os
from pathlib import Path
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent.parent
load_dotenv(BASE_DIR / ".env")

SECRET_KEY = os.environ["SECRET_KEY"]  # Explota si no está — sin fallback

# Apps, middleware, templates, database base, i18n — común a todos los ambientes
INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    # ...
    "apps.core",
]
```

```python
# config/settings/local.py
from config.settings.base import *  # noqa: F403

DEBUG = True
ALLOWED_HOSTS = ["localhost", "127.0.0.1"]

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }
}

EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"

# Django Debug Toolbar (solo en desarrollo)
INSTALLED_APPS += ["debug_toolbar"]  # noqa: F405
MIDDLEWARE = ["debug_toolbar.middleware.DebugToolbarMiddleware"] + MIDDLEWARE  # noqa: F405
INTERNAL_IPS = ["127.0.0.1"]
```

```python
# config/settings/production.py
from config.settings.base import *  # noqa: F403

DEBUG = False
ALLOWED_HOSTS = os.environ["ALLOWED_HOSTS"].split(",")

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.environ["DB_NAME"],
        "USER": os.environ["DB_USER"],
        "PASSWORD": os.environ["DB_PASSWORD"],
        "HOST": os.environ.get("DB_HOST", "localhost"),
        "PORT": os.environ.get("DB_PORT", "5432"),
    }
}

# Security hardening
SECURE_SSL_REDIRECT = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
```

**Regla**: `manage.py` y `wsgi.py` apuntan a `config.settings` (no a `config.settings.local`). El `__init__.py` decide cuál cargar según `DJANGO_ENVIRONMENT`.

### 4. Django Debug Toolbar (HTMX-safe)

DDT es esencial para detectar N+1 queries, tiempo de templates, y cache hits durante desarrollo. Pero **rompe HTMX**: la toolbar se inyecta en responses parciales y corrompe fragments que esperan `innerHTML` puro.

Configuración correcta — solo en `local.py`, y **nunca en respuestas HTMX ni API**:

```python
# config/settings/local.py (continuación)
def show_toolbar(request):
    """No inyectar toolbar en partials HTMX ni endpoints API."""
    from debug_toolbar.middleware import show_toolbar as default_show
    if request.headers.get("HX-Request"):
        return False
    if request.path.startswith("/api/"):
        return False
    return default_show(request)

DEBUG_TOOLBAR_CONFIG = {
    "SHOW_TOOLBAR_CALLBACK": show_toolbar,
}

DEBUG_TOOLBAR_PANELS = [
    "debug_toolbar.panels.history.HistoryPanel",
    "debug_toolbar.panels.versions.VersionsPanel",
    "debug_toolbar.panels.timer.TimerPanel",
    "debug_toolbar.panels.settings.SettingsPanel",
    "debug_toolbar.panels.headers.HeadersPanel",
    "debug_toolbar.panels.request.RequestPanel",
    "debug_toolbar.panels.sql.SQLPanel",
    "debug_toolbar.panels.profiling.ProfilingPanel",
]
```

```bash
# Instalación
pip install django-debug-toolbar
```

**Gotcha**: si usás django-ninja o DRF, los endpoints API también reciben HTML inyectado. El filtro `request.path.startswith("/api/")` lo previene.

### 5. Decimal siempre con strings

```python
from decimal import Decimal

# Bien
Decimal("0.00")
# Mal
Decimal(0.1)  # float pollution
```

### 6. app/ inicial con BaseModel

```python
# apps/core/apps.py
from django.apps import AppConfig

class CoreConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.core"
    verbose_name = "Core"
```

### 7. Estructura moderna con modelos en directorio

Para apps con más de 3 modelos:

```
project/
├── apps/
│   └── myapp/
│       ├── __init__.py
│       ├── apps.py
│       ├── admin/
│       │   ├── __init__.py
│       │   └── admin.py
│       ├── models/
│       │   ├── __init__.py
│       │   ├── __init__.py
│       │   └── mymodel.py
│       ├── urls.py
│       └── views.py
```

### 8. Sin side effects en save()

Los modelos NO crean otros modelos al guardarse. Las automatizaciones van a signals o servicios.

```python
# MAL: dentro del modelo
class Person(BaseModel):
    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if self.is_client:
            Deal.objects.create(person=self)  #side effect!

# BIEN: signal separada
@receiver(post_save, sender=Person)
def create_deal_for_client(sender, instance, created, **kwargs):
    if created and instance.is_client:
        Deal.objects.create(person=instance)
```

### 9. EncryptedCharField para secretos en base de datos

API keys, tokens OAuth, private keys de pasarelas de pago — nunca en texto plano en la DB. Si alguien obtiene un dump de la base de datos, los secretos deben estar encriptados.

Usá un campo Django custom con **Fernet** (AES-128-CBC simétrico). La clave de encriptación vive en variables de entorno, nunca en la DB.

```python
# apps/core/models/fields.py
from cryptography.fernet import Fernet
from django.conf import settings
from django.db import models
import os

class EncryptedTextField(models.TextField):
    """Field that encrypts data at rest using Fernet symmetric encryption."""

    description = "Encrypted text field using Fernet (AES-128-CBC)"

    def __init__(self, *args, **kwargs):
        kwargs["editable"] = kwargs.get("editable", True)
        super().__init__(*args, **kwargs)

    def get_prep_value(self, value):
        if value is None:
            return None
        fernet = Fernet(settings.FERNET_ENCRYPTION_KEY.encode())
        return fernet.encrypt(value.encode()).decode()

    def from_db_value(self, value, expression, connection):
        if value is None:
            return None
        fernet = Fernet(settings.FERNET_ENCRYPTION_KEY.encode())
        return fernet.decrypt(value.encode()).decode()

    def to_python(self, value):
        if value is None or isinstance(value, str):
            return value
        return self.from_db_value(value, None, None)
```

```python
# config/settings/base.py — clave de encriptación
FERNET_ENCRYPTION_KEY = os.environ.get("FERNET_ENCRYPTION_KEY")
if not FERNET_ENCRYPTION_KEY and DEBUG:
    # Auto-generar en desarrollo (NO en producción)
    FERNET_ENCRYPTION_KEY = Fernet.generate_key().decode()
    print(f"WARNING: auto-generated FERNET_ENCRYPTION_KEY. Set it in .env for persistence.")
```

```python
# apps/payments/models/gateway_config.py
from apps.core.models.base import BaseModel
from apps.core.models.fields import EncryptedTextField

class GatewayConfig(BaseModel):
    gateway = models.CharField(max_length=50)
    api_key = EncryptedTextField()          # ← Encriptado en DB
    webhook_secret = EncryptedTextField()   # ← Encriptado en DB

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["tenant", "gateway"], name="uq_tenant_gateway")
        ]
```

**Testing**: verificá que el valor en DB no sea texto plano:

```python
def test_api_key_encrypted_at_rest(db):
    config = GatewayConfig.objects.create(gateway="wompi", api_key="sk_test_abc123")
    raw = GatewayConfig.all_objects.raw(
        "SELECT api_key FROM payments_gatewayconfig WHERE id = %s", [config.id]
    )[0]
    assert "sk_test_abc123" not in raw.api_key  # No es texto plano
    assert config.api_key == "sk_test_abc123"    # Se desencripta al leer del ORM
```

**⚠️ Cuidado con el admin**: Django Admin mostrará el valor desencriptado en formularios. Para campos encriptados, usá `exclude` o un widget readonly que oculte el valor real:

```python
# apps/payments/admin/gateway_admin.py
class GatewayConfigAdmin(admin.ModelAdmin):
    exclude = ("api_key", "webhook_secret")  # No exponer en admin forms
```

### 10. Rate limiting con cache atómico

APIs públicas y webhooks necesitan rate limiting para evitar abuso. Usá `cache.incr()` que es atómico — sin race conditions.

```python
# apps/core/middleware.py
from django.core.cache import cache
from django.http import HttpResponse

class RateLimitMiddleware:
    """Rate limit requests per path and IP using atomic cache.incr()."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        # Rutas con límites específicos
        limits = {
            "/api/webhooks/": (60, 60),      # 60 requests por minuto
            "/api/ghl/query": (100, 60),     # 100 requests por minuto
        }

        for path_prefix, (max_requests, window_seconds) in limits.items():
            if request.path.startswith(path_prefix):
                client_ip = request.META.get("REMOTE_ADDR", "0.0.0.0")
                key = f"ratelimit:{path_prefix}:{client_ip}"

                count = cache.incr(key)
                if count == 1:
                    cache.expire(key, window_seconds)

                if count > max_requests:
                    return HttpResponse(
                        "Too many requests", status=429,
                        headers={"Retry-After": str(window_seconds)}
                    )

        return self.get_response(request)
```

**Por qué `cache.incr()` y no `cache.get()` + `cache.set()`**: `incr()` es atómico en Redis y LocMemCache. Con get+set, dos requests concurrentes pueden leer el mismo valor y ambos pasar el límite.

### 11. Decisiones de stack según contexto

| Si necesitas... | Usá (default) | Alternativa cuando escale |
|----------------|-----|---------|
| CRUDs, formularios, tablas, dashboards | HTMX + Alpine.js + Tailwind + django-cotton + **Preline UI** | — |
| Componentes UI reutilizables | django-cotton + Preline UI | `{% include %}` spaghetti, labb (wrapper frágil) |
| API para SPA externo/mobile | Django Ninja | DRF (más verboso) |
| Interactividad ligera (dropdowns, modals, tabs) | Alpine.js | React por 3 componentes |
| Actualizaciones parciales | HTMX | Fetch API manual |
| Pantalla con estado de cliente complejo (drag & drop, wizards, canvas) | **Inertia + PrimeVue** | React, Vue SPA separada |
| Background tasks (emails, reports, webhooks) | **django-q2** (ORM broker) | Celery + Redis (solo si necesitás +500 tasks/min) |
**Regla de oro:** Empezá server-side. "Graduá" a Inertia + PrimeVue **solo cuando una pantalla específica demuestre** que no puede resolverse con HTMX + Alpine.js.

**Regla de componentes:** Preferí `django-cotton` sobre `{% include %}` siempre que necesités reusar markup con props o slots. Preline UI te da los estilos base, cotton te da la encapsulación en templates.

**Regla de background tasks:** Empezá con `django-q2` y ORM broker. No agregues Celery + Redis **sin medición real de throughput**. `django-q2` usa tu DB existente como broker por defecto — cero infraestructura extra. Solo migrá a Celery cuando tengas >500 tasks por minuto o necesités encolamiento por prioridad.

---

## Frontend Stack: django-cotton + Preline UI + Tailwind

### Por qué este stack

**django-cotton** es a Django templates lo que los Web Components son al DOM: encapsulamiento, reutilización y composición sin salir del ecosistema server-side.

**Preline UI** es una biblioteca de componentes HTML + Tailwind madura, gratuita y con mejor cobertura de componentes complejos (modals, datepickers, steppers) que alternativas similares. Se integra limpiamente con Alpine.js para interactividad.

**Tailwind CSS** provee las utilidades base. Preline UI define las clases de componente. cotton encapsula el markup.

### Setup de un proyecto nuevo

```bash
# Instalar dependencias
pip install django-cotton
npm install -D tailwindcss @tailwindcss/cli preline

# Agregar a INSTALLED_APPS
INSTALLED_APPS = [
    "django_cotton",
    # ... tus apps
]

# Configurar templates
TEMPLATES = [{
    "BACKEND": "django.template.backends.django.DjangoTemplates",
    "DIRS": [BASE_DIR / "templates"],
    "APP_DIRS": True,
    "OPTIONS": {
        "context_processors": [
            # ... los tuyos
        ],
        "builtins": ["django_cotton.templatetags.cotton"],
    },
}]
```

### Estructura de componentes cotton

Los componentes se organizan en **subdirectorios por dominio funcional** — misma filosofía que la carpeta `models/` o `admin/` del backend. No por tipo técnico.

```
templates/
└── cotton/
    ├── ui/                       # Componentes base transversales (solo estos van aquí)
    │   ├── button.html
    │   ├── card.html
    │   ├── modal.html
    │   ├── alert.html
    │   └── input.html
    ├── layout/                   # Layouts de página
    │   ├── sidebar.html
    │   ├── header.html
    │   └── container.html
    ├── forms/                    # Componentes de formulario
    │   ├── field.html
    │   ├── label.html
    │   └── error.html
    ├── surveys/                  # Dominio: encuestas
    │   ├── header.html
    │   ├── footer.html
    │   ├── question_radio.html
    │   ├── question_checkbox.html
    │   └── _slider.html          # ← Prefijo _ = interno, no se usa directo
    ├── dashboard/                # Dominio: dashboards
    │   ├── stats_card.html
    │   ├── chart_container.html
    │   └── _filter_bar.html      # ← Interno, usado por stats_card
    └── general/                  # Solo para componentes usados en 2+ dominios
        ├── progress_bar.html
        └── _loading.html         # ← Interno, no se invoca standalone
```

**Reglas:**

1. **1 componente = 1 archivo**. No agrupes variantes en un mismo archivo.
2. **Subdirectorio por dominio**, no por tipo. `surveys/` no `inputs/` ni `cards/`. Misma lógica que `apps/surveys/models/` vs `apps/surveys/views/`.
3. **Prefijo `_` para componentes internos** que no se invocan directamente desde templates de página. Son reutilizados por otros componentes cotton dentro del mismo dominio. Ej: `_slider.html` solo se usa dentro de `question_*.html`.
4. **`general/`** para componentes usados en 2+ dominios distintos (progress_bar, loading).
5. **`ui/`** solo para componentes base que no pertenecen a ningún dominio (button, card, modal, input).
6. **Máximo 2 niveles** de profundidad. Si necesitás 3, el componente está mal diseñado.

### Patrones de componentes cotton

#### 1. Componente base con props y slot

```html
<!-- templates/cotton/ui/button.html -->
<button
  type="{{ type|default:'button' }}"
  class="inline-flex items-center justify-center gap-x-2 font-medium rounded-lg border border-transparent
    {% if variant == 'primary' %} bg-blue-600 text-white hover:bg-blue-700 focus:bg-blue-700 {% elif variant == 'secondary' %} bg-gray-100 text-gray-800 hover:bg-gray-200 dark:bg-neutral-700 dark:text-neutral-200 dark:hover:bg-neutral-600 {% elif variant == 'danger' %} bg-red-600 text-white hover:bg-red-700 {% elif variant == 'ghost' %} bg-transparent text-gray-600 hover:bg-gray-100 dark:text-neutral-400 dark:hover:bg-neutral-700 {% else %} bg-blue-600 text-white hover:bg-blue-700 {% endif %}
    {% if size == 'sm' %} px-3 py-2 text-sm {% elif size == 'lg' %} px-5 py-3 text-lg {% else %} px-4 py-3 text-sm {% endif %}"
  {% if disabled %}disabled{% endif %}
  {% if id %}id="{{ id }}"{% endif %}
  {% if hx_get %}hx-get="{{ hx_get }}"{% endif %}
  {% if hx_post %}hx-post="{{ hx_post }}"{% endif %}
  {% if hx_target %}hx-target="{{ hx_target }}"{% endif %}
  {% if hx_swap %}hx-swap="{{ hx_swap|default:'innerHTML' }}"{% endif %}
>
  {% if icon %}<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="{{ icon }}"></path></svg>{% endif %}
  {{ slot }}
</button>
```

```html
<!-- Uso -->
<c-ui.button variant="primary" size="lg" icon="M5 13l4 4L19 7">
  Guardar cambios
</c-ui.button>
```

#### 2. Componente con slots nombrados

```html
<!-- templates/cotton/ui/card.html -->
<div class="flex flex-col bg-white border border-gray-200 shadow-sm rounded-xl dark:bg-neutral-800 dark:border-neutral-700 {{ class|default:'' }}">
  {% if header %}
  <div class="px-6 py-4 border-b border-gray-200 dark:border-neutral-700">
    {{ header }}
  </div>
  {% endif %}
  <div class="p-6">
    {{ slot }}
  </div>
  {% if footer %}
  <div class="flex items-center justify-end gap-x-2 px-6 py-4 border-t border-gray-200 dark:border-neutral-700">
    {{ footer }}
  </div>
  {% endif %}
</div>
```

```html
<!-- Uso -->
<c-ui.card>
  <c-slot name="header">
    <h3 class="text-lg font-semibold text-gray-800 dark:text-white">Título</h3>
  </c-slot>
  <p class="text-gray-600 dark:text-neutral-400">Contenido del card...</p>
  <c-slot name="footer">
    <c-ui.button variant="primary">Aceptar</c-ui.button>
  </c-slot>
</c-ui.card>
```

#### 3. Modal con formulario (Alpine.js + HTMX)

```html
<!-- templates/cotton/ui/modal.html -->
<div
  x-data="{ open: false }"
  @keydown.escape.window="open = false"
  class="relative"
>
  <!-- Trigger -->
  <div @click="open = true">
    {{ trigger }}
  </div>

  <!-- Backdrop -->
  <div
    x-show="open"
    x-transition:enter="transition ease-out duration-300"
    x-transition:enter-start="opacity-0"
    x-transition:enter-end="opacity-100"
    x-transition:leave="transition ease-in duration-200"
    x-transition:leave-start="opacity-100"
    x-transition:leave-end="opacity-0"
    class="fixed inset-0 z-[80] bg-gray-900/50 backdrop-blur-sm"
    @click="open = false"
  ></div>

  <!-- Panel -->
  <div
    x-show="open"
    x-transition:enter="transition ease-out duration-300"
    x-transition:enter-start="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
    x-transition:enter-end="opacity-100 translate-y-0 sm:scale-100"
    x-transition:leave="transition ease-in duration-200"
    x-transition:leave-start="opacity-100 translate-y-0 sm:scale-100"
    x-transition:leave-end="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
    class="fixed inset-0 z-[80] flex items-center justify-center p-4"
  >
    <div
      class="bg-white dark:bg-neutral-800 border dark:border-neutral-700 rounded-xl shadow-xl w-full {{ class|default:'max-w-lg' }}"
      @click.stop
    >
      {% if header %}
      <div class="flex items-center justify-between px-6 py-4 border-b dark:border-neutral-700">
        <h3 class="text-lg font-semibold text-gray-900 dark:text-white">{{ header }}</h3>
        <button @click="open = false" class="text-gray-400 hover:text-gray-600 dark:hover:text-white">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>
        </button>
      </div>
      {% endif %}
      <div class="px-6 py-4">
        {{ slot }}
      </div>
      {% if footer %}
      <div class="flex items-center justify-end gap-2 px-6 py-4 border-t dark:border-neutral-700">
        {{ footer }}
      </div>
      {% endif %}
    </div>
  </div>
</div>
```

```html
<!-- Uso -->
<c-ui.modal header="Nueva encuesta">
  <c-slot name="trigger">
    <c-ui.button variant="primary">Crear encuesta</c-ui.button>
  </c-slot>

  <form
    id="survey-form"
    hx-post="{% url 'survey_create' %}"
    hx-target="#survey-list"
    hx-swap="beforeend"
    @htmx:after-request="if(event.detail.successful) open = false"
  >
    <c-forms.field label="Nombre" id="id_name">
      <input type="text" name="name" id="id_name" class="py-3 px-4 block w-full border-gray-200 rounded-lg text-sm focus:border-blue-500 focus:ring-blue-500 dark:bg-neutral-900 dark:border-neutral-700 dark:text-neutral-400" required>
    </c-forms.field>
  </form>

  <c-slot name="footer">
    <c-ui.button variant="ghost" @click="open = false">Cancelar</c-ui.button>
    <c-ui.button variant="primary" type="submit" form="survey-form">Guardar</c-ui.button>
  </c-slot>
</c-ui.modal>
```

#### 4. Componente de formulario

```html
<!-- templates/cotton/forms/field.html -->
<div class="w-full mb-4 {{ class|default:'' }}">
  {% if label %}
  <label class="block text-sm font-medium mb-1 text-gray-700 dark:text-neutral-300" for="{{ id }}">
    {{ label }}
  </label>
  {% endif %}
  {{ slot }}
  {% if help_text %}
  <p class="mt-1 text-sm text-gray-500 dark:text-neutral-500">{{ help_text }}</p>
  {% endif %}
  {% if error %}
  <p class="mt-1 text-sm text-red-600 dark:text-red-400">{{ error }}</p>
  {% endif %}
</div>
```

```html
<!-- Uso con Django forms -->
<c-forms.field label="Nombre" id="id_name" error="{{ form.name.errors|first }}">
  <input
    type="text"
    name="name"
    id="id_name"
    value="{{ form.name.value|default:'' }}"
    class="py-3 px-4 block w-full border-gray-200 rounded-lg text-sm focus:border-blue-500 focus:ring-blue-500 dark:bg-neutral-900 dark:border-neutral-700 dark:text-neutral-400"
  >
</c-forms.field>
```

### Configuración de Tailwind + Preline UI

```css
/* static/css/main.css */
@import "tailwindcss";
@import "preline/preline.css";

/* Tu tema custom */
@theme {
  --color-primary: #F97316;
  --color-secondary: #3B82F6;
}
```

### Inicialización de Preline JS

Preline requiere inicialización de componentes JS. En tu `base.html`:

```html
<!-- templates/base.html -->
<!DOCTYPE html>
<html lang="es" class="light">
<head>
  <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
  <link rel="stylesheet" href="{% static 'css/dist.css' %}">
</head>
<body class="bg-gray-50 dark:bg-neutral-900">
  {% block content %}{% endblock %}

  <!-- Preline JS -->
  <script src="{% static 'js/preline.js' %}"></script>
  <script>
    document.addEventListener('DOMContentLoaded', () => {
      HSStaticMethods.autoInit();
    });
    // Re-inicializar cuando HTMX carga contenido nuevo
    document.body.addEventListener('htmx:afterSwap', () => {
      HSStaticMethods.autoInit();
    });
  </script>
</body>
</html>
```

**Nota:** `HSStaticMethods.autoInit()` es obligatorio cuando cargás componentes Preline vía HTMX dinámicamente.

### Migración desde `{% include %}`

| Antes (include) | Después (cotton) |
|----------------|-----------------|
| `{% include "button.html" with text="Guardar" clase="primary" %}` | `<c-ui.button variant="primary">Guardar</c-ui.button>` |
| `{% include "card.html" with title="Hola" body="Mundo" %}` | `<c-ui.card><c-slot name="header">Hola</c-slot>Mundo</c-ui.card>` |
| Strings escapados como props | Slots reales con HTML |
| `{% include "modal.html" with content=modal_content %}` | `<c-ui.modal>Contenido HTML real</c-ui.modal>` |

---

## Patrones que DEPENDEN del contexto

### 1. Multitenant con Organization

Para **SaaS multi-tenant** (muchas organizaciones):

```python
# apps/accounts/models/organization.py
from django.db import models
from django.utils.text import slugify
from apps.core.models.base import BaseModel

class Organization(BaseModel):
    name = models.CharField(max_length=255)
    slug = models.SlugField(max_length=255, unique=True)

    # Configuración
    settings = models.JSONField(default=dict)
    is_active = models.BooleanField(default=True)

    # Branding (opcional)
    logo = models.ImageField(upload_to="org_logos/", null=True, blank=True)
    primary_color = models.CharField(max_length=7, default="#F97316")

    def save(self, *args, **kwargs):
        if not self.slug:
            self.slug = slugify(self.name)
        super().save(*args, **kwargs)
```

Para **un solo tenant** (una sola empresa):
- NO necesitas Organization como modelo separada
- User tiene ForeignKey a Organization null=True
- Puedes simplificar a un solo tenant

### 2. User con email login

Para **auth con email**:

```python
# apps/accounts/models/user.py
import uuid
from django.contrib.auth.models import AbstractUser
from django.db import models
from apps.core.models.base import BaseModel

class User(BaseModel, AbstractUser):
    username = None  # Removed

    organization = models.ForeignKey(
        "accounts.Organization",
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="users"
    )
    email = models.EmailField(unique=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["first_name", "last_name"]

    @property
    def full_name(self):
        return f"{self.first_name} {self.last_name}".strip()
```

Para **username clásico** (menos común):
- Simplemente usa AbstractUser por defecto
- No necesitas cambiar USERNAME_FIELD

### 3. TenantMiddleware para filtering automático

Para **SaaS multitenant con filtering automático**:

```python
# apps/core/models/tenant.py
import threading
thread_local = threading.local()

def get_current_organization():
    return getattr(thread_local, "current_organization", None)

def set_current_organization(org):
    thread_local.current_organization = org
```

```python
# apps/core/middleware.py
from apps.core.models import set_current_organization

class TenantMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if hasattr(request, "user") and request.user.is_authenticated:
            set_current_organization(request.user.organization)
        else:
            set_current_organization(None)

        response = self.get_response(request)
        set_current_organization(None)  # Cleanup
        return response
```

```python
# apps/core/models/tenant.py (continuación)
class TenantQuerySet(models.QuerySet):
    def for_current_organization(self):
        org = get_current_organization()
        if org is None:
            return self.none()
        return self.filter(organization=org)

    def with_global(self):
        """Return global objects OR current org's objects."""
        org = get_current_organization()
        if org is None:
            return self.filter(is_global=True)
        return self.filter(Q(is_global=True) | Q(organization=org))

class TenantManager(models.Manager):
    def get_queryset(self):
        return TenantQuerySet(self.model, using=self._db)

    def for_current_organization(self):
        return self.get_queryset().for_current_organization()

class TenantMixin(models.Model):
    organization = models.ForeignKey(Organization, on_delete=models.CASCADE)
    is_global = models.BooleanField(default=False)

    class Meta:
        abstract = True
```

Para **un solo tenant**:
- NO necesitas TenantMiddleware
- NO necesitas filtrado automático por organización
- Queries son más simples

### 4. Catálogo unificado con is_global

Para **muchas organizaciones con templates compartidos**:

```python
# apps/catalog/models/evaluation.py
class EvaluationType(BaseTextChoices):
    ASSESSMENT_360 = "ASSESSMENT_360", "Evaluación 360°"
    PULSE_SURVEY = "PULSE_SURVEY", "Encuesta de Pulso"

class Evaluation(BaseModel):
    name = models.CharField(max_length=255)
    slug = models.SlugField(max_length=255)
    type = models.CharField(max_length=20, choices=EvaluationType.choices)

    is_global = models.BooleanField(default=False)
    organization = models.ForeignKey(Organization, null=True, blank=True)
    parent = models.ForeignKey("self", null=True, blank=True)  # Custom versions

    is_active = models.BooleanField(default=True)
    config = models.JSONField(default=dict)

    def is_visible_to(self, organization):
        if self.is_global:
            return True
        return self.organization_id == organization.id
```

Para **un solo tenant**:
- NO necesitas is_global (usa organization nullable)
- NO necesitas parent para custom versions
- Simpler: solo una evaluación por tipo

### 5. Domain layer pura (dataclasses frozen, calculadoras sin Django)

Para lógica de negocio compleja (cálculos financieros, pricing, scoring), separá la lógica pura de los modelos Django. Usá **dataclasses frozen** — inmutables, sin side effects, 100% testeables sin DB.

```python
# apps/quoting/domain/pricing.py
from dataclasses import dataclass, field
from decimal import Decimal

@dataclass(frozen=True)
class PriceBreakdown:
    """Immutable price calculation result."""
    subtotal: Decimal
    iva: Decimal
    total: Decimal
    iva_rate: Decimal = Decimal("0.19")

    @property
    def iva_amount(self) -> Decimal:
        return self.subtotal * self.iva_rate

@dataclass(frozen=True)
class QuoteFinancials:
    items_total: Decimal
    labor_total: Decimal
    materials_total: Decimal
    markup_percent: Decimal = Decimal("0")
    discount_percent: Decimal = Decimal("0")

    @property
    def subtotal(self) -> Decimal:
        return self.items_total + self.labor_total + self.materials_total

    @property
    def markup_amount(self) -> Decimal:
        return self.subtotal * (self.markup_percent / Decimal("100"))

    @property
    def grand_total(self) -> Decimal:
        marked_up = self.subtotal + self.markup_amount
        discount = marked_up * (self.discount_percent / Decimal("100"))
        return marked_up - discount
```

```python
# apps/quoting/domain/pricing.py (continuación)
@dataclass(frozen=True)
class ExecutionQuoteItemCalculator:
    """Pure calculator for a single execution quote item. Zero Django imports."""

    unit_cost: Decimal
    quantity: Decimal
    margin_percent: Decimal = Decimal("30")
    iva_rate: Decimal = Decimal("0.19")

    def calculate(self) -> PriceBreakdown:
        subtotal = self.unit_cost * self.quantity
        iva = subtotal * self.iva_rate
        total = subtotal * (1 + self.margin_percent / Decimal("100")) + iva
        return PriceBreakdown(subtotal=subtotal, iva=iva, total=total, iva_rate=self.iva_rate)
```

**Testing sin DB**:

```python
def test_calculator_pure_logic():
    calc = ExecutionQuoteItemCalculator(
        unit_cost=Decimal("100"), quantity=Decimal("5"), margin_percent=Decimal("30")
    )
    result = calc.calculate()
    assert result.subtotal == Decimal("500")
    assert result.iva == Decimal("95")
    assert result.total > Decimal("500")  # Con margen
```

**Regla**: Si un archivo en `domain/` importa `from django.db import models` o `from apps.*.models import *`, está mal ubicado. El domain layer **nunca** toca el ORM.

### 6. Snapshot pattern (congelar datos al cambiar de estado)

Cuando un registro cambia de estado (cotización → aprobada, orden → confirmada), ciertos valores de configuración deben congelarse para siempre. Si la tasa de IVA cambia mañana, las cotizaciones de hoy no deberían verse afectadas.

```python
# apps/quoting/models/base_quote.py
class BaseQuote(BaseModel):
    STATUS_DRAFT = "draft"
    STATUS_SENT = "sent"
    STATUS_APPROVED = "approved"

    status = models.CharField(max_length=20, default=STATUS_DRAFT)

    # Valores "vivos" — se actualizan con GlobalConfiguration
    iva_rate = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal("0.19"))

    # Snapshots — se congelan al aprobar/enviar
    iva_rate_snapshot = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    markup_snapshot = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    approved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        abstract = True

    def approve(self):
        """Freeze current rates as snapshots."""
        self.status = self.STATUS_APPROVED
        self.iva_rate_snapshot = self.iva_rate
        self.markup_snapshot = GlobalConfiguration.get_solo().default_markup
        self.approved_at = timezone.now()
        self.save(update_fields=["status", "iva_rate_snapshot", "markup_snapshot", "approved_at"])
```

**Cuándo usarlo**: cotizaciones, órdenes de compra, facturas, contratos — cualquier documento financiero donde los parámetros del momento de emisión deben ser inmutables.

### 7. Singleton model con cache

Configuración global que rara vez cambia pero se lee en cada request. Usá un modelo singleton + cache para evitar pegarle a la DB constantemente.

```python
# apps/core/models/global_configuration.py
from django.core.cache import cache
from django.db import models
from apps.core.models.base import BaseModel

class GlobalConfiguration(BaseModel):
    """Singleton — solo existe UNA fila en esta tabla."""
    default_markup = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal("30"))
    default_iva = models.DecimalField(max_digits=5, decimal_places=2, default=Decimal("0.19"))
    company_name = models.CharField(max_length=255)
    email_notifications_enabled = models.BooleanField(default=True)

    CACHE_KEY = "global_configuration"
    CACHE_TTL = 3600  # 1 hora

    def save(self, *args, **kwargs):
        self.pk = 1  # Forzar singleton
        super().save(*args, **kwargs)
        cache.set(self.CACHE_KEY, self, self.CACHE_TTL)

    @classmethod
    def get_solo(cls):
        """Obtener la única instancia, desde cache si está disponible."""
        cached = cache.get(cls.CACHE_KEY)
        if cached is not None:
            return cached
        obj, _ = cls.objects.get_or_create(pk=1)
        cache.set(cls.CACHE_KEY, obj, cls.CACHE_TTL)
        return obj
```

**Invalida el cache cuando cambia** — el `save()` sobreescrito lo hace automáticamente. Para cambios vía `update()`, usá `cache.delete(GlobalConfiguration.CACHE_KEY)`.

### 8. Calculator pattern (calculadoras stateless por entidad)

Para lógica de pricing/scoring con múltiples estrategias, usá calculadoras stateless — una clase por estrategia, sin estado interno. El modelo de configuración decide cuál instanciar.

```python
# apps/evaluations_360/services/calculators.py
from dataclasses import dataclass
from decimal import Decimal
from abc import ABC, abstractmethod

@dataclass(frozen=True)
class ScoreResult:
    raw: Decimal
    normalized: Decimal  # 0-100
    weighted: Decimal    # Con peso del rol aplicado

class ScoreCalculator(ABC):
    @abstractmethod
    def calculate(self, scores: list[Decimal], weight: Decimal = Decimal("1")) -> ScoreResult: ...

class SimpleAverageCalculator(ScoreCalculator):
    def calculate(self, scores, weight=Decimal("1")):
        avg = sum(scores, Decimal("0")) / len(scores)
        return ScoreResult(raw=avg, normalized=avg, weighted=avg * weight)

class WeightedAverageCalculator(ScoreCalculator):
    def __init__(self, weights: list[Decimal]):
        self.weights = weights

    def calculate(self, scores, weight=Decimal("1")):
        weighted_sum = sum(s * w for s, w in zip(scores, self.weights), Decimal("0"))
        total_weight = sum(self.weights, Decimal("0"))
        avg = weighted_sum / total_weight if total_weight else Decimal("0")
        return ScoreResult(raw=avg, normalized=avg, weighted=avg * weight)
```

**Dispatcher** — el modelo de configuración decide qué calculadora usar:

```python
# apps/evaluations_360/services/scoring_engine.py
class ConfigurableScoringEngine:
    CALCULATORS = {
        "simple_avg": SimpleAverageCalculator,
        "weighted_avg": WeightedAverageCalculator,
    }

    def __init__(self, scoring_config):
        self.config = scoring_config

    def get_calculator(self) -> ScoreCalculator:
        calc_class = self.CALCULATORS[self.config.method]
        if self.config.method == "weighted_avg":
            role_weights = [rw.weight for rw in self.config.role_weights.all()]
            return calc_class(role_weights)
        return calc_class()
```

### 9. Conditional UniqueConstraint

Constraints que varían según el valor de otro campo. Útil para modelos multi-tenant donde algunos registros son globales y otros pertenecen a una organización.

```python
# apps/catalog/models/tag.py
from django.db import models
from django.db.models import Q

class Tag(BaseModel):
    name = models.CharField(max_length=100)
    organization = models.ForeignKey("accounts.Organization", null=True, blank=True,
                                      on_delete=models.CASCADE)
    is_global = models.BooleanField(default=False)

    class Meta:
        constraints = [
            # Tags globales: nombre único (sin organización)
            models.UniqueConstraint(
                fields=["name"],
                condition=Q(is_global=True),
                name="uq_tag_global_name"
            ),
            # Tags por organización: nombre único dentro de la org
            models.UniqueConstraint(
                fields=["name", "organization"],
                condition=Q(is_global=False),
                name="uq_tag_org_name"
            ),
        ]
```

**Cuándo usarlo**: cualquier modelo donde la unicidad depende del scope (global vs tenant, activo vs inactivo, draft vs published).

### 10. django-q2 con ORM broker (configuración completa)

`django-q2` es una cola de tareas distribuida multiproceso para Django, más madura que `django.tasks` y más simple que Celery. Soporta múltiples brokers (ORM, Redis, IronMQ, SQS), tareas Schedule con cron, chaining, y admin propio.

```python
# config/settings/base.py
Q_CLUSTER = {
    "name": "finance-manager",
    "workers": 4,
    "recycle": 500,
    "timeout": 60,
    "retry": 120,
    "max_attempts": 3,
    "compress": True,
    "save_limit": 250,
    "queue_limit": 500,
    "cpu_affinity": 1,
    "label": "Django Q2",
    "orm": "default",  # Usa la DB existente como broker — cero infra extra
}
```

```bash
# Migración necesaria (crea las tablas django_q_*)
pip install django-q2
python manage.py migrate
```

```python
# apps/notifications/tasks.py
from django_q.tasks import async_task

def send_welcome_email(user_id: int):
    from apps.accounts.models import User
    user = User.objects.get(id=user_id)
    user.email_user("Bienvenido", "Gracias por registrarte.")

def process_payment_webhook(payment_intent_id: int):
    from apps.payments.services.orchestrator import PaymentOrchestrator
    PaymentOrchestrator.process(payment_intent_id)
```

```python
# Uso en views — fire-and-forget, no bloquea
from django_q.tasks import async_task

def register_view(request):
    user = User.objects.create(...)
    async_task("apps.notifications.tasks.send_welcome_email", user_id=user.id)
    return redirect("dashboard")
```

**Tareas Schedule (cron-like):**

```python
# apps/tasks/schedules.py — se llama desde apps.py o migration
from django_q.models import Schedule

def setup_schedules():
    Schedule.objects.get_or_create(
        name="process-scheduled-transactions",
        defaults={
            "func": "apps.tasks.scheduled_transactions.process",
            "schedule_type": Schedule.CRON,
            "cron": "0 * * * *",  # Cada hora
            "repeats": -1,  # Indefinido
        },
    )
    Schedule.objects.get_or_create(
        name="update-exchange-rates",
        defaults={
            "func": "apps.tasks.exchange_rates.update",
            "schedule_type": Schedule.CRON,
            "cron": "0 6 * * *",  # Diario a las 6 AM
            "repeats": -1,
        },
    )
```

**Worker** (proceso separado):

```bash
# Desarrollo — polling cada segundo
python manage.py qcluster

# Producción — con workers específicos
python manage.py qcluster --timeout 300
```

**Brokers disponibles**:

| Broker | Infra | Para |
|--------|-------|------|
| `"orm": "default"` | Nada | MVP, desarrollo, proyectos medianos |
| `"redis": {"host": ..., "port": 6379}` | Redis | Producción con alto throughput |
| `"iron_mq"` o `"sqs"` | Externo | Cloud-native, escalado horizontal |

**Retries y manejo de errores**:

```python
# Config global en Q_CLUSTER
Q_CLUSTER = {
    "max_attempts": 3,     # Reintentos automáticos
    "retry": 120,          # Tiempo antes de marcar como fallido (segundos)
    "timeout": 60,         # Timeout por tarea (segundos)
}

# Por tarea individual vía hook
def on_failure(task):
    import structlog
    log = structlog.get_logger()
    log.error("task_failed", task_id=task.id, func=task.func, result=task.result)
    # Crear Alert para el usuario si es crítico

async_task("apps.tasks.exchange_rates.update", hook=on_failure, task_name="update-rates")
```

**Migración desde Celery**:

```bash
# Quitás todo esto:
# - celery.py
# - celerybeat schedule
# - Redis config (si no lo necesitás para otra cosa)
# - docker-compose celery + celery-beat services

# Agregás solo:
pip install django-q2
python manage.py migrate  # Crea django_q_schedule, django_q_task
```

**Ventaja clave sobre Celery**: API más simple, schedules nativos sin beat, admin integrado, y ORM broker que no requiere Redis para empezar. Solo migrá a Redis cuando el throughput lo justifique.

---

## Patrones que NO VAN (específicos de tests-360)

Estos patrones son específicos del proyecto tests-360 (evaluaciones 360 + encuestas de pulso SaaS). No aplicarlos en otros proyectos.

### 1. TenantMiddleware + TenantMixin completos

Solo para **SaaS multitenant con evaluación de organizaciones**.

### 2. Assignment con EvaluationRole

Solo para **evaluaciones 360 con roles definidos**:

```python
# apps/evaluations_360/models/assignment.py
class EvaluationRole(BaseModel, models.TextChoices):
    SELF = "SELF", "Autoevaluación"
    BOSS = "BOSS", "Jefe"
    PEER = "PEER", "Par"
    SUBORDINATE = "SUBORDINATE", "Persona a Cargo"
    OTHER_AREA = "OTHER_AREA", "Otra Área"
    CUSTOMER = "CUSTOMER", "Cliente"
    CUSTOMER_1 = "CUSTOMER_1", "Cliente 1"
    CUSTOMER_2 = "CUSTOMER_2", "Cliente 2"

class Assignment(BaseModel):
    cycle = models.ForeignKey(EvaluationCycle)
    evaluator = models.ForeignKey(User, related_name="evaluations_given")
    evaluatee = models.ForeignKey(User, related_name="evaluations_received")
    role = models.CharField(max_length=20, choices=EvaluationRole.choices)
    code = models.UUIDField(default=uuid.uuid4, unique=True)
```

### 3. Question con show_on_* booleans

Solo para **evaluaciones donde cada pregunta tiene visibilidad por rol**:

```python
# apps/catalog/models/question.py
class Question(BaseModel):
    # Visibilidad por rol
    show_on_self = models.BooleanField(default=True)
    show_on_boss = models.BooleanField(default=False)
    show_on_peers = models.BooleanField(default=False)
    show_on_subordinates = models.BooleanField(default=False)
    show_on_other_area = models.BooleanField(default=False)
    show_on_customers = models.BooleanField(default=False)
```

### 4. Survey + SurveyResponse para pulse

Solo para **encuestas de pulso con anonymeidad**:

```python
# apps/pulse_surveys/models/survey.py
class Survey(BaseModel):
    is_anonymous = models.BooleanField(default=False)
    allow_partial = models.BooleanField(default=True)
    code = models.UUIDField(default=uuid.uuid4, unique=True)

# apps/pulse_surveys/models/survey_response.py
class SurveyResponse(BaseModel):
    survey = models.ForeignKey(Survey)
    user = models.ForeignKey(User, null=True)  # Null if anonymous
    value_raw = models.IntegerField()
    value_normalized = models.IntegerField()  # For inverted items
```

### 5. Segment con factor + jerarquía

Solo para **evaluaciones organizadas por categorías**:

```python
# apps/catalog/models/segment.py
class FactorType(BaseTextChoices):
    EXTERNO = "EXTERNO", "Factor Externo"
    INDIVIDUAL = "INDIVIDUAL", "Factor Individual"

class Segment(BaseModel):
    factor = models.CharField(max_length=20, choices=FactorType.choices)
    parent = models.ForeignKey("self", null=True, blank=True)  # Jerarquía
```

### 6. Management command seed con datos demo

Solo para **proyectos con datos de prueba necesarios**:

```python
# apps/management/commands/seed.py
from django.core.management.base import BaseCommand

class Command(BaseCommand):
    help = "Seed database with sample data"

    def add_arguments(self, parser):
        parser.add_argument("--demo", action="store_true")

    def handle(self, *args, **options):
        # Create org, users, evaluations, cycles
        pass
```

---

## Commands

```bash
# Verificar consistencia de versiones
cat .python-version && grep pythonVersion pyrightconfig.json 2>/dev/null || true

# Verificar BaseModel
ls apps/core/models/base.py && grep "class BaseModel" apps/core/models/base.py

# Verificar multitenant (si es SaaS)
ls apps/core/middleware.py apps/core/models/tenant.py

# Verificar Organization
ls apps/accounts/models/organization.py

# Verificar configuración de database
grep -E "DATABASES|DB_" config/settings.py .env.example

# Verificar frontend stack
ls templates/cotton/ 2>/dev/null || echo "No cotton components yet"
grep "django_cotton" config/settings.py 2>/dev/null || echo "cotton not in INSTALLED_APPS"
grep "preline" package.json 2>/dev/null && echo "preline installed" || echo "preline not found"

# Formatear y lintear (si está configurado)
ruff format . 2>/dev/null || true
ruff check --select I --fix . 2>/dev/null || true

# Correr tests
pytest 2>/dev/null || python manage.py test

# Seedear datos demo
python manage.py seed --demo 2>/dev/null || echo "No seed command"

# Migraciones
python manage.py makemigrations
python manage.py migrate

# Build CSS (Tailwind + Preline UI)
npx @tailwindcss/cli -i static/css/main.css -o static/css/dist.css --watch  # watch mode
npx @tailwindcss/cli -i static/css/main.css -o static/css/dist.css          # build once

# Verificar settings por ambiente
ls config/settings/__init__.py config/settings/base.py config/settings/local.py config/settings/production.py 2>/dev/null || echo "Single settings.py"

# Verificar Django Debug Toolbar
grep "debug_toolbar" config/settings/local.py 2>/dev/null && echo "DDT configured" || echo "DDT not configured"

# Verificar EncryptedCharField
grep -r "EncryptedTextField\|EncryptedCharField" apps/ 2>/dev/null && echo "EncryptedField found" || echo "No encrypted fields"

# Verificar rate limiting middleware
grep -r "RateLimitMiddleware\|cache.incr" apps/ 2>/dev/null && echo "Rate limiting found" || echo "No rate limiting"

# Verificar django-q2
grep -r "Q_CLUSTER\|django-q2\|django_q" config/settings/ apps/ 2>/dev/null && echo "django-q2 configured" || echo "No django-q2 config"

# Verificar domain layer
ls apps/*/domain/*.py 2>/dev/null && echo "Domain layer found" || echo "No domain/ directory"

# Verificar pre-commit
ls .pre-commit-config.yaml 2>/dev/null && echo "pre-commit configured" || echo "No pre-commit hooks"

# Verificar conditional unique constraints
grep -r "UniqueConstraint.*condition" apps/ 2>/dev/null && echo "Conditional constraints found" || echo "No conditional constraints"
```

---

## Checklist para proyectos nuevos

| checks | Descripción |
|--------|-------------|
| `.python-version` y `pyrightconfig.json` coinciden |
| `DEBUG` lee de env var, default `False` |
| `.env` en `.gitignore`, `.env.example` versionado |
| `BaseModel` con soft delete y dos managers |
| `SECRET_KEY` explota si no está en env |
| Decimal usa strings, no floats |
| Database configurable vía env |
| ruff y pyright en dev dependencies (recomendado) |
| pytest configurado (recomendado) |
| **django-cotton** en `INSTALLED_APPS` |
| **Tailwind CSS** + **Preline UI** configurados |
| Carpeta `templates/cotton/` con componentes base (button, card, alert, input, modal) |
| `HSStaticMethods.autoInit()` configurado en base.html |
| Event listener `htmx:afterSwap` para reinicializar Preline |
| `builtins` configurado en `TEMPLATES` para cotton (opcional pero recomendado) |
| Componentes cotton organizados por dominio con prefijo `_` para internos |
| Settings por ambiente (`config/settings/{base,local,production}.py`) |
| `pre-commit` configurado (ruff + mypy + djlint) |
| Django Debug Toolbar instalado y configurado con `SHOW_TOOLBAR_CALLBACK` para HTMX |
| `django-q2` configurado (ORM broker para dev/prod, Redis opcional para alto throughput) |
| `FERNET_ENCRYPTION_KEY` set en `.env` (auto-generada en dev) |

---

## Checklist para proyectos SaaS multilenant

| checks | Descripción |
|--------|-------------|
| Organization como modelo con branding |
| User con email login (USERNAME_FIELD = "email") |
| TenantMiddleware seteando current org |
| TenantManager + TenantMixin |
| get_current_organization() disponible |
| MIDDLEWARE incluye TenantMiddleware |
| is_global booleano en modelos tenant |
| Organization.settings como JSONField |
| Conditional UniqueConstraints para modelos con `is_global` vs por tenant |
| `EncryptedCharField` para secretos (API keys, tokens) en modelos de gateway |
| Rate limiting en endpoints públicos (webhooks, API) |

---

## Checklist para proyectos en curso (tests-360 example)

| checks | Descripción |
|--------|-------------|
| TenantMiddleware en MIDDLEWARE |
| TenantManager y TenantMixin existentes |
| Organization con branding |
| Organization con email config |
| User con email login |
| User con autologin_token |
| Evaluation con is_global |
| Evaluation con type |
| EvaluationCycle existente |
| Assignment con roles |
| Question con show_on_* |
| Survey con is_anonymous |
| Admin Unfold configurado |
| Inlines para relations |
| seed command existe |
| **django-cotton** instalado y en `INSTALLED_APPS` |
| **Preline UI** + **Tailwind** configurados |
| `HSStaticMethods.autoInit()` + listener `htmx:afterSwap` en base.html |
| Componentes base de cotton creados (button, card, alert, input, modal) |
| Componentes organizados por dominio con prefijo `_` para internos |
| Templates migrados de `{% include %}` a cotton donde aplica |
| `django-q2` reemplazando Celery si no hay necesidad de +500 tasks/min |
| `EncryptedCharField` en modelos con secretos (API keys, webhook secrets) |
| Rate limiting en endpoints públicos |
| Domain layer separado (`domain/` sin imports Django) para lógica de negocio compleja |
| Calculator pattern si hay múltiples estrategias de cálculo |
| Settings por ambiente (no `if DEBUG` en un solo archivo) |

---

## Testing: pytest + Playwright

### Regla general

| Tipo de proyecto | Testing |
|-----------------|---------|
| **Solo backend** (API REST, Django admin) | pytest nomás |
| **Backend + frontend** (HTMX, templates, SPA) | pytest + Playwright |

Ambos deben estar configurados desde el día 1. No los agregues al final.

### pytest (siempre)

```ini
# pytest.ini
DJANGO_SETTINGS_MODULE = config.settings
python_files = test_*.py *_test.py
addopts = -v --tb=short
```

```python
# apps/accounts/tests/test_models.py
import pytest
from apps.accounts.models import Organization

@pytest.mark.django_db
def test_organization_creates_slug():
    org = Organization.objects.create(name="Mi Empresa")
    assert org.slug == "mi-empresa"
```

**Qué testear:**
- **Models**: `__str__`, `save()`, properties, constraints únicos
- **Views**: status codes, context, redirects, permisos
- **Seeders**: datos creados correctamente, cantidades
- **HTMX responses**: `HX-Redirect`, partials, status codes

### Playwright (cuando hay frontend)

```bash
pip install pytest-playwright
playwright install chromium
```

```python
# tests/test_evaluation.py
import pytest
from playwright.sync_api import Page

@pytest.mark.playwright
def test_user_can_start_evaluation(page: Page, live_server):
    page.goto(f"{live_server.url}/evaluate/360/{code}/")
    page.click("text=Comenzar evaluación")
    page.wait_for_selector(".card-title")
    assert page.is_visible(".progress")
```

**Qué testear con Playwright:**
- **Flujos completos**: start → answer all questions → done
- **Auto-save**: responder, recargar, verificar que persiste
- **Modal**: abrir, llenar, submit, verificar redirect
- **Responsive**: probar en viewport mobile
- **HTMX interactions**: clicks que disparan hx-get/hx-post

### Estructura de tests

```
tests/
├── conftest.py              # Fixtures compartidos
├── test_*.py                # Tests de integración
└── apps/
    ├── accounts/
    │   └── tests/
    │       ├── test_models.py
    │       └── test_views.py
    ├── catalog/
    │   └── tests/
    └── evaluations_360/
        └── tests/
```

### Commands

```bash
pytest                          # Todos los tests
pytest -k "model"               # Solo tests de modelos
pytest -m playwright            # Solo tests de navegador
pytest --lf                     # Solo los que fallaron
pytest --cov=apps               # Cobertura
playwright show-trace trace.zip # Debug de tests failed
```

- **Guía completa**: See [assets/startup-guide.md](assets/startup-guide.md) for the full startup guide with detailed explanations, patterns, and conventions.
- **django-cotton**: [django-cotton.com](https://django-cotton.com) — Componentes reutilizables en templates Django
- **Preline UI**: [preline.co](https://preline.co) — Biblioteca de componentes HTML + Tailwind
- **Tailwind CSS**: [tailwindcss.com](https://tailwindcss.com) — Framework CSS utilitario
- **HTMX**: [htmx.org](https://htmx.org) — Interactividad server-side sin JavaScript complejo
- **Alpine.js**: [alpinejs.dev](https://alpinejs.dev) — Reactividad ligera para componentes que la necesiten
- **Inertia.js**: [inertiajs.com](https://inertiajs.com) — Adaptador SPA sin API REST (cuando el server-side no alcance)
- **PrimeVue**: [primevue.org](https://primevue.org) — Componentes Vue para Inertia (cuando se justifique la SPA)

## Nota sobre wrappers de terceros

**NO uses labb ni wrappers similares.** Son dependencias frágiles con poca adopción que añaden una capa sin valor real. Instalá django-cotton, Tailwind y Preline UI por separado. En 1-2 días tenés tu propio kit de componentes sin depender de un repo con 80 estrellas.