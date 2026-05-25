function django_setup_frontend
    set -l TPL ~/.config/fish/django-templates

    if not test -f package.json
        echo "🎨 Configurando frontend stack..."

        # 1. Copy package.json and install deps
        cp $TPL/frontend/package.json package.json
        bun install

        # 2. Copy CSS and JS templates
        cp $TPL/frontend/main.css static/css/main.css
        cp $TPL/frontend/preline_init.js static/js/preline_init.js

        # 3. Copy base template
        cp $TPL/frontend/base.html templates/base.html

        # 4. Create cotton component directories
        mkdir -p templates/cotton/{ui,layout,forms}
        touch templates/cotton/__init__.py

        # 5. Build CSS once
        bun run build

        echo "✅ Frontend stack configurado:"
        echo "   - Tailwind CSS v4"
        echo "   - Preline UI"
        echo "   - HTMX"
        echo "   - Alpine.js"
        echo "   - django-cotton"
        echo ""
        echo "📝 Comandos útiles:"
        echo "   bun run build   # build CSS una vez"
        echo "   bun run watch   # build CSS en watch mode"
        echo ""
        echo "⚠️  Recuerda agregar '{% load static %}' en tus templates"
    else
        echo "⚠️  Ya existe package.json. Para re-configurar, elimínalo primero."
        return 1
    end
end
