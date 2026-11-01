#!/usr/bin/env python3
"""Exercise the packaged unit with an inert workspace on an isolated Linux stand."""

import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import socket
import subprocess
import sys
import time
import uuid
import zipfile

# systemd's public SD_MESSAGE_UNIT_OUT_OF_MEMORY identifier, independent of
# log wording and whether a reload's final service result is signal/oom-kill.
OOM_EVENT = "fe6faa94e7774663a0da52717891d8ef"


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=20).strip()


def properties(unit):
    return dict(line.split("=", 1) for line in run(
        "systemctl", "show", unit, "-p", "MainPID", "-p", "NRestarts",
        "-p", "ActiveState", "-p", "Result", "-p", "MemoryMax",
        "-p", "MemorySwapMax", "-p", "OOMPolicy", "-p", "ControlGroup",
    ).splitlines())


def snapshot(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob("*") if p.is_file() and p.suffix in (".json", ".zip")}


def status(root, binding):
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(2)
        client.connect(str(root / "runner.sock"))
        client.sendall((json.dumps({**binding, "command": "status"}) + "\n").encode())
        reply = b""
        while b"\n" not in reply:
            chunk = client.recv(65536)
            if not chunk:
                break
            reply += chunk
        response = json.loads(reply)
        assert response.get("ok") is True, response
        return response["result"]


