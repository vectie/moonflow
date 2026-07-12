#!/usr/bin/env bash
set -euo pipefail

suite_root="${1:-${HOME}/moonsuite}"
source_root="${MOON_SUITE_SOURCE_ROOT:-${HOME}/Workspace}"
bin_dir="${suite_root}/bin"
runtime_dir="${suite_root}/.moonsuite/runtime"

mkdir -p "${bin_dir}" "${runtime_dir}"

build_and_install() {
  local repo="$1"
  local package="$2"
  local output="$3"
  local destination="$4"
  (
    cd "${source_root}/${repo}"
    moon build --target native "${package}"
    install -m 0755 "${output}" "${bin_dir}/${destination}"
  )
}

build_and_install moongate cmd/main _build/native/debug/build/cmd/main/main.exe moongate
build_and_install moonflow cmd/main _build/native/debug/build/cmd/main/main.exe moonflow
build_and_install moonbook cmd/main _build/native/debug/build/cmd/main/main.exe moonbook
build_and_install moonbook cmd/moonflow_attestor _build/native/debug/build/cmd/moonflow_attestor/moonflow_attestor.exe moonbook-flow-attestor
build_and_install moonclaw cmd/main _build/native/debug/build/vectie/moonclaw/cmd/main/main.exe moonclaw
build_and_install moontown src/cmd/moonflow_attestor _build/native/debug/build/cmd/moonflow_attestor/moonflow_attestor.exe moontown-flow-attestor
build_and_install moonrobo cmd/moonflow_attestor _build/native/debug/build/cmd/moonflow_attestor/moonflow_attestor.exe moonrobo-flow-attestor
build_and_install moonmoon cmd/moonflow_attestor _build/native/debug/build/cmd/moonflow_attestor/moonflow_attestor.exe moonmoon-flow-attestor

manifest="${runtime_dir}/installed-runtime.json"
temporary="${manifest}.tmp"
installed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
entries=(
  "moonbook:moonbook"
  "moonbook-flow-attestor:moonbook"
  "moonclaw:moonclaw"
  "moonflow:moonflow"
  "moongate:moongate"
  "moonmoon-flow-attestor:moonmoon"
  "moonrobo-flow-attestor:moonrobo"
  "moontown-flow-attestor:moontown"
)

{
  printf '{\n'
  printf '  "contract_id": "moonsuite.installed-runtime.v1",\n'
  printf '  "suite_root": "%s",\n' "${suite_root}"
  printf '  "installed_at": "%s",\n' "${installed_at}"
  printf '  "binaries": [\n'
  for index in "${!entries[@]}"; do
    IFS=: read -r binary repo <<<"${entries[$index]}"
    digest="$(shasum -a 256 "${bin_dir}/${binary}" | awk '{print $1}')"
    commit="$(git -C "${source_root}/${repo}" rev-parse HEAD)"
    printf '    {"name":"%s","sha256":"%s","source_repo":"%s","source_commit":"%s"}' \
      "${binary}" "${digest}" "${repo}" "${commit}"
    if [[ "${index}" -lt "$((${#entries[@]} - 1))" ]]; then
      printf ','
    fi
    printf '\n'
  done
  printf '  ]\n'
  printf '}\n'
} >"${temporary}"
mv "${temporary}" "${manifest}"

printf 'Installed Moon Suite unattended runtime in %s\n' "${bin_dir}"
printf 'Wrote content-addressed manifest %s\n' "${manifest}"
