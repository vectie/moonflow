#!/usr/bin/env python3
"""Refuse native reuse if retained executable or any native source input differs."""
import argparse
import hashlib
import json
from pathlib import Path


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream,'sha256').hexdigest()


def native_inputs(source):
    return {str(path.relative_to(source)):path for path in source.rglob('*')
            if path.is_file() and '.git' not in path.relative_to(source).parts
            and (path.suffix in ('.mbt','.mbti','.c','.h') or path.name in ('moon.mod','moon.pkg'))}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True,type=Path)
    parser.add_argument('--cli',required=True,type=Path)
    args=parser.parse_args()
    manifest=json.loads((Path(__file__).parent/'shared_table_native_inputs.json').read_text())
    actual=native_inputs(args.source.resolve())
    assert set(actual)==set(manifest['native_inputs']), 'native source input set changed; a fresh build is required'
    mismatches=[name for name,path in actual.items() if digest(path)!=manifest['native_inputs'][name]]
    assert not mismatches, 'native source bytes changed; a fresh build is required: '+', '.join(mismatches)
    assert digest(args.cli)==manifest['cli_sha256'], 'retained executable hash changed'
    print(json.dumps({'native_source_and_config_files_identical':len(actual),
                      'cli_sha256':manifest['cli_sha256'],'native_rebuilt':False,
                      'provenance_limit':manifest['provenance_limit']},indent=2))


if __name__=='__main__':main()
