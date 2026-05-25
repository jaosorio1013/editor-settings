function django_start_project
    set -l project_name ""
    if test (count $argv) -gt 0
        set project_name $argv[1]
        mkdir -p $project_name
        cd $project_name
    end

    set -l TPL ~/.config/fish/django-templates

    echo "🚀 Iniciando proyecto Django moderno..."

    # 1. Init uv project
    if not test -f pyproject.toml
        uv init
    end

    # 2. Add dependencies
    uv add django django-unfold python-dotenv django-stubs django-cotton ruff pytest pytest-django

    # 3. Create Django project
    uv run django-admin startproject config .

    # 4. Generate SECRET_KEY
    set -l SECRET_KEY (uv run python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())")

    printf "%s\n" \
        "SECRET_KEY='$SECRET_KEY'" \
        "DEBUG=true" \
        "ALLOWED_HOSTS=localhost,127.0.0.1" \
        "DB_ENGINE=django.db.backends.sqlite3" \
        "DB_NAME=db.sqlite3" \
        > .env

    # 5. Copy templates
    cp $TPL/env.example .env.example
    cp $TPL/pytest.ini pytest.ini
    cp $TPL/gitignore .gitignore
    cp $TPL/nixpacks.toml nixpacks.toml

    # 6. Create directory structure
    mkdir -p apps/core/{models,admin,views,services,dtos,seeders,domain,management/commands}
    mkdir -p apps/accounts/{models,admin}
    mkdir -p templates/cotton/{ui,layout,forms}
    mkdir -p static/{css,js,images}
    mkdir -p tests

    # 7. Create __init__.py files
    for init_file in apps/__init__.py \
                     apps/core/__init__.py apps/core/models/__init__.py apps/core/admin/__init__.py \
                     apps/core/views/__init__.py apps/core/services/__init__.py apps/core/dtos/__init__.py \
                     apps/core/seeders/__init__.py apps/core/domain/__init__.py \
                     apps/core/management/__init__.py apps/core/management/commands/__init__.py \
                     apps/accounts/__init__.py apps/accounts/models/__init__.py apps/accounts/admin/__init__.py \
                     templates/__init__.py templates/cotton/__init__.py
        touch $init_file
    end

    # 8. Copy core templates
    cp $TPL/core/models_base.py apps/core/models/base.py
    cp $TPL/core/models_init.py apps/core/models/__init__.py
    cp $TPL/core/apps.py apps/core/apps.py
    cp $TPL/accounts/apps.py apps/accounts/apps.py

    # 9. Patch settings.py
    uv run python3 $TPL/patch_settings.py

    echo "✅ Proyecto Django moderno configurado"
    if test -n "$project_name"
        echo ""
        echo "📁 Creado en: $project_name/"
    end
    echo ""
    echo "📂 Estructura:"
    echo "   - apps/core/         (BaseModel, estructura moderna)"
    echo "   - apps/accounts/     (para usuarios personalizados)"
    echo "   - templates/cotton/  (componentes UI)"
    echo "   - static/            (CSS/JS)"
    echo "   - tests/             (pytest)"
    echo "   - .env / .env.example"
    echo "   - nixpacks.toml      (config de deploy con Dockploy/Nixpacks)"
    echo ""
    echo "📝 Siguientes pasos:"
    echo "   1. Revisar config/settings.py"
    echo "   2. uv run python manage.py migrate"
    echo "   3. uv run python manage.py runserver"
    echo ""
    echo "🎨 Para frontend (Tailwind + Preline + cotton):"
    echo "   django_setup_frontend"
end
