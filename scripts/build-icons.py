#!/usr/bin/env python3
"""Package the dark artwork with macOS proportions in every appearance."""
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
catalog = root / '.build' / 'IconAssets.xcassets'
if catalog.exists():
    shutil.rmtree(catalog)
app = catalog / 'AppIcon.appiconset'
artwork = catalog / 'LightmarkIcon.imageset'
app.mkdir(parents=True)
artwork.mkdir(parents=True)
info = {'version': 1, 'author': 'xcode'}
(catalog / 'Contents.json').write_text(json.dumps({'info': info}))
source = root / 'App icons' / 'Lightmark app icon-iOS-Dark-1024@1x.png'
prepared = artwork / 'Lightmark.png'
subprocess.run(['swift', str(root / 'scripts' / 'prepare-icon.swift'), str(source), str(prepared)], check=True)
images = []
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        filename = f'icon-{size}@{scale}x.png'
        subprocess.run(['sips', '-z', str(size * scale), str(size * scale), str(prepared),
                        '--out', str(app / filename)], check=True, stdout=subprocess.DEVNULL)
        images.append({'idiom': 'mac', 'size': f'{size}x{size}', 'scale': f'{scale}x', 'filename': filename})
(app / 'Contents.json').write_text(json.dumps({'images': images, 'info': info}, indent=2))
(artwork / 'Contents.json').write_text(json.dumps({'images': [{'idiom': 'universal', 'filename': 'Lightmark.png'}],
                                                'info': info}, indent=2))
