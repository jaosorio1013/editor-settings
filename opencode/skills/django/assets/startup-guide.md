# Startup Guide: Proyectos Django Modernos

Guía de arranque para nuevos proyectos basada en prácticas reales que escalan. Diseñada para evitar la deuda técnica que se paga con dolor a los 6 meses.

## Quick path para iniciar un proyecto

1. [ ] Elegir stack y fijar versiones en `.python-version`, `pyproject.toml`, y `pyrightconfig.json` (¡las tres deben coincidir!).
2. [ ] Crear estructura de apps con `admin/`, `models/`, `tests/` como directorios desde el día 1.
3. [ ] Implementar `BaseModel` con soft delete y dos managers (`objects` / `all_objects`).
4. [ ] Configurar `GlobalConfiguration` como singleton con cache.
5. [ ] Separar lógica de negocio pura en `domain/` usando `dataclass(frozen=True)` + `Protocol`.
6. [ ] Escribir `FLUJO.md` con el caso de negocio real antes de tocar código de frontend.
7. [ ] Configurar `pytest-django` + `model-bakery` y un test que valide la primera regla de negocio.
8. [ ] Agregar `ruff` y `pyright` como dev dependencies (no asumir `uvx` en CI).

---

## Stack recomendado

| Capa | Tecnología | Por qué |
|------|------------|---------|
| **Runtime** | Python 3.13+ | LTS, mejor performance, typing nativo |
| **Framework** | Django 6.0 LTS (o superior estable) | No usar betas en producción salvo que tengas equipo para mantenerlo |
| **Gestor de paquetes** | `uv` + `pyproject.toml` | Lockfile rápido, grupos de dev dependencies nativos (PEP 735) |
| **DB** | PostgreSQL desde el primer día | SQLite solo para prototipos de una tarde |
| **Admin** | Django Unfold | Tailwind-based, moderno, extensible |
| **Frontend default** | HTMX 4 + Alpine.js + Tailwind 4 | Sin build pesado, progresivo, se integra natural con Django |
| **API (cuando aplica)** | Django Ninja | Type hints nativos, auto-docs, rendimiento, mucho menos boilerplate que DRF |
| **Build** | Vite | Solo si necesitas bundling de assets propios; si es HTMX puro, evalúa si realmente lo necesitas |
| **Testing** | pytest-django + model-bakery + pytest-mock | Fixtures declarativos, factories rápidas |
| **Type check** | pyright en modo `strict` | Detecta errores antes del deploy |
| **Linter/Format** | ruff (reemplaza flake8, black, isort) | Un solo tool, ultra rápido |

### Decisiones de stack según contexto

No todas las capas se activan desde el día 1. Elegí según lo que estés construyendo:

| Si necesitas... | Usá | No uses |
|----------------|-----|---------|
| CRUDs, formularios, tablas, kanbans en el admin | HTMX 4 + Alpine.js + Tailwind | Vue, React, Inertia |
| API para SPA externo o mobile | Django Ninja | DRF (más verboso) o GraphQL (overkill inicial) |
| Interactividad ligera (dropdowns, tabs, modales) | Alpine.js | React por 3 componentes |
| Actualizaciones de página parcial sin JS manual | HTMX 4 | Fetch API + manejo de estado propio |
| Bundling de CSS/JS propios (raro con HTMX) | Vite | Webpack |
| Base de datos en producción | PostgreSQL | SQLite |

#### Por qué HTMX 4 + Alpine.js como default

- **HTMX** maneja lo que antes hacías con AJAX/fetch: actualizar una tabla, un formulario, un modal, sin recargar la página. Se integra con las vistas de Django sin cambiar nada en el backend.
- **Alpine.js** maneja el estado local del frontend: mostrar/ocultar un dropdown, toggle de tabs, validaciones visuales. Es como jQuery pero moderno y declarativo (`x-show`, `x-data`).
- Juntos cubren el 90% de los casos sin necesidad de un framework SPA. No hay estado global, no hay router client-side, no hay build pesado.

#### Por qué Django Ninja cuando necesites API

Si en algún punto necesitás exponer endpoints REST (por un dashboard externo, una app mobile, o integraciones), usá **Django Ninja** en vez de Django REST Framework:

- Usa **type hints nativos** de Python (no serializers classes enormes).
- **Auto-genera documentación** OpenAPI/Swagger sin configurar nada.
- **Más rápido** que DRF porque no tiene tantas capas de abstracción.
- Se integra limpio con el ORM de Django sin romper la arquitectura.

No agregues Ninja desde el día 1 si no tenés un consumidor de API. Esperá a que surja la necesidad real.

### Lo que NO incluir por defecto

