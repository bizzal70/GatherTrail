"""Runs the addon's tests in real Lua 5.1 against a fake WoW API.

Setup (once):  pip install lupa
Run:           python tests/run.py

The fake API (wow_stub.lua) only proves the addon's own logic. It says
nothing about whether the real client's API behaves the way the stub does.
"""
import pathlib
import sys

import lupa.lua51 as lua51

TESTS = pathlib.Path(__file__).resolve().parent
ADDON = TESTS.parent   # the addon's files sit at the top of the project

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.globals().ADDON_DIR = ADDON.as_posix()
lua.execute((TESTS / "wow_stub.lua").read_text(encoding="utf-8"))
try:
    lua.execute((TESTS / "test_gathertrail.lua").read_text(encoding="utf-8"))
    print("test_gathertrail.lua: ALL PASSED")
except Exception as error:
    print(f"test_gathertrail.lua: ERROR: {error}")
    sys.exit(1)
