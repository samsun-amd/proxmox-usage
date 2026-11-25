#!/usr/bin/env python3
"""Exercise the real installer with disposable agent homes and no credentials."""
import os
from pathlib import Path
import subprocess
import tempfile

REPO = Path(__file__).resolve().parent
ENTRY = 'deploy.sh'
SOURCES = {'proxmox-usage': 'skills/proxmox-usage'}
ALWAYS_INSTALL = False


def main():
    for agents in ((), ("claude",), ("codex",), ("claude", "codex")):
        for custom_state in (False, True):
            with tempfile.TemporaryDirectory(prefix="skill install ") as temporary:
                home = Path(temporary)
                for agent in agents:
                    (home / f".{agent}").mkdir()
                env = {"HOME": str(home), "PATH": "/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"}
                if custom_state:
                    env["CODEX_HOME"] = str(home / "custom state")
                checkout = home / "checkout with spaces"
                checkout.symlink_to(REPO)
                command = ["bash", str(checkout / ENTRY)]
                expected = {"claude", "codex"} if ALWAYS_INSTALL else set(agents)
                previous = None
                for _ in range(2):
                    result = subprocess.run(command, env=env, capture_output=True, text=True)
                    assert result.returncode == 0, result.stderr
                    observed = {}
                    for agent, directory in (("claude", ".claude"), ("codex", ".agents")):
                        skills = home / directory / "skills"
                        names = {p.name for p in skills.iterdir()} if skills.exists() else set()
                        assert names == (set(SOURCES) if agent in expected else set()), (agent, names)
                        for name in names:
                            link = skills / name
                            assert link.is_symlink() and not os.path.isabs(os.readlink(link))
                            assert link.resolve() == (REPO / SOURCES[name]).resolve()
                            assert (link / "SKILL.md").is_file()
                            observed[(agent, name)] = (os.readlink(link), link.lstat().st_ino)
                    if previous is not None:
                        assert observed == previous, "second install must be a no-op"
                    previous = observed
                    assert not (home / ".codex/skills").exists()
                    assert not (home / "custom state/skills").exists()

                if "codex" not in expected:
                    continue
                link = home / ".agents/skills" / next(iter(SOURCES))
                for kind in ("file", "directory", "foreign-link", "broken-link"):
                    link.unlink()
                    foreign = home / "foreign" / "amd-llm-gateway" / kind
                    foreign.mkdir(parents=True)
                    if kind == "file":
                        link.write_text("preserve")
                    elif kind == "directory":
                        link.mkdir()
                    else:
                        link.symlink_to(os.path.relpath(foreign / "missing" if kind == "broken-link" else foreign, link.parent))
                    before = os.readlink(link) if link.is_symlink() else None
                    result = subprocess.run(command, env=env, capture_output=True, text=True)
                    assert result.returncode != 0, (kind, result.stdout)
                    if before is not None:
                        assert os.readlink(link) == before
                    elif kind == "directory":
                        assert link.is_dir()
                    else:
                        assert link.read_text() == "preserve"
                    if kind == "directory":
                        link.rmdir()
                    else:
                        link.unlink()
                    link.symlink_to(os.path.relpath(REPO / SOURCES[link.name], link.parent))
                if agents == ("claude", "codex") and not custom_state:
                    link.unlink()
                    tools = home / "bin"
                    tools.mkdir()
                    fake_ln = tools / "ln"
                    fake_ln.write_text("#!/bin/sh\nexit 17\n")
                    fake_ln.chmod(0o755)
                    failed_env = {**env, "PATH": str(tools) + ":/usr/bin:/bin"}
                    result = subprocess.run(command, env=failed_env, capture_output=True, text=True)
                    assert result.returncode != 0, "failed ln must not report success"
    print("PASS: actual defaults, selection, state separation, relative links, no-op and collision preservation")


if __name__ == "__main__":
    main()
