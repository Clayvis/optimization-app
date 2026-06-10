#!/bin/sh
#
# Installs the local pre-push test gate. Idempotent. Run once per clone:
#   sh scripts/install_git_hooks.sh
#
# The hook lives in .git/hooks (not tracked), so this installer is the tracked,
# reproducible way to enable it. Uninstall: rm .git/hooks/pre-push

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_DIR="$REPO_ROOT/.git/hooks"
HOOK="$HOOK_DIR/pre-push"

if [ ! -d "$HOOK_DIR" ]; then
    echo "error: $HOOK_DIR not found (run from inside the git repo)."
    exit 1
fi

cat > "$HOOK" <<'EOF'
#!/bin/sh
exec sh "$(git rev-parse --show-toplevel)/scripts/pre_push_test_gate.sh" "$@"
EOF
chmod +x "$HOOK"
chmod +x "$REPO_ROOT/scripts/pre_push_test_gate.sh"

echo "Installed pre-push test gate -> $HOOK"
echo "Bypass once with: git push --no-verify"
echo "Fast push (parity guards only): SKIP_TESTS=1 git push"
