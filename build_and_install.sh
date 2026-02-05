#!/bin/bash
# Copyright (c) PyPTO Contributors.
# Build script for pto-testing-framework
# Supports flexible dependency management through environment variables

set -e  # Exit on error

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PTO Testing Framework Build Script${NC}"
echo -e "${BLUE}========================================${NC}"

# Get project root directory (where this script is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

# Detect Python executable
if [ -n "$PYTHON_EXE" ]; then
    # Use environment variable if set
    :
elif command -v python3 &> /dev/null; then
    PYTHON_EXE=$(command -v python3)
else
    echo -e "${RED}Error: python3 not found${NC}"
    exit 1
fi

# Default values
BUILD_TYPE="RelWithDebInfo"
CLEAN_BUILD=false
INSTALL_PACKAGE=false
JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
PYPTO_REPO="https://github.com/hw-native-sys/pypto"
SIMPLER_REPO="https://github.com/ChaoWao/simpler"
PYPTO_BRANCH="main"
SIMPLER_BRANCH="main"

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "The build script automatically detects and builds available dependencies."
    echo ""
    echo "Build Configuration:"
    echo "  -t, --type TYPE        Build type: Debug, Release, RelWithDebInfo (default: RelWithDebInfo)"
    echo "  -c, --clean            Clean build directory before building"
    echo "  -i, --install          Install pto-test package in editable mode"
    echo "  -j, --jobs N           Number of parallel jobs (default: auto-detect)"
    echo ""
    echo "Dependency Configuration:"
    echo "  --pypto-repo URL       PyPTO repository URL (default: $PYPTO_REPO)"
    echo "  --simpler-repo URL     Simpler repository URL (default: $SIMPLER_REPO)"
    echo "  --pypto-branch NAME    PyPTO branch/tag (default: $PYPTO_BRANCH)"
    echo "  --simpler-branch NAME  Simpler branch/tag (default: $SIMPLER_BRANCH)"
    echo ""
    echo "Other Options:"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  FRAMEWORK_ROOT         Override framework root directory"
    echo "  PYPTO_ROOT             Use existing PyPTO (skips build, uses pre-built version)"
    echo "  SIMPLER_ROOT           Use existing Simpler (skips build, uses pre-built version)"
    echo ""
    echo "Dependency Auto-Detection Priority:"
    echo "  1. Environment variable (PYPTO_ROOT/SIMPLER_ROOT) - uses pre-built, skips building"
    echo "  2. Existing 3rdparty/ directory - will build if needed"
    echo "  3. pip editable install (pip install -e) - uses existing installation"
    echo "  4. Auto-clone from GitHub (if not found) - will build after cloning"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-detect and build all available dependencies"
    echo "  $0 --clean                            # Clean build with auto-detection"
    echo "  $0 --type Debug                       # Debug build with auto-detection"
    echo "  $0 --clean --install                  # Clean build and install package"
    echo ""
    echo "  # Use existing pre-built PyPTO (via PYTHONPATH, no pip install):"
    echo "  export PYPTO_ROOT=/path/to/pypto  # Should already have python/pypto/pypto_core*.so"
    echo "  $0"
    echo ""
    echo "  # Or let script auto-detect pip installed version:"
    echo "  cd /path/to/pypto && pip install -e ."
    echo "  cd /path/to/pto-testing-framework"
    echo "  $0  # Will auto-detect and use pip installed PyPTO"
    echo ""
    echo "After building, set up the environment:"
    echo "  source ${PROJECT_ROOT}/build/setup_env.sh"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --pypto-repo)
            PYPTO_REPO="$2"
            shift 2
            ;;
        --simpler-repo)
            SIMPLER_REPO="$2"
            shift 2
            ;;
        --pypto-branch)
            PYPTO_BRANCH="$2"
            shift 2
            ;;
        --simpler-branch)
            SIMPLER_BRANCH="$2"
            shift 2
            ;;
        -t|--type)
            BUILD_TYPE="$2"
            shift 2
            ;;
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -i|--install)
            INSTALL_PACKAGE=true
            shift
            ;;
        -j|--jobs)
            JOBS="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            print_usage
            exit 1
            ;;
    esac
