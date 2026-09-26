#!/usr/bin/env bash
# Build frontend → sync to OpenList/public/dist → go build → openlist binary
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND="$ROOT/OpenList-Frontend"
BACKEND="$ROOT/OpenList"
BACKEND_DIST="$BACKEND/public/dist"
OUTPUT="$ROOT/openlist"

LITE=false
SKIP_FRONTEND=false
SKIP_FRONTEND_BUILD=false
FRONTEND_ONLY=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

  Build OpenList frontend, embed it into the backend, and produce ./openlist.

Options:
  --lite              Build lite frontend (pnpm build:lite)
  --skip-frontend     Skip frontend build/sync (use existing public/dist)
  --skip-frontend-build
                      Skip pnpm build; only copy an existing frontend dist/
  --frontend-only     Only build/sync frontend; do not run go build
  -o <path>           Output binary path (default: $ROOT/openlist)
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lite) LITE=true; shift ;;
    --skip-frontend) SKIP_FRONTEND=true; shift ;;
    --skip-frontend-build|--skip-build) SKIP_FRONTEND_BUILD=true; shift ;;
    --frontend-only) FRONTEND_ONLY=true; shift ;;
    -o) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ ! -d "$BACKEND" ]]; then
  echo "Error: backend not found at $BACKEND" >&2
  exit 1
fi

ensure_mpegts_built() {
  local mpegts_dir="$FRONTEND/node_modules/mpegts.js"
  if [[ ! -d "$mpegts_dir" ]]; then
    return 0
  fi
  if [[ -f "$mpegts_dir/dist/mpegts.js" ]]; then
    return 0
  fi
  echo "==> Building mpegts.js (missing dist/)..."
  (
    cd "$mpegts_dir"
    if [[ ! -d node_modules ]]; then
      npm install --include=dev
    fi
    npm run build
  )
}

sync_frontend() {
  if [[ ! -d "$FRONTEND" ]]; then
    echo "Error: frontend not found at $FRONTEND" >&2
    exit 1
  fi

  cd "$FRONTEND"

  if [[ "$SKIP_FRONTEND_BUILD" != true ]]; then
    if ! command -v pnpm >/dev/null 2>&1; then
      echo "Error: pnpm is required" >&2
      exit 1
    fi
    if [[ ! -d node_modules ]]; then
      echo "==> Installing frontend dependencies..."
      pnpm install
    fi
    ensure_mpegts_built
    if [[ "$LITE" == true ]]; then
      echo "==> Building lite frontend..."
      pnpm run build:lite
    else
      echo "==> Building frontend..."
      pnpm run build
    fi
  fi

  if [[ ! -d "$FRONTEND/dist" ]]; then
    echo "Error: $FRONTEND/dist not found (build first, or omit --skip-frontend-build)" >&2
    exit 1
  fi

  echo "==> Syncing to $BACKEND_DIST ..."
  rm -rf "$BACKEND_DIST"
  mkdir -p "$BACKEND_DIST"
  cp -a "$FRONTEND/dist/." "$BACKEND_DIST/"
}

build_backend() {
  if [[ ! -f "$BACKEND_DIST/index.html" ]]; then
    echo "Error: $BACKEND_DIST/index.html missing; build/sync frontend first" >&2
    exit 1
  fi
  if ! command -v go >/dev/null 2>&1; then
    echo "Error: go is required" >&2
    exit 1
  fi

  local built_at git_author git_commit version web_version ldflags
  built_at="$(date +'%F %T %z')"
  git_author="The OpenList Projects Contributors <noreply@oplist.org>"
  version="dev"
  web_version="dev"
  if git -C "$BACKEND" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_commit="$(git -C "$BACKEND" log --pretty=format:'%h' -1)"
  else
    git_commit="unknown"
  fi
  if [[ -f "$BACKEND_DIST/VERSION" ]]; then
    web_version="$(tr -d '[:space:]' < "$BACKEND_DIST/VERSION")"
  fi

  ldflags="-w -s \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.BuiltAt=${built_at}' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.GitAuthor=${git_author}' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.GitCommit=${git_commit}' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.Version=${version}' \
-X 'github.com/OpenListTeam/OpenList/v4/internal/conf.WebVersion=${web_version}'"

  mkdir -p "$(dirname "$OUTPUT")"
  echo "==> Building backend → $OUTPUT ..."
  (
    cd "$BACKEND"
    CGO_ENABLED="${CGO_ENABLED:-0}" go build -o "$OUTPUT" -ldflags="$ldflags" -tags=jsoniter .
  )
}

if [[ "$SKIP_FRONTEND" != true ]]; then
  sync_frontend
else
  echo "==> Skipping frontend (using existing $BACKEND_DIST)"
fi

if [[ "$FRONTEND_ONLY" == true ]]; then
  echo "Done. Frontend dist copied to OpenList/public/dist"
  exit 0
fi

build_backend
echo "Done. Binary: $OUTPUT"
ls -lh "$OUTPUT"
