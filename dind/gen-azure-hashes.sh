#!/bin/sh
# Regenerate dind/azure-cli-requirements.txt: a pip --require-hashes lockfile pinning
# azure-cli and its full transitive dependency tree to exact versions + PyPI sha256 hashes.
# Run after bumping AZURE_CLI_VERSION so the dind CLOUD=azure variant installs verified deps.
#
# Runs the real install in a clean Alpine 3.24 (the dind base) container to resolve the
# exact tree, then reads each file's sha256 from the PyPI JSON API (so the hashes match
# whatever pip downloads on any arch). Usage, from the repo root:
#
#   docker run --rm \
#     -v "$PWD/dind/gen-azure-hashes.sh:/gen.sh:ro" \
#     -v "$PWD/dind:/out" \
#     -e AZURE_CLI_VERSION=2.88.0 \
#     alpine:3.24 sh /gen.sh
#
# (Bump the alpine tag to match the dind base's Alpine version when it changes.)
set -eu
AZURE_CLI_VERSION="${AZURE_CLI_VERSION:-2.88.0}"

apk add --no-cache python3 py3-pip >/dev/null
apk add --no-cache --virtual .bd gcc musl-dev python3-dev libffi-dev openssl-dev linux-headers make cargo >/dev/null

python3 -m venv /venv
/venv/bin/pip install --no-cache-dir --upgrade pip >/dev/null 2>&1
/venv/bin/pip install --no-cache-dir "azure-cli==${AZURE_CLI_VERSION}" >/dev/null 2>&1

# Exact resolved versions. Use `pip list` (not `pip freeze`, which hides
# setuptools/wheel) and drop only pip itself: azure-cli has a runtime dep on setuptools,
# so under --require-hashes it too must be pinned.
/venv/bin/pip list --format=freeze | grep -v -iE '^pip==' > /tmp/frozen.txt

/venv/bin/python3 - "$AZURE_CLI_VERSION" <<'PY'
import json, sys, urllib.request
azver = sys.argv[1]
out = [
    "# Generated: pip --require-hashes lockfile for azure-cli=={} on Alpine 3.24 (musl).".format(azver),
    "# Regenerate with dind/gen-azure-hashes.sh after bumping AZURE_CLI_VERSION.",
    "# Every resolved dependency is pinned to an exact version + all its PyPI sha256 hashes.",
]
for line in open("/tmp/frozen.txt"):
    line = line.strip()
    if not line or "==" not in line:
        continue
    name, ver = line.split("==", 1)
    data = json.load(urllib.request.urlopen(
        "https://pypi.org/pypi/{}/{}/json".format(name, ver), timeout=60))
    hashes = sorted({f["digests"]["sha256"] for f in data["urls"]})
    if not hashes:
        raise SystemExit("no PyPI hashes for %s==%s" % (name, ver))
    block = "{}=={}".format(name, ver)
    for h in hashes:
        block += " \\\n    --hash=sha256:{}".format(h)
    out.append(block)
open("/out/azure-cli-requirements.txt", "w").write("\n".join(out) + "\n")
print("wrote", len(out) - 3, "pinned packages")
PY