- **SPA frameworks** (Vue, React, Svelte): suman complejidad innecesaria para CRUDs. HTMX resuelve el 90% de los casos.
- **Inertia**: a menos que estés 100% seguro de que necesitas un SPA híbrido.
- **DRF**: si eventualmente necesitás API, preferí Ninja. No agregues DRF "por si acaso".
- **django-cors-headers**: solo si hay API pública o SPA separada.
- **django-vite**: solo si usás Vite. Si no, no lo dejes en `INSTALLED_APPS` "por si acaso".

---

## Estructura de proyecto

```
project/
├── config/               # settings, urls, wsgi, asgi
│   ├── settings.py
│   └── urls.py
├── core/                 # Base técnica transversal
│   ├── models/
│   │   └── base_model.py
│   ├── admin/
│   ├── dtos/
│   ├── utils/
│   ├── seeders/
│   ├── management/
│   └── tests/
├── <app_domain>/         # Ej: crm, quoting, inventory
│   ├── admin/
│   ├── models/
│   ├── domain/           # Lógica pura, sin dependencia de Django ORM
│   ├── services/         # Use cases / orquestación (no lógica de negocio pesada)
│   ├── tests/
│   │   ├── conftest.py
│   │   ├── models/
│   │   ├── domain/
│   │   └── admin/
│   └── views.py          # O templates/ si usás CBV
├── templates/
├── static/
├── resources/            # Entrypoints de Vite/Bun si aplica
├── docs/                 # Decisiones de arquitectura (ADRs)
├── pyproject.toml
├── pytest.ini
├── .python-version
├── .prettierrc
└── .env.example
```

### Regla de oro

> Si una app tiene más de 3 modelos, `admin.py` y `models.py` deben ser **directorios**, no archivos.

---

## Patrones obligatorios

### 1. Soft Delete en `BaseModel`

```python
# core/models/base_model.py
from django.db import models
from django.utils import timezone

class SoftDeleteManager(models.Manager):
    def get_queryset(self):
        return super().get_queryset().filter(deleted_at__isnull=True)

class GlobalManager(models.Manager):
    pass

class BaseModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted_at = models.DateTimeField(null=True, blank=True, editable=False)

    objects = SoftDeleteManager()
    all_objects = GlobalManager()

    class Meta:
        abstract = True

    def delete(self, *args, **kwargs):
        self.deleted_at = timezone.now()
        self.save(update_fields=["deleted_at", "updated_at"])

    def restore(self):
        self.deleted_at = None
        self.save(update_fields=["deleted_at", "updated_at"])
```

**Checklist:**
- [ ] Todos los modelos heredan de `BaseModel`.
- [ ] El admin usa `all_objects` cuando se necesita ver borrados.
- [ ] Se testea que `unique_together` sigue funcionando con soft delete (o se documenta si no es el comportamiento deseado).

### 2. Singleton de configuración global con cache

```python
# core/models/global_config.py
from django.core.cache import cache

class GlobalConfiguration(BaseModel):
    # tus campos de config

    @classmethod
    def get_solo(cls):
        config = cache.get("global_config")
        if not config:
            config = cls.objects.order_by("-created_at").first()
            if not config:
                config = cls.objects.create()
            cache.set("global_config", config, 3600)
        return config

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        cache.delete("global_config")
```

**Checklist:**
- [ ] El admin prohíbe crear más de una instancia.
- [ ] El admin prohíbe borrar la instancia.
- [ ] Invalidación de cache inmediata al guardar.

### 3. Domain Model puro (sin Django ORM)

```python
# quoting/domain/pricing.py
from dataclasses import dataclass
from decimal import Decimal
from typing import Protocol

@dataclass(frozen=True)
class PriceBreakdown:
    unit_cost: Decimal
    unit_utilidad: Decimal
    # ...

class PricingConfig(Protocol):
    show_utilidad: bool
    # ...

class QuoteCalculator:
    def calculate(self, config: PricingConfig, cost: Decimal, qty: int) -> PriceBreakdown:
        # lógica pura, testeable sin DB
        ...
```

**Checklist:**
- [ ] `domain/` no importa nada de Django.
- [ ] La lógica se testea con `pytest` puro (sin `@pytest.mark.django_db`).
- [ ] Los tests replican escenarios de negocio fila por fila (documentación viva).

### 4. Side effects fuera del modelo

**NUNCA** crees objetos adicionales dentro de `Model.save()`.

```python
# MAL
class Person(BaseModel):
    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if self.is_client:
            Deal.objects.create(person=self)  # ¡Magia oculta!

# BIEN: usar signals o servicios de aplicación
from django.db.models.signals import post_save
from django.dispatch import receiver

@receiver(post_save, sender=Person)
def create_deal_for_client(sender, instance, created, **kwargs):
    if created and instance.is_client:
        Deal.objects.create(person=instance)
```

