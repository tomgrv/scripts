#!/bin/sh

# Bump version utility - updates version numbers in files based on configuration
# Used by bump-changelog and other versioning scripts
#
# This script uses GitVersion to determine semantic versions and reads configuration 
# from package.json commit-and-tag-version.bumpFiles to update version numbers in 
# specified files with workspace-aware functionality.

set -e

# Parse command line arguments using zz_args helper
eval $(
    zz_args "Bump version files utility" $0 "$@" <<- help
        m   -         minimal     Only bump workspace files if commit scope relates to workspace name
        r   range     range       Git range to check for affected workspaces (required for minimal mode)
        d   -         dry_run     Show what would be updated without making changes
        -   version   version     Version to set in files (optional - will use GitVersion if not provided)
help
)

# Change to repository root to ensure we're working from the correct directory
cd "$(git rev-parse --show-toplevel)" > /dev/null

# ===== VERSION DETERMINATION FUNCTIONS =====

# Get the latest semantic version tag from git history (fallback method)
get_latest_tag() {
    git tag -l --sort=-version:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Calculate git range from latest tag to HEAD for change analysis
get_latest_range() {
    local latest_tag=$(get_latest_tag)
    if [ -n "$latest_tag" ]; then
        echo "${latest_tag}..HEAD"
    else
        # From initial commit to HEAD if no tags exist
        local initial_commit=$(git rev-list --max-parents=0 HEAD 2>/dev/null | head -1)
        echo "${initial_commit}..HEAD"
    fi
}

# Format and validate version string
# Parameters: version (raw version string from user input)
# Returns properly formatted semantic version
format_version() {
    local raw_version="$1"

    if [ -z "$raw_version" ]; then
        zz_log e "Version cannot be empty"
        return 1
    fi

    # Clean and validate semantic version format
    local clean_version=$(echo "$raw_version" | sed 's/^v//')
    
    # Validate semantic version pattern (supports pre-release and build metadata)
    if echo "$clean_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'; then
        echo "$clean_version"
        return 0
    fi

    # Auto-complete partial versions
    case "$clean_version" in
        [0-9]*.[0-9]*)
            echo "${clean_version}.0"
            ;;
        [0-9]*)
            echo "${clean_version}.0.0"
            ;;
        *)
            zz_log e "Invalid version format: $raw_version"
            return 1
            ;;
    esac
}

# ===== VERSION FILE UPDATE FUNCTIONS =====

# Update version in a JSON file using jq
update_json_file() {
    local filepath="$1"
    local version="$2"

    if [ -n "$dry_run" ]; then
        zz_log i "Would update JSON file: $filepath to version $version"
        return 0
    fi

    if command -v jq > /dev/null 2>&1; then
        jq --arg version "$version" '.version = $version' "$filepath" > "${filepath}.tmp" && mv "${filepath}.tmp" "$filepath"
        # Only add to git if the file is not ignored
        if git check-ignore "$filepath" > /dev/null 2>&1; then
            zz_log w "File $filepath is ignored by git, not staging"
        else
            git add "$filepath"
        fi
        zz_log s "Updated $filepath to version $version"
    else
        zz_log e "jq not available for updating JSON file: $filepath"
        return 1
    fi
}

# Update version in a plain text file
update_text_file() {
    local filepath="$1"
    local version="$2"

    if [ -n "$dry_run" ]; then
        zz_log i "Would update text file: $filepath to version $version"
        return 0
    fi

    echo "$version" > "$filepath"
    # Only add to git if the file is not ignored
    if git check-ignore "$filepath" > /dev/null 2>&1; then
        zz_log w "File $filepath is ignored by git, not staging"
    else
        git add "$filepath"
    fi
    zz_log s "Updated $filepath to version $version"
}

