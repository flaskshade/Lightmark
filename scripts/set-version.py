#!/usr/bin/env python3
"""Explicit app version/build bump; Info.plist remains authoritative."""
import plistlib,re,sys
from pathlib import Path
if len(sys.argv)!=3 or not re.fullmatch(r'\d+\.\d+\.\d+',sys.argv[1]) or not re.fullmatch(r'[1-9]\d*',sys.argv[2]):
    raise SystemExit('Usage: python3 scripts/set-version.py VERSION BUILD_NUMBER')
p=Path(__file__).resolve().parent.parent/'Resources/Info.plist'
s=p.read_text(); old=plistlib.loads(s.encode())
if int(sys.argv[2])<=int(old['CFBundleVersion']):
    raise SystemExit('Build number must increase')
for key,value in [('CFBundleShortVersionString',sys.argv[1]),('CFBundleVersion',sys.argv[2])]:
    s=re.sub(r'(<key>'+key+r'</key>\s*<string>)[^<]+(</string>)',lambda m:m[1]+value+m[2],s)
p.write_text(s)
print(f'Version {sys.argv[1]}, build {sys.argv[2]}')
