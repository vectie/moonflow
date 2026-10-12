#!/usr/bin/env python3
"""Return explicit offline criterion findings as a prepared MoonFlow review receipt."""
import argparse
from datetime import datetime
import io
import json
import math
import os
from pathlib import Path
import re
import sys
import zipfile

from review_packet import (MAX_ARTIFACTS, MAX_FILE, MAX_RESPONSE, MAX_TOTAL,
                           PacketError, current_result, digest, json_bytes,
                           prepare_packet, select_item)

MAX_PACKET = MAX_TOTAL + 3 * MAX_RESPONSE + 128 * 1024
MAX_WORKSHEET = 2 * 1024 * 1024
ITEM_BINDING = ('work_item_id', 'declaration_id', 'product_id', 'operation',
                'request_id', 'active_attempt_id', 'idempotency_key', 'input_digest',
                'result_id', 'output_digest', 'acceptance_criteria')
HEAD_BINDING = ('run_id', 'book_id', 'declaration_revision', 'source_digest')


def bounded_read(path, maximum):
    with path.open('rb') as source:
        data = source.read(maximum + 1)
    if len(data) > maximum:
        raise PacketError(f'{path.name} exceeds its supported byte limit')
    return data


def decode_json(data):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise PacketError(f'duplicate JSON field: {key}')
            result[key] = value
        return result
    def bad_number(value):
        raise PacketError(f'invalid JSON number: {value}')
    value = json.loads(data.decode('utf-8'), object_pairs_hook=pairs, parse_constant=bad_number)
    if not isinstance(value, dict):
        raise PacketError('expected one JSON object')
    return value


def nonblank(value, label, limit=4096):
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise PacketError(f'{label} must be explicit nonblank text (at most {limit} characters)')
    return value


def portable_ref(value):
    if (not isinstance(value, str) or not value or value.startswith('/') or '\\' in value
            or any(p in {'', '.', '..'} for p in value.split('/'))
            or any(ord(c) < 32 or ord(c) == 127 for c in value)):
        raise PacketError('receipt must be a portable workspace-relative file reference')
    return value


def read_packet(path):
    """Inspect only bounded ZIP members; never extract or execute packet content."""
    raw = bounded_read(path, MAX_PACKET)
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        infos = archive.infolist()
        names = [entry.filename for entry in infos]
        if (len(names) != len(set(names)) or not 4 <= len(names) <= MAX_ARTIFACTS + 3
                or any(entry.file_size > MAX_FILE for entry in infos)
                or sum(entry.file_size for entry in infos) > MAX_PACKET):
            raise PacketError('packet member count, uniqueness or size is unsupported')
        manifest = decode_json(archive.read('manifest.json'))
        if (manifest.get('contract_id') != 'moonflow.review-packet.v1'
                or manifest.get('review_decision') is not None
                or manifest.get('artifact_digest_verified') is not True):
            raise PacketError('expected an undecided pending-review packet')
        head, item = manifest.get('head'), manifest.get('item')
        if not isinstance(head, dict) or not isinstance(item, dict):
            raise PacketError('packet has no complete run/item identity')
        for field in HEAD_BINDING:
            nonblank(head.get(field), field)
        for field in ITEM_BINDING:
            if field != 'acceptance_criteria':
                nonblank(item.get(field), field)
        if (not re.fullmatch(r'[A-Za-z0-9_.-]{1,128}', head['run_id'])
                or head['run_id'] == '.' or '..' in head['run_id']):
            raise PacketError('packet run ID is outside the supported native-client selection syntax')
        projection = {**head, 'protocol': 'moonflow.run-projection.v3',
                      'outcome': head.get('run_outcome'), 'items': [item]}
        select_item(projection, head['run_id'], item['work_item_id'])
        criteria = item['acceptance_criteria']
        if len(criteria) > 256 or len(set(criteria)) != len(criteria):
            raise PacketError('packet requires at most 256 distinct original criteria')
        history_bytes = archive.read('history.json')
        if len(history_bytes) > MAX_RESPONSE or digest(history_bytes) != manifest.get('history_sha256'):
            raise PacketError('packet history bytes differ from the recorded hash')
        event = current_result(decode_json(history_bytes), projection, item)
        if event.get('event_id') != manifest.get('result_event_id'):
            raise PacketError('packet result event identity differs from its history')
        artifacts = manifest.get('artifacts')
        if not isinstance(artifacts, list) or not 1 <= len(artifacts) <= MAX_ARTIFACTS:
            raise PacketError('packet has no supported current outputs')
        expected_names, refs, total = {'index.html', 'manifest.json', 'history.json'}, [], 0
        for ordinal, artifact in enumerate(artifacts, 1):
            if not isinstance(artifact, dict):
                raise PacketError('packet output entry is malformed')
            name = artifact.get('packet_path', '')
            if not re.fullmatch(rf'artifacts/output-{ordinal:04d}\.[A-Za-z0-9]{{1,12}}', name):
                raise PacketError('packet output has an unexpected member path')
            data = archive.read(name)
            total += len(data)
            if (type(artifact.get('size_bytes')) is not int or artifact['size_bytes'] != len(data)
                    or digest(data) != artifact.get('sha256') or total > MAX_TOTAL):
                raise PacketError('packet output bytes differ from its manifest or exceed the limit')
            refs.append(artifact.get('artifact_ref'))
            expected_names.add(name)
        if set(names) != expected_names or refs != event['output_artifacts']:
            raise PacketError('packet members differ from the exact current result outputs')
        observed = digest('\n'.join(f'{a["artifact_ref"]}|{a["sha256"]}' for a in artifacts).encode('utf-8'))
        if observed != item['output_digest'] or observed != manifest.get('observed_output_digest'):
            raise PacketError('packet outputs do not match the recorded result digest')
    return manifest, digest(raw)


