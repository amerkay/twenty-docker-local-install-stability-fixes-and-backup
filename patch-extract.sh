#!/bin/bash

# Script to extract patches from git changes in the ./twenty/ repository
# Usage: ./patch-extract.sh [output_filename]

set -e  # Exit on any error

# Configuration
TWENTY_REPO_PATH="./twenty"
DEFAULT_OUTPUT_FILE="patch-twenty-changes.patch"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Parse command line arguments
OUTPUT_FILE="${1:-$DEFAULT_OUTPUT_FILE}"

# Function to print usage
print_usage() {
    echo "Usage: $0 [output_filename]"
    echo ""
    echo "Options:"
    echo "  output_filename  Name of the patch file (default: patch-twenty-changes.patch)"
    echo ""
    echo "This script extracts ALL changes from the repository including:"
    echo "  - Staged changes (files added with 'git add')"
    echo "  - Unstaged changes (modified tracked files)"
    echo "  - New/untracked files"
    echo ""
    echo "Examples:"
    echo "  $0                    # Extract all changes to patch-twenty-changes.patch"
    echo "  $0 my-patch.patch     # Extract all changes to my-patch.patch"
}

# Check if help is requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    print_usage
    exit 0
fi

# Validate that the twenty directory exists and is a git repository
if [[ ! -d "$TWENTY_REPO_PATH" ]]; then
    echo "Error: Directory '$TWENTY_REPO_PATH' does not exist!"
    echo "Please run this script from the directory containing the twenty folder."
    exit 1
fi

if [[ ! -d "$TWENTY_REPO_PATH/.git" ]]; then
    echo "Error: Directory '$TWENTY_REPO_PATH' is not a git repository!"
    exit 1
fi

# Change to the twenty repository directory
cd "$TWENTY_REPO_PATH"

echo "Extracting patches from twenty repository..."
echo "Repository path: $(pwd)"

# Check if there are any changes (staged, unstaged, or untracked)
if [[ -z $(git status --porcelain) ]]; then
    echo "No changes found in the repository."
    echo "No staged changes, unstaged changes, or new files to include in patch."
    exit 0
fi

echo "Found the following changes to include in the patch:"
git status --short | sed 's/^/  /'
echo ""

# Generate the patch using the 'stage all -> diff -> reset' method
# This method reliably includes all staged, unstaged, and untracked files.
echo "Generating patch..."
PATCH_PATH="../$OUTPUT_FILE"

# 1. Temporarily stage ALL changes (modified, new, deleted).
git add -A

# 2. Create the patch from the index (all staged changes).
git diff --cached > "$PATCH_PATH"

# 3. Reset the index to its original state, unstaging the files.
git reset >/dev/null

# Return to the original directory
cd ..

# Verify the patch was created
if [[ -f "$OUTPUT_FILE" ]]; then
    PATCH_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
    LINE_COUNT=$(wc -l < "$OUTPUT_FILE")
    
    echo "✅ Patch successfully created: $OUTPUT_FILE"
    echo "   Size: $PATCH_SIZE bytes"
    echo "   Lines: $LINE_COUNT"
    echo ""
    
    # Show a preview of the patch
    echo "Preview (first 20 lines):"
    echo "========================="
    head -20 "$OUTPUT_FILE"
    
    if [[ $LINE_COUNT -gt 20 ]]; then
        echo ""
        echo "... (showing first 20 lines of $LINE_COUNT total lines)"
    fi
    
    echo ""
    echo "To apply this patch to another repository:"
    echo "  git apply $OUTPUT_FILE"
    echo ""
    echo "To see the full patch content:"
    echo "  cat $OUTPUT_FILE"
    echo "  # or"
    echo "  less $OUTPUT_FILE"
    
else
    echo "❌ Error: Failed to create patch file!"
    exit 1
fi

echo ""
echo "🎉 Patch extraction completed successfully!"
