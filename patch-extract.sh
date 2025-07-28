#!/bin/bash

# Script to extract patches from git changes in the ./twenty/ repository
# Usage: ./patch-extract.sh [output_filename] [--staged]

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

# Check for all types of changes
HAS_CHANGES=false

# Check for staged changes
echo "Checking for staged changes..."
HAS_STAGED_CHANGES=false
if ! git diff --cached --quiet 2>/dev/null; then
    HAS_STAGED_CHANGES=true
    HAS_CHANGES=true
    echo "Found staged changes."
fi

# Check for unstaged changes
echo "Checking for unstaged changes..."
HAS_UNSTAGED_CHANGES=false
if ! git diff --quiet 2>/dev/null; then
    HAS_UNSTAGED_CHANGES=true
    HAS_CHANGES=true
    echo "Found unstaged changes."
fi

# Check for new/untracked files
echo "Checking for new/untracked files..."
NEW_FILES=$(git ls-files --others --exclude-standard)
if [[ -n "$NEW_FILES" ]]; then
    HAS_CHANGES=true
    echo "Found new files to include in patch."
fi

if [[ "$HAS_CHANGES" == "false" ]]; then
    echo "No changes found in the repository."
    echo "No staged changes, unstaged changes, or new files to include in patch."
    echo ""
    echo "Tip: Make some changes to files, stage them with 'git add', or create new files."
    exit 0
fi

# Get the list of all changed files
echo "Getting list of all changed files..."

if [[ "$HAS_STAGED_CHANGES" == "true" ]]; then
    STAGED_FILES=$(git diff --cached --name-only)
    echo "Staged files:"
    echo "$STAGED_FILES" | sed 's/^/  S /'
fi

if [[ "$HAS_UNSTAGED_CHANGES" == "true" ]]; then
    UNSTAGED_FILES=$(git diff --name-only)
    echo "Modified files (unstaged):"
    echo "$UNSTAGED_FILES" | sed 's/^/  M /'
fi

if [[ -n "$NEW_FILES" ]]; then
    echo "New files:"
    echo "$NEW_FILES" | sed 's/^/  + /'
fi
echo ""

# Generate the patch
echo "Generating patch..."
PATCH_PATH="../$OUTPUT_FILE"

# Function to generate patch for a new file
generate_new_file_patch() {
    local file_path="$1"
    local patch_file="$2"
    
    echo "diff --git a/$file_path b/$file_path" >> "$patch_file"
    echo "new file mode 100644" >> "$patch_file"
    echo "index 0000000..$(git hash-object "$file_path" 2>/dev/null || echo "0000000")" >> "$patch_file"
    echo "--- /dev/null" >> "$patch_file"
    echo "+++ b/$file_path" >> "$patch_file"
    
    # Add the file content with + prefix
    if [[ -f "$file_path" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            echo "+$line" >> "$patch_file"
        done < "$file_path"
    fi
}

# Initialize the patch file
> "$PATCH_PATH"

# Generate patch for staged changes
if [[ "$HAS_STAGED_CHANGES" == "true" ]]; then
    echo "Adding staged changes to patch..."
    git diff --cached >> "$PATCH_PATH"
fi

# Generate patch for unstaged changes
if [[ "$HAS_UNSTAGED_CHANGES" == "true" ]]; then
    echo "Adding unstaged changes to patch..."
    git diff >> "$PATCH_PATH"
fi

# Generate patches for new files and append them
if [[ -n "$NEW_FILES" ]]; then
    echo "Adding new files to patch..."
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            echo "  Adding new file: $file"
            generate_new_file_patch "$file" "$PATCH_PATH"
        fi
    done <<< "$NEW_FILES"
fi

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
