#!/bin/bash

# Python altinstall script - compiles from source
# Installs Python 3.9-3.13 without interfering with system Python

set -e

# Installation mode (will be set during runtime)
INSTALL_MODE="interactive"

# Add error trap to debug
trap 'echo "Error on line $LINENO. Exit code: $?" >&2' ERR

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Python versions with their exact patch versions
declare -A PYTHON_VERSIONS=(
    ["3.9"]="3.9.18"
    ["3.10"]="3.10.13"
    ["3.11"]="3.11.7"
    ["3.12"]="3.12.1"
    ["3.13"]="3.13.0"
)

# Check if Python version is already installed
check_python_installed() {
    local version=$1
    if command -v "python${version}" >/dev/null 2>&1; then
        local installed_version=$("python${version}" --version 2>&1 | awk '{print $2}')
        log_success "Python $version already installed: $installed_version"
        return 0
    fi
    return 1
}

# Install build dependencies
install_dependencies() {
    log_info "Installing build dependencies..."
    
    sudo apt update
    sudo apt install -y \
        build-essential \
        zlib1g-dev \
        libncurses5-dev \
        libgdbm-dev \
        libnss3-dev \
        libssl-dev \
        libreadline-dev \
        libffi-dev \
        libsqlite3-dev \
        wget \
        libbz2-dev \
        libxmlsec1-dev \
        libxml2-dev \
        liblzma-dev \
        tk-dev \
        uuid-dev
    
    log_success "Dependencies installed"
}

# Download and compile Python
install_python() {
    local version=$1
    local full_version=$2
    
    log_info "Installing Python $full_version..."
    
    # Create temporary directory
    local temp_dir="/tmp/python-$full_version"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Download source
    log_info "Downloading Python $full_version source..."
    wget "https://www.python.org/ftp/python/$full_version/Python-$full_version.tgz"
    tar -xzf "Python-$full_version.tgz"
    cd "Python-$full_version"
    
    # Configure with optimization
    log_info "Configuring build..."
    ./configure \
        --enable-optimizations \
        --with-lto \
        --enable-shared \
        --with-system-ffi \
        --with-computed-gotos \
        --enable-loadable-sqlite-extensions \
        --prefix=/usr/local
    
    # Compile (use all CPU cores)
    local cores=$(nproc)
    log_info "Compiling with $cores cores..."
    make -j"$cores"
    
    # Install using altinstall (doesn't overwrite system python)
    log_info "Installing Python $full_version..."
    sudo make altinstall
    
    # Update shared library cache
    sudo ldconfig
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
    
    # Verify installation
    if command -v "python${version}" >/dev/null 2>&1; then
        local installed_version=$("python${version}" --version 2>&1 | awk '{print $2}')
        log_success "Python $version installed successfully: $installed_version"
        
        # Install pip for this version if not present
        if ! "python${version}" -m pip --version >/dev/null 2>&1; then
            log_info "Installing pip for Python $version..."
            "python${version}" -m ensurepip --default-pip
        fi
        
        return 0
    else
        log_error "Installation failed for Python $version"
        return 1
    fi
}

