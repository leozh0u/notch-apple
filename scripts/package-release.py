#!/usr/bin/env python3
"""Package validated universal Release output into small per-architecture previews."""
import hashlib
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = pathlib.Path(sys.argv[1]).resolve()
out = root / 'dist'
out.mkdir(exist_ok=True)
for arch in ['arm64', 'x86_64']:
    with tempfile.TemporaryDirectory(prefix='notch-apple-package-') as tmp:
        stage = pathlib.Path(tmp)
        app = stage / 'Notch Apple.app'
        shutil.copytree(source, app, symlinks=True)
        for path in app.rglob('*'):
            if not path.is_file() or path.is_symlink():
                continue
            result = subprocess.run(['lipo', '-archs', str(path)], capture_output=True, text=True)
            if result.returncode:
                continue
            arches = result.stdout.strip().split()
            if arch not in arches:
                raise RuntimeError(f'{path.name} does not support {arch}')
            if len(arches) > 1:
                thin = path.with_name(path.name + '.thin')
                subprocess.run(['lipo', str(path), '-thin', arch, '-output', str(thin)], check=True)
                thin.chmod(path.stat().st_mode)
                thin.replace(path)
        resources = app / 'Contents/Resources'
        shutil.copy2(root/'LICENSE', resources/'NotchApple-LICENSE.txt')
        shutil.copy2(root/'THIRD_PARTY_LICENSES', resources/'NotchApple-THIRD-PARTY-LICENSES.txt')
        (resources/'NotchApple-SOURCE.txt').write_text('Corresponding source: https://github.com/leozh0u/notch-apple/releases/tag/v0.3.2\n')
        subprocess.run(['codesign', '--force', '--deep', '--sign', '-', '--preserve-metadata=entitlements,requirements,flags', str(app)], check=True)
        subprocess.run([sys.executable, str(root/'scripts/sign-preview.py'), str(app)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        # Keep a clean installable bundle too, without build caches or debug dylibs.
        bundle = out / arch / 'Notch Apple.app'
        if bundle.exists():
            shutil.rmtree(bundle)
        bundle.parent.mkdir(exist_ok=True)
        shutil.copytree(app, bundle, symlinks=True)
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(out/f'Notch-Apple-{arch}.zip')], check=True)
        (stage/'Applications').symlink_to('/Applications')
        shutil.copy2(root/'LICENSE', stage/'LICENSE.txt')
        shutil.copy2(root/'THIRD_PARTY_LICENSES', stage/'THIRD-PARTY-LICENSES.txt')
        (stage/'Read me.txt').write_text('Drag Notch Apple into Applications.\nEarly preview: ad-hoc signed, not notarised.\nSetup, source and privacy: https://github.com/leozh0u/notch-apple\n')
        dmg = out/f'Notch-Apple-{arch}.dmg'
        subprocess.run(['hdiutil', 'create', '-volname', 'Notch Apple', '-srcfolder', str(stage), '-format', 'UDZO', '-ov', str(dmg)], check=True)
        subprocess.run(['hdiutil', 'verify', str(dmg)], check=True, stdout=subprocess.DEVNULL)
files = sorted([*out.glob('*.dmg'), *out.glob('*.zip')])
(out/'SHA256SUMS.txt').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in files))
for path in files:
    print(f'{path.name}: {path.stat().st_size:,} bytes')
