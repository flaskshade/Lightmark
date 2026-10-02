#!/usr/bin/env python3
"""Create one signed update entry; private signing material stays in Keychain."""
import pathlib, plistlib, subprocess, sys, xml.etree.ElementTree as ET
from email.utils import formatdate

root = pathlib.Path(__file__).resolve().parent.parent
folder = pathlib.Path(sys.argv[1])
info = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
tools = root / '.build/artifacts/sparkle/Sparkle/bin'
public = subprocess.check_output([str(tools/'generate_keys'), '--account', 'lightmark-updates', '-p'], text=True).strip()
if public != info['SUPublicEDKey']:
    raise SystemExit('Sparkle Keychain public key does not match Info.plist; stop publication.')
archive = folder / 'Lightmark.zip'
signature = subprocess.check_output([str(tools/'sign_update'), '--account', 'lightmark-updates', '-p', str(archive)], text=True).strip()
subprocess.run([str(tools/'sign_update'), '--account', 'lightmark-updates', '--verify', str(archive), signature], check=True)
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
name = f'Lightmark-{version}-{build}.zip'
(folder/name).write_bytes(archive.read_bytes())
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
feed = ET.Element('rss', version='2.0')
channel = ET.SubElement(feed, 'channel')
ET.SubElement(channel, 'title').text = 'Lightmark Updates'
ET.SubElement(channel, 'link').text = 'https://trylightmark.com/'
ET.SubElement(channel, 'description').text = 'Signed Lightmark updates'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'Lightmark {version}'
ET.SubElement(item, 'pubDate').text = formatdate(usegmt=True)
ET.SubElement(item, f'{{{ns}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
ET.SubElement(item, f'{{{ns}}}fullReleaseNotesLink').text = 'https://trylightmark.com/changelog/'
ET.SubElement(item, 'enclosure', {
    'url': f'https://trylightmark.com/downloads/{name}',
    'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
    f'{{{ns}}}version': build, f'{{{ns}}}shortVersionString': version,
    f'{{{ns}}}edSignature': signature,
})
ET.indent(feed)
ET.ElementTree(feed).write(folder/'appcast.xml', encoding='utf-8', xml_declaration=True)