# Main installation function
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Python altinstall - Source Compilation${NC}"
    echo -e "${BLUE}     Installing Python 3.9 - 3.13${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    # Check system info
    log_info "System: $(lsb_release -d | cut -f2)"
    log_info "Architecture: $(uname -m)"
    log_info "Available cores: $(nproc)"
    echo
    
    # Show what will be available for installation
    log_info "Available Python versions for installation:"
    for version in $(printf '%s\n' "${!PYTHON_VERSIONS[@]}" | sort -V); do
        local full_version="${PYTHON_VERSIONS[$version]}"
        if check_python_installed "$version" >/dev/null 2>&1; then
            echo "  Python $version -> ${full_version} ${GREEN}(already installed)${NC}"
        else
            echo "  Python $version -> ${full_version} ${YELLOW}(available)${NC}"
        fi
    done
    echo
    
    # Installation mode selection
    echo -e "${BLUE}Installation modes:${NC}"
    echo "  1. Interactive - prompt for each version (recommended)"
    echo "  2. Install all - install all versions automatically"
    echo "  3. Cancel"
    echo
    read -p "Choose mode [1/2/3]: " -n 1 -r
    echo
    
    case $REPLY in
        [2]* )
            INSTALL_MODE="all"
            log_info "Will install all available versions automatically"
            ;;
        [3]* )
            log_info "Installation cancelled."
            exit 0
            ;;
        * )
            INSTALL_MODE="interactive"
            log_info "Will prompt for each version individually"
            ;;
    esac
    
    # Check for sudo access
    log_info "Checking sudo access..."
    sudo -v
    
    # Install dependencies
    install_dependencies
    
    echo
    log_info "Starting Python compilation and installation..."
    echo
    
    # Track results
    local installed_count=0
    local failed_versions=()
    local total_versions=${#PYTHON_VERSIONS[@]}
    
    log_info "Starting installation loop for ${total_versions} versions..."
    
    # Install each version (interactive or automatic)
    for version in $(printf '%s\n' "${!PYTHON_VERSIONS[@]}" | sort -V); do
        local full_version="${PYTHON_VERSIONS[$version]}"
        echo
        echo -e "${BLUE}===== Python $version (${full_version}) =====${NC}"
        
        # Debug output
        log_info "Processing Python $version..."
        
        # Check if already installed first
        if check_python_installed "$version"; then
            log_info "Python $version is already installed, incrementing counter..."
            installed_count=$((installed_count + 1))
            log_info "Skipping Python $version - already installed (count: $installed_count)"
            log_info "Continuing to next version..."
            continue
        fi
        
        log_info "Python $version not found, proceeding with installation prompt..."
        
        local should_install=false
        
        if [ "$INSTALL_MODE" = "all" ]; then
            should_install=true
            log_info "Auto-installing Python $version..."
        else
            # Interactive mode - prompt for each version
            echo -e "${YELLOW}Install Python $version ($full_version)?${NC}"
            echo "  📦 Compilation time: ~5-15 minutes depending on your system"
            echo "  💾 Disk space required: ~100MB"
            echo "  🔧 Will be installed as: /usr/local/bin/python$version"
            echo
            
            while true; do
                read -p "  Install this version? [Y/n/q/a]: " -r
                case $REPLY in
                    [Qq]* )
                        log_info "Installation cancelled by user"
                        break 2  # Break out of both loops
                        ;;
                    [Aa]* )
                        log_info "Installing remaining versions automatically..."
                        INSTALL_MODE="all"
                        should_install=true
                        break
                        ;;
                    [Nn]* )
                        log_info "Skipping Python $version"
                        break
                        ;;
                    [Yy]* | "" )
                        # Default is Yes (including just pressing Enter)
                        should_install=true
                        break
                        ;;
                    * )
                        echo "Please answer Y, n, q, or a"
                        continue
                        ;;
                esac
            done
        fi
        
        if [ "$should_install" = true ]; then
            log_info "Starting compilation of Python $version..."
            local start_time=$(date +%s)
            if install_python "$version" "$full_version"; then
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                log_success "Python $version completed in ${duration}s"
                installed_count=$((installed_count + 1))
            else
                log_error "Failed to install Python $version"
                failed_versions+=("$version")
            fi
        fi
        
        # Show progress
        local remaining=$((total_versions - installed_count - ${#failed_versions[@]}))
        echo -e "${BLUE}Progress: $installed_count installed, ${#failed_versions[@]} failed, $remaining remaining${NC}"
        
        # Add a small delay so user can see progress
        sleep 1
        
        log_info "Finished processing Python $version, moving to next..."
    done
    
    log_info "Completed installation loop."
    
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}         Installation Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    log_info "Successfully installed: $installed_count/$total_versions versions"
    
    if [ ${#failed_versions[@]} -gt 0 ]; then
        log_warning "Failed versions: ${failed_versions[*]}"
    fi
    
    echo
    log_info "Installed Python executables:"
    for version in $(printf '%s\n' "${!PYTHON_VERSIONS[@]}" | sort -V); do
        if command -v "python${version}" >/dev/null 2>&1; then
            local installed_version=$("python${version}" --version 2>&1 | awk '{print $2}')
            echo "  python${version} -> $installed_version"
        fi
    done
    
    echo
    echo -e "${GREEN}=== Interactive Prompts ===${NC}"
    echo "  Y/Enter - Install this version"
    echo "  n       - Skip this version"  
    echo "  q       - Quit installation"
    echo "  a       - Install this and all remaining versions"
    echo
    echo -e "${GREEN}=== Usage Examples ===${NC}"
    echo "  python3.12 --version        # Use Python 3.12"
    echo "  python3.11 -m pip install pkg  # Install package with Python 3.11"
    echo "  python3.13 script.py        # Run script with Python 3.13"
    echo
    echo -e "${GREEN}=== Poetry Integration ===${NC}"
    echo "  poetry env use python3.12   # Use Python 3.12 with Poetry"
    echo "  poetry env use /usr/local/bin/python3.11  # Full path"
    echo
    echo -e "${GREEN}=== Virtual Environments ===${NC}"
    echo "  python3.12 -m venv myenv     # Create venv with Python 3.12"
    echo "  source myenv/bin/activate    # Activate environment"
    echo
    echo -e "${GREEN}=== Next Steps ===${NC}"
    echo "  1. Test installation: python3.12 --version"
    echo "  2. Create Poetry project: poetry new myproject"
    echo "  3. Set Python version: poetry env use python3.12"
    echo "  4. Install dependencies: poetry install"
    echo
    
    log_success "Installation completed! All Python versions installed via altinstall."
    log_info "Binaries located in: /usr/local/bin/"
    
    if [ $installed_count -gt 0 ]; then
        echo
        echo -e "${GREEN}✨ Ready to use with Poetry! Try:${NC}"
        echo -e "${BLUE}poetry env use python$(printf '%s\n' "${!PYTHON_VERSIONS[@]}" | sort -V | tail -1)${NC}"
    fi
}

# Check if running as root (not recommended)
if [ "$EUID" -eq 0 ]; then
    log_error "Don't run this script as root. It will use sudo when needed."
    exit 1
fi

# Run main function
main "$@"
