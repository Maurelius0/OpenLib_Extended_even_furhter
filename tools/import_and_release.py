"""Reassemble verified backup parts, import source, and publish a test release."""
from pathlib import Path, PurePosixPath
import hashlib, json, os, subprocess, zipfile

def run(*args):
    return subprocess.check_output(args, text=True).strip()

meta = json.loads(Path('backups/manifest.json').read_text())
stage = Path('.release-staging')
stage.mkdir(exist_ok=True)
assets = []
for item in meta['artifacts']:
    path = stage / item['name']
    digest = hashlib.sha256()
    with path.open('wb') as out:
        for name in item['parts']:
            part = Path(name).read_bytes()
            digest.update(part)
            out.write(part)
    if path.stat().st_size != item['bytes'] or digest.hexdigest() != item['sha256']:
        raise RuntimeError('Backup verification failed: ' + item['name'])
    assets.append(path)

source = next(p for p in assets if p.suffix == '.zip')
paths = []
with zipfile.ZipFile(source) as archive:
    for info in archive.infolist():
        if info.is_dir():
            continue
        p = PurePosixPath(info.filename)
        if p.is_absolute() or '..' in p.parts:
            raise RuntimeError('Unsafe source path')
        rel = p.relative_to(meta['source_prefix'])
        if any(x in {'.git', 'test-signing', 'reader-test-signing'} for x in rel.parts) or rel.suffix in {'.keystore', '.jks'}:
            raise RuntimeError('Signing material must not be published')
        if rel.parts[:2] == ('.github', 'workflows'):
            raise RuntimeError('Unexpected inherited workflow')
        target = Path(*rel.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(archive.read(info))
        paths.append(str(target))

ignore=Path('.gitignore')
if '.release-staging/' not in ignore.read_text():
    ignore.write_text(ignore.read_text()+'\n.release-staging/\n')
    paths.append('.gitignore')

subprocess.run(['git', 'config', 'user.name', 'github-actions[bot]'], check=True)
subprocess.run(['git', 'config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com'], check=True)
subprocess.run(['git', 'add', '--', *paths], check=True)
if subprocess.run(['git', 'diff', '--cached', '--quiet']).returncode:
    subprocess.run(['git', 'commit', '-m', 'chore: import verified source snapshot ' + meta['tag']], check=True)
    subprocess.run(['git', 'push', 'origin', 'HEAD:main'], check=True)
sha = run('git', 'rev-parse', 'HEAD')
notes = stage / 'release-notes.md'
notes.write_text('Test milestone backup. Source code and third-party notices are preserved in this repository. Signing keys are excluded.\n\n'
                 'These are the existing test builds; this backup workflow does not rebuild or validate their runtime behavior.\n\n'
                 + '\n'.join(f"- `{a['name']}` SHA-256: `{a['sha256']}`" for a in meta['artifacts']) + '\n')
# Refuse to overwrite a release or reuse an existing tag.
existing = subprocess.run(['gh', 'release', 'view', meta['tag']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
if existing.returncode == 0:
    raise RuntimeError('Release already exists; refusing to overwrite it')
subprocess.run(['gh', 'release', 'create', meta['tag'], '--target', sha, '--title', meta['title'], '--notes-file', str(notes), '--prerelease', *map(str, assets)], check=True)
print('Verified source import and test release published at ' + sha)

release=json.loads(run('gh','api','repos/'+os.environ['GITHUB_REPOSITORY']+'/releases/tags/'+meta['tag']))
marker={'tag':meta['tag'],'source_commit':sha,'release_url':release['html_url'],'assets':[{'name':a['name'],'bytes':a['size'],'download_url':a['browser_download_url']} for a in release['assets']]}
Path('backups/published.json').write_text(json.dumps(marker,indent=2)+'\n')
subprocess.run(['git','add','backups/published.json'],check=True)
subprocess.run(['git','commit','-m','docs: record verified release downloads '+meta['tag']],check=True)
subprocess.run(['git','push','origin','HEAD:main'],check=True)