# Update version files based on configuration with simplified workspace logic
update_version_files() {
    local range="$1"
    local filename="$2"
    local version="$3"
    local is_workspace="$4"
    local update_function="$5"

    if [ "$is_workspace" = true ]; then
        # Determine workspace list based on minimal flag
        local workspace_list
        if [ -n "$minimal" ]; then
            if [ -z "$range" ]; then
                zz_log e "Range parameter required for minimal mode"
                return 1
            fi
            # Affected workspaces depend only on the range, not on which file
            # is being bumped -- multiple @ws entries in bump-version.files
            # share the same range, so cache the lookup (and its "no
            # workspaces affected" warning) per range instead of repeating
            # both the git-workspaces call and the warning for every entry.
            if [ "$range" != "${_workspace_list_range:-}" ]; then
                _workspace_list_range="$range"
                _workspace_list_cache=$(git workspaces -r "$range" 2>/dev/null || echo "")
                if [ -z "$_workspace_list_cache" ]; then
                    zz_log w "No workspaces affected by commits in range $range"
                else
                    zz_log i "Minimal mode: updating workspaces affected by $range"
                fi
            fi
            workspace_list="$_workspace_list_cache"

            if [ -z "$workspace_list" ]; then
                return 0
            fi
        else
            workspace_list=$(git workspaces 2>/dev/null || echo "")
        fi

        # Update workspace files
        if [ -n "$workspace_list" ] && [ -n "$filename" ]; then
            echo "$workspace_list" | while read -r workspace_dir; do
                [ -z "$workspace_dir" ] && continue
                local workspace_file="$workspace_dir/$filename"
                if [ -f "$workspace_file" ]; then
                    "$update_function" "$workspace_file" "$version"
                fi
            done
        fi
    else
        # Update single file
        if [ -n "$filename" ] && [ -f "$filename" ]; then
            "$update_function" "$filename" "$version"
        else
            zz_log w "File not found: $filename"
        fi
    fi
}

# ===== MAIN BUMP FUNCTION =====

# Process version files based on commit-and-tag-version.bumpFiles configuration
bump_version_files() {
    local version="$1"
    local range="$2"

    # Check dependencies
    if [ ! -f "package.json" ]; then
        zz_log w "package.json not found - skipping version file bumping"
        return 0
    fi
    
    if ! command -v jq > /dev/null 2>&1; then
        zz_log w "jq not available - skipping version file bumping"
        return 0
    fi

    # Get bumpFiles configuration
    local bump_files=$(jq -r '."bump-version".files[]? | @json' package.json 2>/dev/null)

    if [ -z "$bump_files" ]; then
        zz_log w "No bumpFiles configuration found in package.json"
        return 0
    fi

    zz_log i "Processing version file updates to $version"

    # Process each bump file configuration
    echo "$bump_files" | while read -r bump_file_json; do
        [ -z "$bump_file_json" ] || [ "$bump_file_json" = "null" ] && continue
        
        # Parse configuration
        local filename=$(echo "$bump_file_json" | jq -r '.filename // empty')
        local type=$(echo "$bump_file_json" | jq -r '.type // "json"')

        # Handle workspace operations (type ends with @ws)
        local is_workspace=false
        if echo "$type" | grep -q '@ws$'; then
            is_workspace=true
            type=$(echo "$type" | sed 's/@ws$//')
        fi

        # Update files based on type
        case "$type" in
            "json")
                update_version_files "$range" "$filename" "$version" "$is_workspace" "update_json_file"
                ;;
            "plain-text")
                update_version_files "$range" "$filename" "$version" "$is_workspace" "update_text_file"
                ;;
            *)
                zz_log w "Unsupported file type: $type for $filename"
                ;;
        esac
    done

    zz_log s "Version files processing completed"
}

# ===== MAIN EXECUTION LOGIC =====

# Determine version using GitVersion or user input
if [ -z "$version" ]; then
    version=$(gv -showvariable SemVer)
    zz_log s "GitVersion determined version: $version"
else
    version=$(format_version "$version")
    if [ $? -ne 0 ]; then
        zz_log e "Failed to format version: $version"
        exit 1
    fi
    zz_log s "Using provided version: $version"
fi

# Calculate git range for minimal mode and output
range=$(get_latest_range)
zz_log i "Git range: $range"

# Output version and range for script chaining
echo "$range $version"

# Exit early if dry run
if [ -n "$dry_run" ]; then
    zz_log i "Dry run mode - no files will be modified"
    exit 0
fi

# Validate minimal mode requirements
if [ -n "$minimal" ] && [ -z "$range" ]; then
    zz_log e "Range parameter is required when using minimal mode"
    exit 1
fi

# Execute version file updates
bump_version_files "$version" "$range"
