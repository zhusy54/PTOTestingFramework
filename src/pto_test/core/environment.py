"""Environment variable management module

This module provides a unified interface for accessing environment variables,
supporting flexible dependency path configuration. It prioritizes environment
variables, then falls back to the default 3rdparty/ directory for backward compatibility.
"""

import os
from pathlib import Path
from typing import Optional


class PtoEnvironmentError(Exception):
    """Environment configuration error exception"""

    pass


def get_framework_root() -> Path:
    """Get the testing framework root directory

    Returns:
        Path: Framework root directory path
    """
    if "FRAMEWORK_ROOT" in os.environ:
        return Path(os.environ["FRAMEWORK_ROOT"])
    # Default: infer from current file (src/pto_test/core/environment.py -> root)
    return Path(__file__).parent.parent.parent.parent


def get_pypto_root() -> Optional[Path]:
    """Get PyPTO root directory (if available)

    Search order:
    1. PYPTO_ROOT environment variable
    2. 3rdparty/pypto directory (backward compatible)

    Returns:
        Optional[Path]: PyPTO root directory, or None if not found
    """
    if "PYPTO_ROOT" in os.environ:
        return Path(os.environ["PYPTO_ROOT"])
    # Backward compatibility: check 3rdparty path
    fallback = get_framework_root() / "3rdparty" / "pypto"
    if fallback.exists():
        return fallback
    return None


def get_simpler_root() -> Optional[Path]:
    """Get Simpler root directory (if available)

    Search order:
    1. SIMPLER_ROOT environment variable
    2. 3rdparty/simpler directory (backward compatible)

    Returns:
        Optional[Path]: Simpler root directory, or None if not found
    """
    if "SIMPLER_ROOT" in os.environ:
        return Path(os.environ["SIMPLER_ROOT"])
    # Backward compatibility: check 3rdparty path
    fallback = get_framework_root() / "3rdparty" / "simpler"
    if fallback.exists():
        return fallback
    return None


def require_pypto_root() -> Path:
    """Get PyPTO root directory (required)

    Raises an exception with solutions if PyPTO is not found.

    Returns:
        Path: PyPTO root directory

    Raises:
        PtoEnvironmentError: When PyPTO is not found
    """
    root = get_pypto_root()
    if root is None:
        raise PtoEnvironmentError(
            "PyPTO not found. Please either:\n"
            "  1. Set PYPTO_ROOT environment variable, or\n"
            "  2. Run: ./build_and_install.sh --with-pypto"
        )
    return root


def require_simpler_root() -> Path:
    """Get Simpler root directory (required)

    Raises an exception with solutions if Simpler is not found.

    Returns:
        Path: Simpler root directory

    Raises:
        PtoEnvironmentError: When Simpler is not found
    """
    root = get_simpler_root()
    if root is None:
        raise PtoEnvironmentError(
            "Simpler not found. Please either:\n"
            "  1. Set SIMPLER_ROOT environment variable, or\n"
            "  2. Run: ./build_and_install.sh --with-runtime"
        )
    return root


def get_pypto_python_path() -> Optional[Path]:
    """Get PyPTO Python package path

    Returns:
        Optional[Path]: PyPTO Python package path (pypto/python directory)
    """
    root = get_pypto_root()
    if root is None:
        return None
    return root / "python"


def get_simpler_python_path() -> Optional[Path]:
    """Get Simpler Python package path

    Returns:
        Optional[Path]: Simpler Python package path (simpler/python directory)
    """
    root = get_simpler_root()
    if root is None:
        return None
    return root / "python"


def get_simpler_scripts_path() -> Optional[Path]:
    """Get Simpler scripts path

    Returns:
        Optional[Path]: Simpler scripts path (simpler/examples/scripts directory)
    """
    root = get_simpler_root()
    if root is None:
        return None
    return root / "examples" / "scripts"
