# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller Spec File for DICOM Gateway Mock Service

This spec file creates a single-file executable bundling:
- mock_service.py
- All Python dependencies from requirements.txt
- Config file as a data file

Usage:
    pyinstaller build.spec
"""

import os
from pathlib import Path

# Get the repository root directory (3 levels up from scripts/powershell/exe)
repo_root = Path(os.getcwd()).resolve().parent.parent.parent
src_dir = repo_root / 'src'

# Analysis: Scan the script and dependencies
a = Analysis(
    [str(src_dir / 'mock_service.py')],
    pathex=[],
    binaries=[],
    datas=[
        (str(src_dir / 'config.yaml'), '.'),  # Include config file
    ],
    hiddenimports=[
        'pydantic',
        'yaml',
        'numpy',
        'PIL',
        'requests',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

# PYZ: Create a Python archive
pyz = PYZ(a.pure)

# EXE: Create the executable
exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='DicomGatewayMock',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,  # Use UPX compression if available
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,  # Console application (shows logs)
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=None,
)
