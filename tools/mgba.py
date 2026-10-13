"""lldb helper: build, (re)launch mGBA with its GDB server, wait for it to listen.

mGBA 0.10's GDB server only serves one session per launch (later connections
hang or get reset), so every debug session gets a fresh mGBA.

Usage from lldb (before `target create`, so lldb loads the fresh ELF):
    command script import tools/mgba.py
"""

import os
import subprocess
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROM = os.path.join(ROOT, "zig-out", "bin", "txustris.gba")
PORT = 2345


def listening():
    # Don't probe by connecting: a dropped connection wedges mGBA's stub.
    r = subprocess.run(["lsof", "-nP", f"-iTCP:{PORT}", "-sTCP:LISTEN"], capture_output=True)
    return r.returncode == 0


def __lldb_init_module(debugger, internal_dict):
    # -Ddebug: unoptimized, so stepping and locals behave.
    build = subprocess.run(["zig", "build", "-Ddebug"], cwd=ROOT, capture_output=True, text=True)
    if build.returncode != 0:
        print(build.stderr)
        raise RuntimeError("zig build failed")

    subprocess.run(["pkill", "-f", f"mGBA -g {ROM}"])
    deadline = time.time() + 5
    while listening() and time.time() < deadline:
        time.sleep(0.1)

    subprocess.Popen(["mgba", "-g", ROM], cwd=ROOT, start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 15
    while not listening():
        if time.time() > deadline:
            raise RuntimeError(f"mGBA didn't open port {PORT}")
        time.sleep(0.1)
    print(f"mGBA listening on :{PORT}")
