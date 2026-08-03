#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

domain_pattern='(^|[^A-Za-z0-9])(moonfish|mooncast|moonmold|finance|financial|stock|equity_research|a_share|ashare|aigc|campaign|storyboard|animatic|video_generation|video_production)([^A-Za-z0-9]|$)'

if rg -n -i "$domain_pattern" . \
  --glob '*.mbt' \
  --glob '*.mbti' \
  --glob '!**/*_test.mbt' \
  --glob '!**/*_wbtest.mbt' \
  --glob '!conformance/**' \
  --glob '!_build/**'; then
  echo "MoonFlow production code contains pack-owned domain vocabulary" >&2
  exit 1
fi

if rg -n '"vectie/(moonfish|mooncast|moonmold)([/@"]|$)' . \
  --glob 'moon.mod' \
  --glob 'moon.pkg' \
  --glob 'moon.pkg.json' \
  --glob '!_build/**'; then
  echo "MoonFlow depends directly on a domain pack" >&2
  exit 1
fi

echo "Current MoonFlow domain-isolation checks passed"
