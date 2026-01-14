# NHS Manage Breast Screening Gateway Service

A Python-based DICOM gateway service for NHS breast screening management.

## Overview

This service provides DICOM network connectivity and data management for breast screening systems.

## Features

- DICOM network protocol support via pynetdicom
- DICOM file parsing and manipulation via pydicom
- Configurable service parameters

## Installation

The service can be packaged and deployed using multiple strategies:

- **ZIP Package**: Portable Python environment with directory junction deployment
- **MSI Package**: Traditional Windows Installer
- **EXE Package**: Single-file executable via PyInstaller

## Development

### Requirements

- Python >= 3.14
- uv package manager

### Setup

```bash
uv venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
uv pip install -e .
```

### Testing

```bash
pytest tests/ -v
```

## Deployment

See the packaging scripts in `scripts/powershell/` for build and deployment options.

## License

MIT