done

# Validate build type
if [[ ! "$BUILD_TYPE" =~ ^(Debug|Release|RelWithDebInfo)$ ]]; then
    echo -e "${RED}Error: Invalid build type '$BUILD_TYPE'${NC}"
    echo "Valid types: Debug, Release, RelWithDebInfo"
    exit 1
fi

echo ""
echo -e "${BLUE}Build Configuration:${NC}"
echo "  Build type:        ${BUILD_TYPE}"
echo "  Clean build:       ${CLEAN_BUILD}"
echo "  Install package:   ${INSTALL_PACKAGE}"
echo "  Parallel jobs:     ${JOBS}"
echo ""

# Function to resolve dependency path
# Priority: Environment variable -> Existing 3rdparty -> pip editable install -> Clone to 3rdparty
# Returns: "path:source" on success (e.g., "/path/to/pypto:environment"), ":notfound" on failure
resolve_dependency() {
    local dep_name=$1
    local env_var=$2
    local fallback_path=$3
    local repo_url=$4
    local branch=$5
    
    # Check environment variable first
    if [ -n "${!env_var}" ]; then
        local dep_path="${!env_var}"
        if [ -d "$dep_path" ]; then
            echo -e "${GREEN}✓ $dep_name found (environment variable)${NC}" >&2
            echo "${dep_path}:environment"
            return 0
        else
            echo -e "${YELLOW}⚠ $env_var is set but path does not exist: ${dep_path}${NC}" >&2
        fi
    fi
    
    # Check 3rdparty directory
    if [ -d "$fallback_path" ]; then
        echo -e "${GREEN}✓ $dep_name found (3rdparty directory)${NC}" >&2
        echo "${fallback_path}:3rdparty"
        return 0
    fi
    
    # Try to detect pip editable install
    local package_name_lower=$(echo "$dep_name" | tr '[:upper:]' '[:lower:]')
    local pip_path=$($PYTHON_EXE -c "
import sys
try:
    import ${package_name_lower}
    import os
    # For editable installs, the package __file__ points to the source
    pkg_file = ${package_name_lower}.__file__
    if pkg_file:
        # Go up to find the root directory (usually 2 levels: package/__init__.py -> python/ -> root/)
        pkg_dir = os.path.dirname(os.path.dirname(pkg_file))
        # Check if this looks like a source directory (has python/ subdirectory)
        if os.path.basename(pkg_dir) == 'python':
            root_dir = os.path.dirname(pkg_dir)
            print(root_dir)
        else:
            print(pkg_dir)
except:
    pass
" 2>/dev/null || echo "")
    
    if [ -n "$pip_path" ] && [ -d "$pip_path" ]; then
        echo -e "${GREEN}✓ $dep_name found (pip editable install)${NC}" >&2
        echo "${pip_path}:pip"
        return 0
    fi
    
    # Try to clone to 3rdparty
    echo -e "${YELLOW}⚠ $dep_name not found, attempting to clone from ${repo_url}...${NC}" >&2
    mkdir -p "$(dirname "$fallback_path")"
    
    if git clone --branch "$branch" --depth 1 "$repo_url" "$fallback_path" 2>/dev/null; then
        echo -e "${GREEN}✓ $dep_name cloned successfully${NC}" >&2
        echo "${fallback_path}:cloned"
        return 0
    else
        echo -e "${YELLOW}⚠ $dep_name not available (skipping)${NC}" >&2
        echo ":notfound"
        return 0
    fi
}

# Auto-detect and resolve dependencies
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Detecting Dependencies${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detect PyPTO
echo -e "${BLUE}Checking for PyPTO...${NC}"
PYPTO_RESULT=$(resolve_dependency "PyPTO" "PYPTO_ROOT" "${PROJECT_ROOT}/3rdparty/pypto" "$PYPTO_REPO" "$PYPTO_BRANCH")
PYPTO_DIR="${PYPTO_RESULT%:*}"
PYPTO_SOURCE="${PYPTO_RESULT#*:}"

NEED_PYPTO=false
if [ "$PYPTO_SOURCE" != "notfound" ] && [ -n "$PYPTO_DIR" ]; then
    # Verify PyPTO structure
    if [ -d "$PYPTO_DIR/python" ]; then
        NEED_PYPTO=true
        echo -e "${GREEN}  → PyPTO will be built${NC}"
    else
        echo -e "${YELLOW}  → PyPTO found but invalid structure (missing python/), skipping${NC}"
    fi
else
    echo -e "${YELLOW}  → PyPTO not available, skipping${NC}"
fi
echo ""

# Detect Simpler
echo -e "${BLUE}Checking for Simpler...${NC}"
SIMPLER_RESULT=$(resolve_dependency "Simpler" "SIMPLER_ROOT" "${PROJECT_ROOT}/3rdparty/simpler" "$SIMPLER_REPO" "$SIMPLER_BRANCH")
SIMPLER_DIR="${SIMPLER_RESULT%:*}"
SIMPLER_SOURCE="${SIMPLER_RESULT#*:}"

NEED_SIMPLER=false
if [ "$SIMPLER_SOURCE" != "notfound" ] && [ -n "$SIMPLER_DIR" ]; then
    # Verify Simpler structure
    if [ -d "$SIMPLER_DIR/python" ]; then
        NEED_SIMPLER=true
        echo -e "${GREEN}  → Simpler will be built${NC}"
    else
        echo -e "${YELLOW}  → Simpler found but invalid structure (missing python/), skipping${NC}"
    fi
else
    echo -e "${YELLOW}  → Simpler not available, skipping${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}Build Plan:${NC}"
echo "  • Framework:       ${GREEN}✓ (always)${NC}"
if [ "$NEED_PYPTO" = true ]; then
    echo "  • PyPTO:           ${GREEN}✓ (detected)${NC}"
else
    echo "  • PyPTO:           ${YELLOW}⊗ (not found)${NC}"
fi
if [ "$NEED_SIMPLER" = true ]; then
    echo "  • Simpler:         ${GREEN}✓ (detected)${NC}"
else
    echo "  • Simpler:         ${YELLOW}⊗ (not found)${NC}"
fi
echo ""

# Build PyPTO if needed
if [ "$NEED_PYPTO" = true ]; then
    # Skip building if PyPTO is from environment variable (externally managed)
    if [ "$PYPTO_SOURCE" = "environment" ]; then
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}PyPTO Build Status${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo -e "${GREEN}✓ Using external PyPTO from PYPTO_ROOT${NC}"
        echo -e "${YELLOW}Skipping build (using pre-built version at: ${PYPTO_DIR})${NC}"
        echo ""
        
        # Verify that .so file exists
        SO_FILE=$(find "$PYPTO_DIR/python/pypto" -name "pypto_core*.so" 2>/dev/null | head -n 1)
        if [ -n "$SO_FILE" ]; then
            echo -e "${GREEN}✓ Found PyPTO module: ${SO_FILE}${NC}"
        else
            echo -e "${YELLOW}⚠ Warning: PyPTO module not found, make sure it's built at: ${PYPTO_DIR}${NC}"
        fi
        echo ""
    else
        # Check if PyPTO is already built (has compiled .so file)
        SO_FILE=$(find "$PYPTO_DIR/python/pypto" -name "pypto_core*.so" 2>/dev/null | head -n 1)
        
        if [ -n "$SO_FILE" ] && [ "$CLEAN_BUILD" != true ]; then
            echo -e "${BLUE}========================================${NC}"
            echo -e "${BLUE}PyPTO Build Status${NC}"
            echo -e "${BLUE}========================================${NC}"
            echo ""
            echo -e "${GREEN}✓ PyPTO already built: ${SO_FILE}${NC}"
            echo -e "${YELLOW}Skipping PyPTO build (use --clean to rebuild)${NC}"
            echo ""
        else
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}Building PyPTO${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""
        
        BUILD_DIR="${PROJECT_ROOT}/build/pypto"
        
        # Clean build directory if requested
        if [ "$CLEAN_BUILD" = true ]; then
            echo -e "${BLUE}Cleaning PyPTO build directory...${NC}"
            if [ -d "$BUILD_DIR" ]; then
                rm -rf "$BUILD_DIR"
                echo -e "${GREEN}✓ Build directory cleaned${NC}"
            fi
        fi
        
        # Create build directory
        mkdir -p "$BUILD_DIR"
        
        # Detect Python paths
        echo -e "${BLUE}Detecting Python installation...${NC}"
        PYTHON_INCLUDE_DIR=$($PYTHON_EXE -c "import sysconfig; print(sysconfig.get_path('include'))")
        
        # Detect OS and set appropriate library extension
        if [[ "$OSTYPE" == "darwin"* ]]; then
            PYTHON_LIBRARY=$($PYTHON_EXE -c "import sysconfig; import os; libdir = sysconfig.get_config_var('LIBDIR'); version = sysconfig.get_config_var('VERSION'); print(os.path.join(libdir, f'libpython{version}.dylib'))")
        else
            # Linux
            PYTHON_LIBRARY=$($PYTHON_EXE -c "import sysconfig; import os; libdir = sysconfig.get_config_var('LIBDIR'); version = sysconfig.get_config_var('VERSION'); print(os.path.join(libdir, f'libpython{version}.so'))")
        fi
        
        # Detect nanobind location
        echo -e "${BLUE}Detecting nanobind installation...${NC}"
        NANOBIND_DIR=$($PYTHON_EXE -c "import nanobind; import os; print(os.path.join(os.path.dirname(nanobind.__file__), 'cmake'))" 2>/dev/null || echo "")
        
        if [ -z "$NANOBIND_DIR" ]; then
            echo -e "${YELLOW}Warning: nanobind not found. Installing...${NC}"
            $PYTHON_EXE -m pip install nanobind
            NANOBIND_DIR=$($PYTHON_EXE -c "import nanobind; import os; print(os.path.join(os.path.dirname(nanobind.__file__), 'cmake'))")
        fi
        
        echo ""
        echo -e "${GREEN}PyPTO Build Configuration:${NC}"
        echo "  PyPTO source:      ${PYPTO_DIR}"
        echo "  Build directory:   ${BUILD_DIR}"
        echo "  Python exe:        ${PYTHON_EXE}"
        echo "  Python include:    ${PYTHON_INCLUDE_DIR}"
        echo "  nanobind_DIR:      ${NANOBIND_DIR}"
        echo ""
        
        # Configure with CMake
        echo -e "${BLUE}Configuring PyPTO with CMake...${NC}"
        PYTHON_PREFIX=$($PYTHON_EXE -c "import sys; print(sys.prefix)")
        
        cmake -S "$PYPTO_DIR" -B "$BUILD_DIR" \
            -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
            -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
            -Dnanobind_DIR="$NANOBIND_DIR" \
            -DPython_EXECUTABLE="$PYTHON_EXE" \
            -DPython_ROOT_DIR="$PYTHON_PREFIX"
        echo -e "${GREEN}✓ CMake configuration complete${NC}"
        
        # Build
        echo -e "${BLUE}Building PyPTO...${NC}"
        cmake --build "$BUILD_DIR" -j"$JOBS"
        echo -e "${GREEN}✓ PyPTO build complete${NC}"
        
            # Verify build output
            echo ""
            echo -e "${BLUE}Verifying PyPTO build output...${NC}"
            SO_FILE=$(find "$PYPTO_DIR/python/pypto" -name "pypto_core*.so" 2>/dev/null | head -n 1)
            if [ -n "$SO_FILE" ]; then
                echo -e "${GREEN}✓ Built module found: ${SO_FILE}${NC}"
            else
                echo -e "${RED}✗ Built module not found${NC}"
                exit 1
            fi
            echo ""
        fi
    fi
fi

# Install pto-test package if requested
if [ "$INSTALL_PACKAGE" = true ]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Installing pto-test Package${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    $PYTHON_EXE -m pip install -e "$PROJECT_ROOT"
    echo -e "${GREEN}✓ pto-test package installed${NC}"
    echo ""
fi

# Generate setup_env.sh
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Generating Environment Setup Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

SETUP_ENV_FILE="${PROJECT_ROOT}/build/setup_env.sh"
mkdir -p "$(dirname "$SETUP_ENV_FILE")"

# Start building the environment script
cat > "$SETUP_ENV_FILE" << 'EOF_HEADER'
#!/bin/bash
# Auto-generated environment setup script for pto-testing-framework
# Source this file to set up the environment: source build/setup_env.sh

EOF_HEADER

# Add FRAMEWORK_ROOT
echo "export FRAMEWORK_ROOT=\"${PROJECT_ROOT}\"" >> "$SETUP_ENV_FILE"

# Build PYTHONPATH
PYTHON_PATHS="${PROJECT_ROOT}/src"

if [ "$NEED_PYPTO" = true ]; then
    echo "export PYPTO_ROOT=\"${PYPTO_DIR}\"" >> "$SETUP_ENV_FILE"
    PYTHON_PATHS="${PYPTO_DIR}/python:${PYTHON_PATHS}"
fi

if [ "$NEED_SIMPLER" = true ]; then
    echo "export SIMPLER_ROOT=\"${SIMPLER_DIR}\"" >> "$SETUP_ENV_FILE"
    PYTHON_PATHS="${SIMPLER_DIR}/python:${SIMPLER_DIR}/examples/scripts:${PYTHON_PATHS}"
fi

echo "" >> "$SETUP_ENV_FILE"
echo "export PYTHONPATH=\"${PYTHON_PATHS}:\${PYTHONPATH}\"" >> "$SETUP_ENV_FILE"

# Add status message
cat >> "$SETUP_ENV_FILE" << 'EOF_FOOTER'

echo "========================================="
echo "Environment configured for pto-testing-framework"
echo "========================================="
echo "  FRAMEWORK_ROOT: $FRAMEWORK_ROOT"
EOF_FOOTER

if [ "$NEED_PYPTO" = true ]; then
    echo 'echo "  PYPTO_ROOT:     $PYPTO_ROOT"' >> "$SETUP_ENV_FILE"
fi

if [ "$NEED_SIMPLER" = true ]; then
    echo 'echo "  SIMPLER_ROOT:   $SIMPLER_ROOT"' >> "$SETUP_ENV_FILE"
fi

echo 'echo "========================================="' >> "$SETUP_ENV_FILE"

chmod +x "$SETUP_ENV_FILE"
echo -e "${GREEN}✓ Environment setup script generated: ${SETUP_ENV_FILE}${NC}"
echo ""

# Test imports
if [ "$NEED_PYPTO" = true ] || [ "$NEED_SIMPLER" = true ]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Testing Imports${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Source the environment
    source "$SETUP_ENV_FILE"
    
    if [ "$NEED_PYPTO" = true ]; then
        if $PYTHON_EXE -c "import pypto; print(f'✓ PyPTO version: {pypto.__version__}')"; then
            echo -e "${GREEN}✓ PyPTO successfully importable${NC}"
        else
            echo -e "${RED}✗ Failed to import PyPTO${NC}"
            exit 1
        fi
    fi
    
    if [ "$NEED_SIMPLER" = true ]; then
        if $PYTHON_EXE -c "import pto_compiler; print('✓ Simpler modules accessible')"; then
            echo -e "${GREEN}✓ Simpler successfully importable${NC}"
        else
            echo -e "${YELLOW}⚠ Simpler import check skipped (may need runtime setup)${NC}"
        fi
    fi
    
    echo ""
fi

# Final success message
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build Completed Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${GREEN}Environment has been configured for this session.${NC}"
echo ""
echo -e "${YELLOW}For new terminal sessions, source the environment:${NC}"
echo ""
echo "  source ${PROJECT_ROOT}/build/setup_env.sh"
echo ""
echo -e "Then you can run tests:"
echo "  pytest tests/"
echo ""
