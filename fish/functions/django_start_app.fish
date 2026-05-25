function django_start_app
    if test (count $argv) -eq 0
        echo "❌ Uso: django_start_app <nombre_app>"
        return 1
    end

    set -l app_name $argv[1]
    set -l TPL ~/.config/fish/django-templates

    if test -d "apps/$app_name"
        echo "❌ La app apps/$app_name ya existe"
        return 1
    end

    echo "🏗️  Creando app apps/$app_name..."

    # Create modern folder structure
    mkdir -p apps/$app_name/{models,admin,views,services,dtos,seeders,domain}
    touch apps/$app_name/__init__.py
    touch apps/$app_name/models/__init__.py
    touch apps/$app_name/admin/__init__.py
    touch apps/$app_name/views/__init__.py
    touch apps/$app_name/services/__init__.py
    touch apps/$app_name/dtos/__init__.py
    touch apps/$app_name/seeders/__init__.py
    touch apps/$app_name/domain/__init__.py

    # Convert snake_case to CamelCase for class name
    set -l class_name ""
    for part in (string split "_" $app_name)
        set class_name $class_name(string upper (string sub -l 1 $part))(string sub -s 2 $part)
    end

    # Create apps.py
    printf "from django.apps import AppConfig\n\n\nclass %sConfig(AppConfig):\n    default_auto_field = \"django.db.models.BigAutoField\"\n    name = \"apps.%s\"\n    verbose_name = \"%s\"\n" $class_name $app_name $class_name > apps/$app_name/apps.py

    # Create urls.py from template
    sed "s/{app_name}/$app_name/g" $TPL/app_urls.py > apps/$app_name/urls.py

    # Add to INSTALLED_APPS
    if test -f config/settings.py
        uv run python3 $TPL/add_installed_app.py $app_name
    end

    echo "✅ App apps/$app_name creada con estructura moderna"
end
