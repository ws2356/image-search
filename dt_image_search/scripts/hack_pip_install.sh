script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

uv pip install --project "$script_dir/../.." -r "$script_dir/../../requirements-windows.lock"
