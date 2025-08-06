#!/bin/bash

# Script to revert changes, select tag version, apply patch, and build docker images
# Usage: ./patch-apply-and-docker-build.sh [patch_filename]

set -e  # Exit on any error

# Configuration
TWENTY_REPO_PATH="./twenty"
DEFAULT_PATCH_FILE="patch-twenty-changes.patch"
DOCKER_COMPOSE_FILE="./docker-compose.yml"

# Parse command line arguments
PATCH_FILE="${1:-$DEFAULT_PATCH_FILE}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}==>${NC} ${1}"
}

print_success() {
    echo -e "${GREEN}✅${NC} ${1}"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} ${1}"
}

print_error() {
    echo -e "${RED}❌${NC} ${1}"
}

# Function to print usage
print_usage() {
    echo "Usage: $0 [patch_filename]"
    echo ""
    echo "This script will:"
    echo "  1. Revert all changes in the ./twenty/ repository"
    echo "  2. Show available tags and let you select which version to checkout"
    echo "  3. Apply the specified patch file"
    echo "  4. Build the Docker images using docker-compose"
    echo ""
    echo "Arguments:"
    echo "  patch_filename   Name of the patch file to apply (default: $DEFAULT_PATCH_FILE)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use default patch file"
    echo "  $0 my-custom-patch.patch             # Use custom patch file"
}

# Check if help is requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    print_usage
    exit 0
fi

# Validate that required directories and files exist
print_step "Validating environment..."

if [[ ! -d "$TWENTY_REPO_PATH" ]]; then
    print_error "Directory '$TWENTY_REPO_PATH' does not exist!"
    echo "Please run this script from the directory containing the twenty folder."
    exit 1
fi

if [[ ! -d "$TWENTY_REPO_PATH/.git" ]]; then
    print_error "Directory '$TWENTY_REPO_PATH' is not a git repository!"
    exit 1
fi

if [[ ! -f "$PATCH_FILE" ]]; then
    print_error "Patch file '$PATCH_FILE' does not exist!"
    echo "Available patch files:"
    ls -la *.patch 2>/dev/null || echo "  No patch files found in current directory"
    exit 1
fi

if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
    print_error "Docker compose file '$DOCKER_COMPOSE_FILE' does not exist!"
    exit 1
fi

print_success "Environment validation completed"

# Step 1: Navigate to twenty repository and check current status
print_step "Checking current repository status..."
cd "$TWENTY_REPO_PATH"

# Show current status
echo "Current git status:"
git status --porcelain

# Check if there are any uncommitted changes
if ! git diff-index --quiet HEAD --; then
    print_warning "Found uncommitted changes in the repository"
    echo "The following files will be reverted:"
    git diff --name-only
    echo ""
    read -p "Do you want to continue and lose these changes? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Operation cancelled by user"
        exit 1
    fi
else
    print_success "No uncommitted changes found"
fi

# Step 2: Revert all changes
print_step "Reverting all changes..."

# Reset any staged changes
git reset HEAD . 2>/dev/null || true

# Revert all modified files
git checkout -- . 2>/dev/null || true

# Remove any untracked files (with confirmation)
UNTRACKED_FILES=$(git ls-files --others --exclude-standard)
if [[ -n "$UNTRACKED_FILES" ]]; then
    print_warning "Found untracked files:"
    echo "$UNTRACKED_FILES"
    echo ""
    read -p "Do you want to remove these untracked files? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git clean -fd
        print_success "Untracked files removed"
    else
        print_warning "Untracked files kept"
    fi
fi

print_success "All changes reverted"

# Step 3: Select and checkout tag version
print_step "Fetching tags from remote..."

# Fetch all tags and branches
git fetch --all --tags

# Get current commit hash
CURRENT_COMMIT=$(git rev-parse HEAD)

# Get current tag if we're on one
CURRENT_TAG=""
if CURRENT_TAG=$(git describe --tags --exact-match HEAD 2>/dev/null); then
    print_step "Currently on tag: $CURRENT_TAG"
else
    CURRENT_BRANCH=$(git branch --show-current)
    print_step "Currently on branch: $CURRENT_BRANCH (commit: ${CURRENT_COMMIT:0:8})"
fi

# Get last 12 tags sorted by date (descending)
print_step "Getting available tags..."
TAGS=("HEAD" $(git tag -l --sort=-creatordate | head -11))