def main():
    executable, service, fixture = map(lambda p: Path(p).resolve(), sys.argv[1:])
    assert os.geteuid() == 0, "Use a disposable privileged Linux test stand"
    assert not (fixture / "credentials.json").exists(), "No credentials allowed"
    binding = json.loads((fixture / "runner.json").read_text())
    record, = json.loads((fixture / "Plugins/registry.json").read_text())
    with zipfile.ZipFile(fixture / "Plugins" / record["storedFileName"]) as package:
        capabilities = set(json.loads(package.read("plugin/manifest.json"))["capabilities"])
    assert capabilities <= {"workspace.render", "workspace.continue",
                            "state.plugin.read_write", "workspace.schedule"}
    available = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines()
                     if line.startswith("MemAvailable:"))
    assert available >= 384 * 1024, "Insufficient spare RAM for a contained 256 MiB test"

    name = "hivra-memory-test-" + uuid.uuid4().hex[:12]
    unit = name + ".service"
    unit_file = Path("/run/systemd/system") / unit
    root = Path("/var/lib") / name
    binaries = Path("/opt") / name
    created_user = False
    try:
        try:
            account = pwd.getpwnam("hivra-workspace")
        except KeyError:
            run("useradd", "--system", "--user-group", "--no-create-home",
                "--shell", "/usr/sbin/nologin", "hivra-workspace")
            created_user = True
            account = pwd.getpwnam("hivra-workspace")
        shutil.copytree(fixture, root, ignore=shutil.ignore_patterns("runner.sock"))
        for path in [root, *root.rglob("*")]:
            assert not path.is_symlink()
            os.chown(path, account.pw_uid, account.pw_gid)
            os.chmod(path, 0o700 if path.is_dir() else 0o600)
        binaries.mkdir(mode=0o755)
        for file in (executable, executable.parent / "libhivra_ffi.so"):
            shutil.copy2(file, binaries / file.name)
        allocator = binaries / "allocate.py"
        allocator.write_text("import time\nblocks=[]\nfor _ in range(64):\n"
                             " block=bytearray(8*1024*1024)\n"
                             " for offset in range(0,len(block),4096): block[offset]=1\n"
                             " blocks.append(block)\n time.sleep(.01)\n"
                             "raise RuntimeError('Memory limit was not enforced')\n")
        # Only paths and test containment change. Resource/OOM/restart policy
        # comes directly from the same unit shipped inside the runner archive.
        unit_file.write_text(service.read_text() + "\n[Service]\nStateDirectory=\n"
                             f"StateDirectory={name}\nStateDirectoryMode=0700\nExecStart=\n"
                             f"ExecStart={binaries / executable.name} serve {root}\n"
                             f"ExecReload=/usr/bin/python3 {allocator}\n"
                             "PrivateNetwork=yes\nCPUQuota=25%\nTasksMax=64\nRuntimeMaxSec=90\n"
                             "InaccessiblePaths=-/var/lib/hivra-workspace -/var/www/hivra.space\n")
        run("systemctl", "daemon-reload")
        run("systemctl", "start", unit)
        deadline = time.monotonic() + 10
        while True:
            try:
                before_view = status(root, binding)
                break
            except (OSError, ValueError, AssertionError):
                assert time.monotonic() < deadline, "Fixture runner did not start"
                time.sleep(.1)
        before = properties(unit)
        assert before["MemoryMax"] == "268435456", before
        assert before["MemorySwapMax"] == "0" and before["OOMPolicy"] == "kill", before
        cgroup = Path("/sys/fs/cgroup") / before["ControlGroup"].lstrip("/")
        assert (cgroup / "memory.max").read_text().strip() == "268435456"
        assert (cgroup / "memory.swap.max").read_text().strip() == "0"
        assert (cgroup / "memory.oom.group").read_text().strip() == "1"
        durable = snapshot(root)
        started = time.monotonic()
        run("systemctl", "reload", "--no-block", unit)
        oom_at = None
        events = {}
        while time.monotonic() - started < 60:
            current = properties(unit)
            if current["Result"] != "success" and oom_at is None:
                entries = run("journalctl", "-u", unit, "MESSAGE_ID=" + OOM_EVENT,
                              "--no-pager", "-o", "json")
                if entries:
                    event = json.loads(entries.splitlines()[-1])
                    oom_at = int(event["__MONOTONIC_TIMESTAMP"]) / 1_000_000
            try:
                for line in (cgroup / "memory.events").read_text().splitlines():
                    key, value = line.split()
                    events[key] = max(events.get(key, 0), int(value))
            except FileNotFoundError:
                pass
            if current["ActiveState"] == "active" and current["MainPID"] not in ("0", before["MainPID"]):
                try:
                    after_view = status(root, binding)
                    break
                except (OSError, ValueError, AssertionError):
                    pass
            time.sleep(.05)
        else:
            raise AssertionError("Runner did not recover after contained memory exhaustion")
        assert oom_at is not None and int(current["NRestarts"]) >= 1, current
        assert snapshot(root) == durable, "OOM recovery changed durable state or authority"
        for key in ("mode", "enabled", "running", "active", "revoked", "revision",
                    "expires_at_ms", "scope", "access", "credentials"):
            assert after_view["view"]["execution"][key] == before_view["view"]["execution"][key]
        assert current["MemoryMax"] == "268435456" and current["MemorySwapMax"] == "0"
        print(json.dumps({"passed": True, "memory_max_bytes": int(current["MemoryMax"]),
                          "oom_policy": current["OOMPolicy"], "memory_events": events,
                          "systemd_oom_event_observed": OOM_EVENT,
                          "restart_count": int(current["NRestarts"]),
                          "recovery_seconds_after_oom": round(time.monotonic() - oom_at, 2),
                          "durable_state_and_grant_unchanged": True, "provider_requests": 0}))
    except Exception:
        diagnostics = {str(p): {"mode": oct(p.stat().st_mode & 0o777),
                               "uid": p.stat().st_uid, "gid": p.stat().st_gid}
                       for p in (root, root / "runner.lock") if p.exists()}
        print(json.dumps({"fixture_permissions": diagnostics,
                          "unit": properties(unit)}), file=sys.stderr)
        print(run("journalctl", "-u", unit, "-n", "12", "--no-pager", "-o", "cat"),
              file=sys.stderr)
        raise
    finally:
        try:
            subprocess.run(["systemctl", "stop", unit], capture_output=True, timeout=20)
        except subprocess.TimeoutExpired:
            run("systemctl", "kill", "--kill-whom=all", "--signal=SIGKILL", unit)
            run("systemctl", "stop", unit)
        subprocess.run(["systemctl", "reset-failed", unit], capture_output=True, timeout=10)
        unit_file.unlink(missing_ok=True)
        run("systemctl", "daemon-reload")
        shutil.rmtree(root, ignore_errors=True)
        shutil.rmtree(binaries, ignore_errors=True)
        if created_user:
            run("userdel", "hivra-workspace")


if __name__ == "__main__":
    main()
