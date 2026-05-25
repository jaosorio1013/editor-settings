function django_test
    if test (count $argv) -gt 0
        uv run pytest $argv
    else
        uv run pytest
    end
end
