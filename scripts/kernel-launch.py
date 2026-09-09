"""Launch ipykernel in the resolved project root, independent of Neovim's cwd."""

import os
import runpy
import sys

os.chdir(sys.argv.pop(1))
runpy.run_module("ipykernel_launcher", run_name="__main__")
