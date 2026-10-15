#!/usr/bin/env python3
"""Ad-hoc previews retain sandbox/runtime, allowing their bundled ad-hoc libraries."""
import pathlib
import plistlib
import subprocess
import sys
import tempfile

app = pathlib.Path(sys.argv[1]).resolve()


def entitlements_for(path):
    result = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', str(path)], capture_output=True)
    if result.returncode and b'code object is not signed at all' in result.stderr:
        return {}
    result.check_returncode()
    return plistlib.loads(result.stdout) if result.stdout.strip() else {}


# Sign each Mach-O and its enclosing code bundles from the inside out.
mach_o = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe',
          b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}
binaries = []
for path in app.rglob('*'):
    if path.is_file() and not path.is_symlink():
        with path.open('rb') as handle:
            if handle.read(4) in mach_o:
                binaries.append(path)
targets = set(binaries) | {app}
for binary in binaries:
    targets.update(parent for parent in binary.parents if parent != app and app in parent.parents
                   and parent.suffix in {'.app', '.xpc', '.framework'})
metadata = {path: entitlements_for(path) for path in targets}
assert metadata[app].get('com.apple.security.app-sandbox') is True

with tempfile.TemporaryDirectory(prefix='notch-apple-sign-') as tmp:
    plist = pathlib.Path(tmp)/'preview.plist'
    for path in sorted(targets, key=lambda item: len(item.parts), reverse=True):
        entitlements = metadata[path]
        entitlements.pop('com.apple.security.get-task-allow', None)
        if path == app:
            # Developer ID builds should sign dependencies with the same team instead.
            entitlements['com.apple.security.cs.disable-library-validation'] = True
        plist.write_bytes(plistlib.dumps(entitlements))
        subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime',
                        '--entitlements', str(plist), '--preserve-metadata=requirements,flags', str(path)], check=True)
for path in binaries:
    assert 'com.apple.security.get-task-allow' not in entitlements_for(path), f'Debug entitlement: {path}'
assert entitlements_for(app).get('com.apple.security.app-sandbox') is True
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
