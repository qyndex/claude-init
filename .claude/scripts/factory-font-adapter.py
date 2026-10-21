#!/usr/bin/env python3
"""Exact registered WOFF2 metadata only; never parse or execute a host font."""
import hashlib
import json
import re

KIND = 'registered-woff2-v1'
SUBSETS = ('cyrillic-ext', 'cyrillic', 'greek-ext', 'greek', 'vietnamese', 'latin-ext', 'latin')
PATHS = {'public/fonts/inter/inter-baseline-' + subset + '.woff2' for subset in SUBSETS}

def require(condition, message):
    if not condition:
        raise ValueError(message)

def no_duplicates(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate font configuration field')
        result[key] = value
    return result

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()

def pin(value, path=None):
    require(isinstance(value, dict), 'invalid font pin')
    require(isinstance(value.get('sha256'), str) and re.fullmatch('[0-9a-f]{64}', value['sha256']), 'invalid font digest')
    if path is not None:
        require(value.get('path') == path, 'unexpected font metadata path')

def registration(approved, repository):
    value = approved.get('review_adapter')
    if value is None:
        return None
    require(isinstance(value, dict) and set(value) == {'kind','repository','spec_sha256','assets','license','provenance'}, 'invalid font registration')
    require(isinstance(repository, str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository) and
            isinstance(approved.get('sha256'), str) and re.fullmatch('[0-9a-f]{64}', approved['sha256']), 'invalid font repository/spec identity')
    require(value['kind'] == KIND and value['repository'] == repository and
            value['spec_sha256'] == approved.get('sha256'), 'font repository/spec binding differs')
    require(isinstance(value['assets'], dict) and 0 < len(value['assets']) <= 7 and set(value['assets']) <= PATHS, 'unregistered font path')
    pin(value['license'], 'public/fonts/inter/OFL.txt')
    pin(value['provenance'], 'public/fonts/inter/SOURCE.json')
    require(set(value['license']) == set(value['provenance']) == {'path','sha256'}, 'invalid font metadata pin')
    for path, item in value['assets'].items():
        pin(item)
        require(set(item) == {'sha256','length','face'} and type(item['length']) is int and 48 <= item['length'] <= 100000, 'invalid font length/schema')
        face = item['face']
        require(isinstance(face, dict) and set(face) == {'family','style','weight','display','unicode_range'} and
                face['family'] == 'Inter' and face['style'] == 'normal' and face['weight'] == '100 900' and face['display'] == 'swap', 'invalid font face metadata')
        require(isinstance(face['unicode_range'], str) and len(face['unicode_range']) <= 1000 and
                re.fullmatch(r'U\+[0-9A-F?]+(?:-[0-9A-F]+)?(?:,U\+[0-9A-F?]+(?:-[0-9A-F]+)?)*', face['unicode_range']), 'invalid font Unicode range')
    return value

def manifest(approved, repository, source, ref):
    value = registration(approved, repository)
    if value is None:
        return None
    for key in ('license','provenance'):
        item = value[key];raw = source(item['path'], ref)
        require(len(raw) <= 100000 and digest(raw) == item['sha256'], 'font metadata source differs')
        text = raw.decode('utf-8')
        require('\x00' not in text and bool(text.strip()), 'invalid font metadata text')
        if key == 'license':
            require('SIL OPEN FONT LICENSE Version 1.1' in text, 'missing font license')
        else:
            provenance = json.loads(text, object_pairs_hook=no_duplicates)
            require(isinstance(provenance, dict) and isinstance(provenance.get('assets'), list), 'missing font provenance assets')
    listed = provenance['assets']
    require(len(listed) == len(value['assets']) and {item.get('path') for item in listed if isinstance(item, dict)} == set(value['assets']), 'font provenance paths differ')
    for item in listed:
        require(isinstance(item, dict) and item.get('sha256') == value['assets'][item['path']]['sha256'] and
                type(item.get('bytes')) is int and item['bytes'] == value['assets'][item['path']]['length'], 'font provenance digest/length differs')
    assets = {path: blob(approved, repository, path, source(path, ref), ref) for path in value['assets']}
    return {'kind':KIND, 'registration_sha256':digest(canonical(value)), 'assets':assets,
            'asset_manifest_sha256':digest(canonical({'head_sha':ref,'assets':value['assets']}))}

def blob(approved, repository, path, raw, ref):
    value = registration(approved, repository)
    require(value is not None and path in value['assets'], 'binary candidate needs an approved review adapter')
    item = value['assets'][path]
    require(len(raw) == item['length'] and digest(raw) == item['sha256'], 'font bytes differ from protected registration')
    require(raw[:4] == b'wOF2' and len(raw) >= 48 and int.from_bytes(raw[8:12], 'big') == len(raw), 'invalid WOFF2 magic/length')
    return {'adapter':KIND, 'path':path, 'revision':ref, 'git_blob_sha1':hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest(),
            'sha256':digest(raw), 'length':len(raw), 'magic':'wOF2', 'face':item['face'],
            'registration_sha256':digest(canonical(value))}

def content(approved, repository, path, raw, ref):
    # Registered paths always require the binary adapter; UTF-8-shaped tampering cannot bypass it.
    value = registration(approved, repository)
    if value is not None and path in value['assets']:
        return blob(approved, repository, path, raw, ref)
    require(b'\0' not in raw, 'binary candidate needs an approved review adapter')
    return raw.decode('utf-8')


def binding(manifest):
    return None if manifest is None else {key:manifest[key] for key in ('kind','registration_sha256','asset_manifest_sha256')}