def worksheet_for(manifest, packet_hash):
    item, head = manifest['item'], manifest['head']
    return {'contract_id': 'moonflow.review-worksheet.v1', 'packet_sha256': packet_hash,
            'head_binding': {key: head[key] for key in HEAD_BINDING},
            'item_binding': {key: item[key] for key in ITEM_BINDING},
            'result_event_id': manifest['result_event_id'],
            'available_evidence': manifest['artifacts'],
            'review_id': '', 'reviewer_id': '', 'review_authority_id': '',
            'recorded_at': '', 'decision': None,
            'criteria': [{'criterion': criterion, 'satisfied': None,
                          'evidence_refs': [], 'note': ''} for criterion in item['acceptance_criteria']]}


def validate_findings(worksheet, manifest, packet_hash):
    template = worksheet_for(manifest, packet_hash)
    if set(worksheet) != set(template):
        raise PacketError('worksheet fields differ from the generated template')
    for key in ('contract_id', 'packet_sha256', 'head_binding', 'item_binding',
                'result_event_id', 'available_evidence'):
        if worksheet[key] != template[key]:
            raise PacketError(f'worksheet {key} no longer matches the selected packet')
    for key in ('review_id', 'reviewer_id', 'review_authority_id'):
        nonblank(worksheet[key], key, 256)
    stamp = worksheet['recorded_at']
    if not isinstance(stamp, str) or not re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', stamp):
        raise PacketError('recorded_at requires an explicit UTC YYYY-MM-DDTHH:MM:SSZ value')
    datetime.strptime(stamp, '%Y-%m-%dT%H:%M:%SZ')
    if worksheet['decision'] not in {'accepted', 'rejected'}:
        raise PacketError('choose an explicit accepted or rejected decision')
    findings = worksheet['criteria']
    if not isinstance(findings, list) or len(findings) != len(template['criteria']):
        raise PacketError('provide one finding for every original criterion')
    available = {a['artifact_ref'] for a in manifest['artifacts']}
    for original, finding in zip(template['criteria'], findings):
        if (not isinstance(finding, dict) or set(finding) != set(original)
                or finding.get('criterion') != original['criterion']):
            raise PacketError('findings must preserve exact criterion order and text')
        if type(finding['satisfied']) is not bool:
            raise PacketError('every criterion needs an explicit true or false finding')
        nonblank(finding['note'], 'criterion note', 16384)
        refs = finding['evidence_refs']
        if (not isinstance(refs, list) or any(not isinstance(ref, str) for ref in refs)
                or len(refs) != len(set(refs)) or any(ref not in available for ref in refs)):
            raise PacketError('evidence must select distinct original current-output references from the packet')
        if finding['satisfied'] and not refs:
            raise PacketError('a satisfied criterion needs at least one current-output evidence reference')
    satisfied = [f['satisfied'] for f in findings]
    if ((worksheet['decision'] == 'accepted' and not all(satisfied))
            or (worksheet['decision'] == 'rejected' and all(satisfied))):
        raise PacketError('decision conflicts with the explicit criterion findings')


