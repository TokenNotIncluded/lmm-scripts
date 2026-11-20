#!/usr/bin/env python3
"""Bind the Windows diagnostic to immutable product and control checkouts."""
import hashlib
import json
import os
import stat
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

PRODUCT_COMMIT = "40c473f8c1a14412cbd17c832babf182802fd974"
PRODUCT_TREE = "fcb4f43a666fb6b454fa938814975de5874a1e1c"
EXPECTED_FILES = {
    ".github/workflows/test.yml": {
        "git_blob": "96b4532aaad12f9ef27dec26dfd603df0cbc6719",
        "sha256": "b0ad6122751fa9a9c79f81d549ac9959414831da89f8c05bc1a052f4bdce99ab",
        "bytes": 6166
    },
    "README.md": {
        "git_blob": "ab446486bddd17811e0fd4fab00f527f84736ce9",
        "sha256": "ce414394b1f8c3f73695ba23b3d370bdd2500d2943e9b6bb8798a3e1c7da2593",
        "bytes": 22377
    },
    "dsh.ps1": {
        "git_blob": "877c0ba1299cbdc3340fb44c9d05dd02721c2061",
        "sha256": "3303d6b68f19d4d3b84231d1627d7fb76133d8b6f4b7bc10ba9cfd3fb06ca5c2",
        "bytes": 24138
    },
    "menu.ps1": {
        "git_blob": "0648d36f6ccf1479954d6529f437fffac26e9d91",
        "sha256": "10580ce626ee55d8cc02bb2dbabfb0b16e4e58b469a2e02563ef0bc4205e1681",
        "bytes": 3026
    },
    "test.ps1": {
        "git_blob": "2461f152989ff88f64f760ce5fc48e26ba6953ae",
        "sha256": "874d6b9dd9f34b2584dbb28b00c37af23280f144fc46c7a5c283290a5649df3a",
        "bytes": 18707
    },
    "test-dsh-managed.ps1": {
        "git_blob": "a377723927939df9f85038b3ea0ccd73c7d506bd",
        "sha256": "d45f7d49f26a91d0addb44b15fe90f8171d19bd08e9b1e819b7dec9b178a18bb",
        "bytes": 7140
    },
    "pi.ps1": {
        "git_blob": "2a8c3857753475c0458d66fe3b56672992f68508",
        "sha256": "0d356f3edb39285b7a499b98e50c249dca64d3036e8938c6b7457f792e00fb30",
        "bytes": 461
    }
}


class ProofFailure(Exception):
    pass


def git(root, *args):
    result = subprocess.run(
        ["git", "-C", str(root), *args], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20, check=False,
    )
    if result.returncode:
        raise ProofFailure("git-" + args[0] + "-failed")
    return result.stdout


def git_text(root, *args):
    return git(root, *args).decode("utf-8").strip()


def snapshot(root, expected_commit, expected_tree=None):
    if Path(git_text(root, "rev-parse", "--show-toplevel")).resolve() != root:
        raise ProofFailure("wrong-checkout-root")
    commit = git_text(root, "rev-parse", "HEAD")
    tree = git_text(root, "rev-parse", "HEAD^{tree}")
    if commit != expected_commit or (expected_tree and tree != expected_tree):
        raise ProofFailure("wrong-checkout-identity")
    if git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all"):
        raise ProofFailure("checkout-not-clean")
    files = []
    for entry in git(root, "ls-tree", "-r", "-z", "--full-tree", "HEAD").split(b"\0"):
        if not entry:
            continue
        metadata, raw_path = entry.split(b"\t", 1)
        mode, kind, expected_blob = metadata.decode("ascii").split()
        path = raw_path.decode("utf-8")
        relative = PurePosixPath(path)
        if relative.is_absolute() or ".." in relative.parts:
            raise ProofFailure("invalid-tracked-path")
        if mode not in ("100644", "100755") or kind != "blob":
            raise ProofFailure("unsupported-tracked-object")
        file = root.joinpath(*relative.parts)
        if not stat.S_ISREG(file.lstat().st_mode) or file.is_symlink():
            raise ProofFailure("tracked-file-not-regular")
        data = file.read_bytes()
        blob = hashlib.sha1(
            b"blob " + str(len(data)).encode("ascii") + b"\0" + data
        ).hexdigest()
        if blob != expected_blob:
            raise ProofFailure("tracked-raw-bytes-differ")
        files.append({
            "path": path, "mode": mode, "type": kind, "git_blob": blob,
            "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
        })
    return {"commit": commit, "tree": tree, "clean": True, "files": files}


def save_json(path, value):
    data = (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)


def main():
    if len(sys.argv) != 5 or sys.argv[1] not in ("before", "after"):
        print("DSH source proof: invalid invocation", file=sys.stderr)
        return 1
    phase = sys.argv[1]
    product, control, evidence = (Path(p).resolve() for p in sys.argv[2:])
    if (
        product == control or product in control.parents or control in product.parents
        or evidence == product or evidence == control
        or product in evidence.parents or control in evidence.parents
    ):
        print("DSH source proof: overlapping roots", file=sys.stderr)
        return 1
    record = {
        "schema": "lmm.dsh-managed-windows-source-proof.v1",
        "phase": phase, "status": "FAIL",
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "expected_product_commit": PRODUCT_COMMIT,
        "expected_product_tree": PRODUCT_TREE,
        "checkout_policy": "Checkout-step-only core.autocrlf=false and core.eol=lf; raw bytes must match Git blobs.",
        "scope": "Windows diagnostic only; 72902 < 50000 remains FAIL.",
    }
    exit_code = 1
    try:
        if phase == "before":
            evidence.mkdir(mode=0o700, parents=False, exist_ok=False)
        else:
            evidence.mkdir(mode=0o700, parents=False, exist_ok=True)
        if os.environ.get("GITHUB_REPOSITORY") != "TokenNotIncluded/lmm-scripts":
            raise ProofFailure("unexpected-repository")
        control_commit = os.environ.get("GITHUB_SHA", "")
        if len(control_commit) != 40 or any(c not in "0123456789abcdef" for c in control_commit):
            raise ProofFailure("invalid-control-commit")
        if Path(__file__).resolve() != control / ".github/scripts/verify-dsh-managed-source.py":
            raise ProofFailure("wrong-proof-program")
        record["product"] = snapshot(product, PRODUCT_COMMIT, PRODUCT_TREE)
        record["control"] = snapshot(control, control_commit)
        actual = {row["path"]: row for row in record["product"]["files"]}
        for path, expected in EXPECTED_FILES.items():
            row = actual.get(path)
            if row is None or any(row[key] != value for key, value in expected.items()):
                raise ProofFailure("product-file-binding-differs")
        if phase == "after":
            previous = json.loads((evidence / "before.json").read_text(encoding="utf-8"))
            if previous.get("status") != "PASS":
                raise ProofFailure("before-proof-not-passed")
            if any(previous.get(key) != record[key] for key in ("product", "control")):
                raise ProofFailure("source-drift")
            record["source_drift"] = False
        record["status"] = "PASS"
        exit_code = 0
    except Exception as error:
        record["error"] = {
            "kind": type(error).__name__,
            "code": str(error) if isinstance(error, ProofFailure) else "source-proof-failed",
        }
    try:
        save_json(evidence / (phase + ".json"), record)
    except Exception:
        print("DSH source proof: receipt-write-failed", file=sys.stderr)
        return 1
    print(json.dumps({"phase": phase, "status": record["status"]}))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
