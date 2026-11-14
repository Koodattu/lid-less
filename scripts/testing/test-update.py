#!/usr/bin/env python3
"""Exercise Sparkle replacement/relaunch in a uniquely identified, disposable app."""
import functools
import http.server
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
import sys

mode = sys.argv[1] if len(sys.argv) > 1 else 'valid'
assert mode in ['valid', 'bad-feed', 'bad-archive']
root = Path(__file__).resolve().parents[2]
source = root / '.build/preview/Lid Less.app'
tools = root / '.build/artifacts/sparkle/Sparkle/bin'
work = Path(tempfile.mkdtemp(prefix='update-test.', dir=root / '.build'))
print(f'Fixture directory: {work}', flush=True)

def run(*args):
    subprocess.run([str(a) for a in args], check=True)

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(work / 'feed')))
threading.Thread(target=server.serve_forever, daemon=True).start()
url = f'http://127.0.0.1:{server.server_port}/'
identifier = 'dev.lid-less.update-test.' + uuid.uuid4().hex
result = work / 'relaunched.txt'
(work / 'feed').mkdir()
for folder, version in [('installed', '1'), ('candidate', '2')]:
    target = work / folder / 'Update Fixture.app'
    run('ditto', source, target)
    shutil.copy2(root / '.build/update-fixture', target / 'Contents/MacOS/LidLess')
    plist = target / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info.update(CFBundleIdentifier=identifier, CFBundleName='Update Fixture', CFBundleDisplayName='Update Fixture',
                CFBundleVersion=version, CFBundleShortVersionString=f'0.0.{version}',
                SUFeedURL=url+'appcast.xml', FixtureResultPath=str(result),
                NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
    plist.write_bytes(plistlib.dumps(info))
    run('codesign', '--force', '--sign', '-', target)
    run('codesign', '--verify', '--deep', '--strict', target)
run('ditto', '-c', '-k', '--keepParent', work / 'candidate/Update Fixture.app', work / 'feed/update.zip')
run(tools / 'generate_appcast', '--account', 'dev.lid-less.app', '--maximum-deltas', '0', '--download-url-prefix', url, work / 'feed')
if mode == 'bad-feed':
    feed = work / 'feed/appcast.xml'
    feed.write_bytes(feed.read_bytes().replace(b'<title>0.0.2</title>', b'<title>tampered</title>'))
elif mode == 'bad-archive':
    archive = work / 'feed/update.zip'
    data = bytearray(archive.read_bytes())
    data[len(data)//2] ^= 1
    archive.write_bytes(data)
log = open(work / 'fixture.log', 'w')
process = subprocess.Popen([str(work / 'installed/Update Fixture.app/Contents/MacOS/LidLess')], stdout=log, stderr=log)
try:
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline and not result.exists():
        if process.poll() not in (None, 0): break
        time.sleep(0.25)
    log.flush()
    print((work / 'fixture.log').read_text(), flush=True)
    info = plistlib.loads((work / 'installed/Update Fixture.app/Contents/Info.plist').read_bytes())
    if mode == 'valid':
        assert result.exists(), 'Updated app did not relaunch; inspect fixture.log'
        assert info['CFBundleVersion'] == '2', 'Bundle was not replaced'
        print('PASS: signed feed, download, validation, replacement, and relaunch of ad-hoc app.', flush=True)
    else:
        assert process.poll() == 3, 'Expected Sparkle to reject the tampered update'
        assert not result.exists() and info['CFBundleVersion'] == '1', 'Tampered update was installed'
        print(f'PASS: {mode} rejected; original app unchanged.', flush=True)
    run('codesign', '--verify', '--deep', '--strict', work / 'installed/Update Fixture.app')
finally:
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=10)
    server.shutdown()
    log.close()
