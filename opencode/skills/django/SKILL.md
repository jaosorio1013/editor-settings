---
name: django
description: >
  Guía para proyectos Django modernos. Incluye patrones universales que aplican a cualquier
  proyecto, patrones condicionales para SaaS multitenant, y auditoría de proyectos en curso.
  Para nuevos proyectos y proyectos existentes.
license: Apache-2.0
metadata:
  author: gentleman-programming
  version: "2.0"
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
- Scaffolding de una nueva app dentro de un proyecto Django existente
- Revisando la estructura de un proyecto Django para alinearlo con buenas prácticas
- Auditando un proyecto en curso para verificar patrones multitenant
- Identificando qué falta para completar una implementación SaaS
- Decidiendo stack frontend (HTMX vs API vs SPA) para un proyecto Django
- Configurando testing, linting, o tooling de un proyecto Django

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

### 3. Decimal siempre con strings

```python
from decimal import Decimal

# Bien
Decimal("0.00")
# Mal
Decimal(0.1)  # float pollution
```

### 4. app/ inicial con BaseModel

```python
# apps/core/apps.py
from django.apps import AppConfig

class CoreConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.core"
    verbose_name = "Core"
```

### 5. Estructura moderna con modelos en directorio

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

### 6. Sin side effects en save()

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

### 7. Decisiones de stack según contexto

| Si necesitas... | Usá (default) | Alternativa cuando escale |
|----------------|-----|---------|
| CRUDs, formularios, tablas, dashboards | HTMX + Alpine.js + Tailwind + django-cotton + **Preline UI** | — |
| Componentes UI reutilizables | django-cotton + Preline UI | `{% include %}` spaghetti, labb (wrapper frágil) |
| API para SPA externo/mobile | Django Ninja | DRF (más verboso) |
| Interactividad ligera (dropdowns, modals, tabs) | Alpine.js | React por 3 componentes |
| Actualizaciones parciales | HTMX | Fetch API manual |
| Pantalla con estado de cliente complejo (drag & drop, wizards, canvas) | **Inertia + PrimeVue** | React, Vue SPA separada |
**Regla de oro:** Empezá server-side. "Graduá" a Inertia + PrimeVue **solo cuando una pantalla específica demuestre** que no puede resolverse con HTMX + Alpine.js.

**Regla de componentes:** Preferí `django-cotton` sobre `{% include %}` siempre que necesités reusar markup con props o slots. Preline UI te da los estilos base, cotton te da la encapsulación en templates.

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

### 8. Multitenant con Organization

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

### 9. User con email login

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

### 10. TenantMiddleware para filtering automático

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

### 11. Catálogo unificado con is_global

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

---

## Patrones que NO VAN (específicos de tests-360)

Estos patrones son específicos del proyecto tests-360 (evaluaciones 360 + encuestas de pulso SaaS). No aplicarlos en otros proyectos.

### 12. TenantMiddleware + TenantMixin completos

Solo para **SaaS multitenant con evaluación de organizaciones**.

### 13. Assignment con EvaluationRole

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

### 14. Question con show_on_* booleans

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

### 15. Survey + SurveyResponse para pulse

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

### 16. Segment con factor + jerarquía

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

### 17. Management command seed con datos demo

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