if [[ ${#TAGS[@]} -eq 0 ]]; then
    print_error "No tags found in repository"
    print_warning "Falling back to latest main branch"
    if git checkout main && git pull origin main; then
        print_success "Checked out latest main branch"
    else
        print_error "Failed to checkout main branch"
        exit 1
    fi
else
    echo ""
    echo "Available options (HEAD + last 11 tags, sorted by date):"
    echo "========================================================"
    
    # Display tag options
    for i in "${!TAGS[@]}"; do
        tag="${TAGS[$i]}"
        
        # Handle HEAD specially
        if [[ "$tag" == "HEAD" ]]; then
            # Show current date/time for HEAD since it represents the current state
            tag_date=$(date '+%Y-%m-%d %H:%M:%S %z')
            markers="🔄 CURRENT HEAD"
        else
            tag_date=$(git log -1 --format=%ai "$tag" 2>/dev/null || echo "unknown date")
            
            # Mark current tag and newest tag
            markers=""
            if [[ "$tag" == "$CURRENT_TAG" ]]; then
                markers="📍 CURRENT"
            fi
            if [[ $i -eq 1 ]]; then  # First actual tag (index 1, since HEAD is at index 0)
                if [[ -n "$markers" ]]; then
                    markers="$markers 🚀 NEWEST"
                else
                    markers="🚀 NEWEST"
                fi
            fi
        fi
        
        printf "%2d) %-20s %s %s\n" $((i+1)) "$tag" "$tag_date" "$markers"
    done
    
    echo ""
    echo "Select an option to checkout (default: 1 - HEAD):"
    read -p "Enter number [1-${#TAGS[@]}]: " -r SELECTION
    
    # Validate selection
    if [[ -z "$SELECTION" ]]; then
        SELECTION=1
    elif ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [[ "$SELECTION" -lt 1 ]] || [[ "$SELECTION" -gt ${#TAGS[@]} ]]; then
        print_error "Invalid selection. Using HEAD (1)."
        SELECTION=1
    fi
    
    SELECTED_TAG="${TAGS[$((SELECTION-1))]}"
    
    # Handle HEAD selection specially
    if [[ "$SELECTED_TAG" == "HEAD" ]]; then
        print_success "Staying on current HEAD (no checkout needed)"
    elif [[ "$SELECTED_TAG" == "$CURRENT_TAG" ]]; then
        print_success "Already on selected tag: $SELECTED_TAG"
    else
        print_step "Checking out tag: $SELECTED_TAG"
        if git checkout "$SELECTED_TAG"; then
            print_success "Successfully checked out tag: $SELECTED_TAG"
        else
            print_error "Failed to checkout tag: $SELECTED_TAG"
            exit 1
        fi
    fi
fi

# Step 4: Apply the patch
print_step "Applying patch: $PATCH_FILE"

# We're currently in the twenty directory, go back to parent where patch file should be
cd ..

# Get absolute path to patch file
PATCH_ABS_PATH=$(realpath "$PATCH_FILE")

if [[ ! -f "$PATCH_ABS_PATH" ]]; then
    print_error "Patch file not found: $PATCH_ABS_PATH"
    exit 1
fi

print_step "Using patch file: $PATCH_ABS_PATH"

# Check if the patch can be applied
if git -C "$TWENTY_REPO_PATH" apply --check "$PATCH_ABS_PATH" 2>/dev/null; then
    print_success "Patch validation successful"
    # Apply the patch
    if git -C "$TWENTY_REPO_PATH" apply "$PATCH_ABS_PATH"; then
        print_success "Patch applied successfully"
    else
        print_error "Failed to apply patch"
        exit 1
    fi
else
    print_warning "Patch validation failed. Attempting to apply with 3-way merge..."
    # Try to apply with 3-way merge
    if git -C "$TWENTY_REPO_PATH" apply --3way "$PATCH_ABS_PATH"; then
        print_success "Patch applied with 3-way merge"
    else
        print_error "Failed to apply patch"
        echo ""
        echo "You may need to:"
        echo "1. Check if the patch is compatible with the current codebase"
        echo "2. Manually resolve conflicts"
        echo "3. Update the patch file"
        exit 1
    fi
fi

# Show what was changed by the patch
print_step "Patch applied. Changed files:"
git -C "$TWENTY_REPO_PATH" diff --name-only
echo ""

# Step 5: Build Docker images
print_step "Building Docker images with docker-compose..."

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
    print_error "Neither docker-compose nor docker is available"
    print_warning "Please install Docker to build the images"
    exit 1
fi

# Use docker compose (newer) or docker-compose (legacy)
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    print_error "No valid docker compose command found"
    exit 1
fi

print_step "Using command: $COMPOSE_CMD"

# Build the images
print_step "Starting Docker build process..."
echo "This may take several minutes..."

if $COMPOSE_CMD build; then
    print_success "Docker images built successfully"
else
    print_error "Docker build failed"
    echo ""
    echo "Common troubleshooting steps:"
    echo "1. Check if Docker daemon is running"
    echo "2. Ensure you have sufficient disk space"
    echo "3. Check docker-compose.yml for any issues"
    echo "4. Try running: docker system prune -f"
    exit 1
fi

# Final summary
echo ""
print_success "🎉 All operations completed successfully!"
echo ""
echo "Summary of what was done:"
echo "  ✅ Reverted all changes in ./twenty/ repository"
if [[ "$SELECTED_TAG" == "HEAD" ]]; then
    echo "  ✅ Stayed on current HEAD"
elif [[ -n "$SELECTED_TAG" ]]; then
    echo "  ✅ Checked out tag: $SELECTED_TAG"
else
    echo "  ✅ Updated to latest main branch"
fi
echo "  ✅ Applied patch: $PATCH_FILE"
echo "  ✅ Built Docker images using $COMPOSE_CMD"
echo ""
echo "Your Docker images are now ready to use!"
echo "You can start the services with:"
echo "  $COMPOSE_CMD up -d"
echo ""
echo "To see the applied changes:"
echo "  cd $TWENTY_REPO_PATH && git diff"