def prepare_receipt(cli, workspace, ref, worksheet, manifest, packet_hash, timeout):
    validate_findings(worksheet, manifest, packet_hash)
    item, head = manifest['item'], manifest['head']
    # The existing packet exporter uses canonical native reads and rehashes the
    # actual current output bytes. It does not write or invoke a review action.
    _, current = prepare_packet(cli, workspace, head['run_id'], item['work_item_id'],
                                timeout, worksheet['recorded_at'])
    for group, fields in (('head', HEAD_BINDING), ('item', ITEM_BINDING)):
        for field in fields:
            if current[group].get(field) != manifest[group].get(field):
                raise PacketError(f'result changed since packet export: {field}; export and review the new result')
    if (current['result_event_id'] != manifest['result_event_id']
            or current['artifacts'] != manifest['artifacts']):
        raise PacketError('current result event or outputs changed since packet export')
    attached = current['item'].get('artifacts', [])
    if any(ref not in attached for f in worksheet['criteria'] for ref in f['evidence_refs']):
        raise PacketError('selected evidence is no longer attached to the current work item')
    receipt = {'contract_id': 'moonflow.acceptance-review.v1',
               'run_id': head['run_id'], 'work_item_id': item['work_item_id'],
               'declaration_id': item['declaration_id'], 'result_id': item['result_id'],
               'attempt_id': item['active_attempt_id'], 'output_digest': item['output_digest'],
               'receipt_artifact': ref}
    for key in ('review_id', 'reviewer_id', 'review_authority_id', 'recorded_at', 'decision', 'criteria'):
        receipt[key] = worksheet[key]
    return receipt, current['head']


def publish(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as output:
        output.write(data)
        output.flush()
        os.fsync(output.fileno())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest='action', required=True)
    sheet = actions.add_parser('worksheet', help='create a blank criterion worksheet from a review ZIP')
    sheet.add_argument('packet', type=Path)
    sheet.add_argument('--output', required=True, type=Path)
    prepare = actions.add_parser('prepare', help='reload current result and prepare, but never submit, a receipt')
    prepare.add_argument('packet', type=Path)
    prepare.add_argument('worksheet', type=Path)
    prepare.add_argument('workspace', type=Path)
    prepare.add_argument('--cli', required=True, type=Path)
    prepare.add_argument('--receipt', required=True, help='new workspace-relative receipt path')
    prepare.add_argument('--timeout', type=float, default=30)
    args = parser.parse_args(argv)
    try:
        manifest, packet_hash = read_packet(args.packet)
        if args.action == 'worksheet':
            data = json_bytes(worksheet_for(manifest, packet_hash))
            if len(data) > MAX_WORKSHEET:
                raise PacketError('generated worksheet exceeds the 2 MiB return limit')
            publish(args.output, data)
            report = {'contract_id': 'moonflow.review-worksheet-export.v1', 'output': str(args.output),
                      'sha256': digest(data), 'packet_sha256': packet_hash, 'decision': None}
        else:
            if not math.isfinite(args.timeout) or not .1 <= args.timeout <= 300:
                raise PacketError('timeout must be 0.1 through 300 seconds')
            workspace, cli = args.workspace.resolve(strict=True), args.cli.resolve(strict=True)
            if not workspace.is_dir() or not cli.is_file() or not os.access(cli, os.X_OK):
                raise PacketError('workspace must be a directory and cli an existing trusted executable')
            ref = portable_ref(args.receipt)
            destination = workspace.joinpath(*ref.split('/'))
            resolved = destination.resolve()
            if (not resolved.is_relative_to(workspace)
                    or resolved.is_relative_to((workspace / '.moonsuite').resolve())):
                raise PacketError('receipt must stay in the workspace outside the canonical .moonsuite store')
            if destination.exists() or destination.is_symlink():
                raise PacketError('receipt already exists; choose a new file')
            if not destination.parent.is_dir():
                raise PacketError('receipt parent directory must already exist')
            raw_worksheet = bounded_read(args.worksheet, MAX_WORKSHEET)
            worksheet = decode_json(raw_worksheet)
            receipt, current_head = prepare_receipt(cli, workspace, ref, worksheet, manifest,
                                                     packet_hash, args.timeout)
            data = json_bytes(receipt)
            publish(destination, data)
            report = {'contract_id': 'moonflow.prepared-review-receipt.v1',
                      'receipt_artifact': ref, 'sha256': digest(data),
                      'packet_sha256': packet_hash, 'worksheet_sha256': digest(raw_worksheet),
                      'observed_head': current_head, 'decision': receipt['decision'],
                      'submitted': False, 'reviewer_identity_authenticated': False,
                      'review_authority_verified': False,
                      'submit_argv': [str(cli), 'review-outcome', str(workspace),
                                      receipt['run_id'], ref]}
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0
    except (PacketError, OSError, ValueError, KeyError, TypeError, RuntimeError,
            zipfile.BadZipFile, RecursionError) as error:
        print(f'review-return: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