**Checklist:**
- [ ] `save()` solo guarda y recalcula campos propios.
- [ ] Automatizaciones de negocio están en `signals.py` o `services/application.py`.
- [ ] Se testean las automatizaciones de forma aislada.

### 5. Settings seguras

```python
# config/settings.py
import os
from pathlib import Path
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

SECRET_KEY = os.environ["SECRET_KEY"]  # explota si no está
DEBUG = os.getenv("DEBUG", "False").lower() == "true"  # default seguro

DATABASES = {
    "default": {
        "ENGINE": os.getenv("DB_ENGINE", "django.db.backends.sqlite3"),
        "NAME": os.getenv("DB_NAME", BASE_DIR / "db.sqlite3"),
        "USER": os.getenv("DB_USER", ""),
        "PASSWORD": os.getenv("DB_PASSWORD", ""),
        "HOST": os.getenv("DB_HOST", ""),
        "PORT": os.getenv("DB_PORT", ""),
    }
}
```

**Checklist:**
- [ ] `DEBUG` nunca está hardcodeado a `True`.
- [ ] `.env` está en `.gitignore`.
- [ ] `.env.example` existe con todas las vars necesarias (sin valores reales).

---

## Documentación mínima obligatoria

| Documento | Contenido | Cuándo escribirlo |
|-----------|-----------|-------------------|
| `README.md` | Setup, comandos de dev, decisiones de stack | Día 1 |
| `FLUJO.md` | Caso de negocio real, ejemplo de usuario, reglas de negocio | Antes del primer modelo de dominio |
| `PROJECT_STATUS.md` | Roadmap con semáforos (rojo/amarillo/verde) | Semana 1, actualizar semanal |
| `docs/arch/` | ADRs: por qué elegimos X sobre Y | En el momento de la decisión |
| `PRICING_LOGIC.md` | Tablas de escenarios si hay cálculos financieros | Cuando surja la complejidad |

---

## Testing

### Setup

```ini
# pytest.ini
[pytest]
DJANGO_SETTINGS_MODULE = config.settings
python_files = tests.py test_*.py *_tests.py
```

```toml
# pyproject.toml (fragmento)
[dependency-groups]
dev = [
    "pytest-django>=4.11",
    "model-bakery>=1.20",
    "pytest-mock>=3.14",
]
```

### Reglas

- [ ] Tests de `domain/` sin base de datos (`@pytest.mark.django_db` no va ahí).
- [ ] Tests de `models/` usan `model-bakery` para factories.
- [ ] Cada automatización de negocio tiene al menos un test.
- [ ] Si hay una tabla de escenarios en un `.md`, debe haber un test que la valide fila por fila.

---

## Conventions

### Decimal

Siempre usar strings para evitar errores de punto flotante:

```python
# Bien
Decimal("0.00")
Decimal("10.50")

# Mal
Decimal(0.1)  # 0.100000000000000005551115123125782702118158340454101562
```

### Imports

Agrupar en este orden, separados por línea en blanco:

1. Standard library
2. Third-party (Django, restframework, etc.)
3. Local project (`from core.models import BaseModel`)

Usar `from typing import TYPE_CHECKING` para evitar ciclos.

### Naming

| Entidad | Convención | Ejemplo |
|---------|-----------|---------|
| Modelos | PascalCase | `ExecutionQuote` |
| Campos/Vars | snake_case | `total_utilidad` |
| Managers | objects / all_objects | — |
| Servicios de aplicación | PascalCase + Service | `DealWorkflowService` |
| Calculadoras de dominio | PascalCase + Calculator | `QuoteCalculator` |
| Choices | Anidados en modelo | `ExecutionQuote.Status` |

---

## Checklist final antes del primer commit

- [ ] `.python-version`, `pyproject.toml`, y `pyrightconfig.json` coinciden en versión de Python.
- [ ] `DEBUG` lee de env var y default es `False`.
- [ ] `.env` está en `.gitignore`; `.env.example` está versionado.
- [ ] `BaseModel` existe con soft delete y dos managers.
- [ ] `GlobalConfiguration` existe como singleton con cache.
- [ ] Al menos un modelo de dominio tiene su lógica pura en `domain/`.
- [ ] `save()` de modelos no crea otros modelos (side effects en signals/services).
- [ ] `ruff` y `pyright` están en `dev` dependencies y pasan sin errores.
- [ ] `pytest` corre y al menos un test de dominio pasa sin DB.
- [ ] No hay dependencias "por si acaso" (Vue, Inertia, CORS, etc.) si no se usan.
