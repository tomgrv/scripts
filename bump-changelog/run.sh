#!/bin/sh

# Bump changelog utility - streamlined changelog generation with fluent data processing
# Used by git-release-changelog script
#
# This script generates structured changelogs from git commit history using conventional commit format.
# It supports both incremental updates and full rebuilds, with buffered writing for safety.
# The changelog format includes sections for breaking changes, scopes, and commit types.

# Parse command line arguments using zz_args helper
# Supports version specification, dry-run mode, rebuild mode, and custom output file
eval $(
    zz_args "Bump changelog utility" $0 "$@" <<- help
        f   version version     Force version for changelog entry
        b   -       bump        Bump version files as per commit-and-tag-version.bumpFiles in package.json
        m   -       minimal     Only bump workspace files if commit scope relates to workspace name
        d   -       dry_run     Show what would be added without making changes
        t   -       tag         Create git tag for version
        r   -       rebuild     Rebuild entire changelog from all git history
        s   scope   scope       Limit changelog to specific scope
        -   file    file        File to write changelog to (default: CHANGELOG.md)  
help
)

# Set default output file if not specified by user
file="${file:-CHANGELOG.md}"

# Change to repository root to ensure we're working from the correct directory
cd "$(git rev-parse --show-toplevel)" > /dev/null

# ===== CONFIGURATION AND UTILITY FUNCTIONS =====

# Get supported commit types and their sections from package.json or use defaults
# This defines how commits are categorized in the changelog (feat -> Features, fix -> Bug Fixes, etc.)
get_supported_types() {
    [ -f "package.json" ] && command -v jq > /dev/null 2>&1 \
        && jq -r '."bump-changelog".types[]? | select(.hidden != true) | "\(.type) \(.section)"' package.json 2> /dev/null \
        || echo "feat Features
fix Bug Fixes
docs Documentation
style Styling
refactor Refactoring  
perf Performance
test Tests
chore Maintenance"
}

# Extract repository URL from package.json for generating commit links
# Returns empty string if not found or jq not available
get_repo_url() {
    [ -f "package.json" ] && command -v jq > /dev/null 2>&1 \
        && jq -r '.repository.url // empty' package.json 2> /dev/null | sed -e 's/^git+//' -e 's/\.git$//' || echo ""
}

# ===== GIT TAG AND RANGE FUNCTIONS =====

# Get all git tags in reverse chronological order (newest first)
# Filters to semantic version tags and includes the initial commit
get_all_tags() {
    # Get semantic version tags sorted by version number
    git tag -l --sort=-version:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+' || echo ""
    # Include the initial commit as a reference point
    git rev-list --max-parents=0 HEAD
}

# Get the latest semantic version tag from git history
# Returns the most recent tag that matches semantic versioning pattern
get_latest_tag() {
    get_all_tags | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Determine git commit range from current and previous references
# Parameters:
#   current_ref: Git ref to generate changelog up to (default: HEAD)
#   previous_ref: Git ref to start from (if empty, starts from repo origin)
# Output: Git range specification (e.g., "v1.0.0..HEAD", "abc123..def456")
list_changelog_range() {
    read -r current_ref previous_ref

    # Determine commit range - either between two refs or from repo origin
    if [ -n "$previous_ref" ]; then
        echo "${previous_ref}..${current_ref}"
    else
        # From repo origin (initial commit) to current ref
        local initial_commit=$(git rev-list --max-parents=0 HEAD 2> /dev/null | head -1)
        if [ -n "$initial_commit" ]; then
            echo "${initial_commit}..${current_ref}"
        else
            # Fallback to all commits if can't find initial commit
            echo "$current_ref"
        fi
    fi
}


# ===== CHANGELOG GENERATION FUNCTIONS =====

# List changelog entries between two git references as structured data
# This extracts and processes commits without formatting them into markdown
# Input: range via stdin (e.g., "v1.0.0..HEAD")
# Output: pipe-separated data: priority|scope|section|message|link
list_changelog_between() {
    # Read range from stdin
    local range
    read -r range

    # Determine repo URL for commit links
    local repo_url="$(get_repo_url)"

    # Extract current and previous refs from range for output
    local current_ref="${range##*..}"
    local previous_ref="${range%%...*}"
    if [ "$current_ref" = "$range" ]; then
        # No .. in range, it's just a single ref
        current_ref="$range"
        previous_ref=""
    else
        # Swap the logic - in "v1.0.0..HEAD", current_ref should be HEAD
        local temp_current="${range##*..}"
        local temp_previous="${range%%...*}"
        current_ref="$temp_current"
        previous_ref="$temp_previous"
    fi

    # Skip if current_ref and previous_ref resolve to the same commit hash
    if [ -n "$previous_ref" ]; then
        local current_hash=$(git rev-parse "$current_ref" 2>/dev/null)
        local previous_hash=$(git rev-parse "$previous_ref" 2>/dev/null)
        if [ -n "$current_hash" ] && [ -n "$previous_hash" ] && [ "$current_hash" = "$previous_hash" ]; then
            zz_log w "Skipping changelog generation: current ref ($current_ref) and previous ref ($previous_ref) resolve to same commit ($current_hash)"
            return 0
        fi
    fi

    # Output range information for build_changelog to handle version headers
    printf "1_RANGE|%s|%s|%s|%s\n" "$current_ref" "$previous_ref" "$range" "$range"

    zz_log i "Processing commits in range: $range"

    # Log scope filtering if active
    if [ -n "$scope" ]; then
        zz_log w "Filtering commits to scope: $scope"
    fi

    # Main commit processing pipeline - extract structured data
    git log --oneline --format="%H|%s" "$range" 2> /dev/null \
        | while IFS='|' read -r commit_hash commit_msg; do
            # Extract scope from conventional commit format: type(scope): message
            commit_scope=$(echo "$commit_msg" | sed -n 's/^[^(]*(\([^)]*\)):.*/\1/p')

            # Skip commits that don't match the specified scope filter
            # If scope filter is specified, only include commits with exact scope match
            if [ -n "$scope" ] && [ "$commit_scope" != "$scope" ]; then
                continue
            fi

            # Clean up message by removing type prefix
            clean_msg=$(echo "$commit_msg" | sed 's/^[^:]*: //')

            # Check for breaking changes - highest priority for changelog organization
            if git show --format="%B" -s "$commit_hash" | grep -q "BREAKING CHANGE:" || echo "$commit_msg" | grep -q "!:"; then
                # Extract breaking change description if available
                breaking_desc=$(git show --format="%B" -s "$commit_hash" | sed -n 's/.*BREAKING CHANGE: //p' | head -1)
                [ -n "$breaking_desc" ] && clean_msg="$breaking_desc"
                priority="3_BREAKING" # Highest priority - will appear first
            else
                priority="4_CHANGES" # Normal priority
            fi

            # Map commit type to changelog section using supported types
            section=$(get_supported_types \
                | awk -v msg="$commit_msg" '
            $1 {
            pat = "^" $1 "[^:]*:"
            if (match(msg, pat)) {
                sec = "" 
                for (i = 2; i <= NF; i++) {
                sec = sec (i == 2 ? "" : " ") $i
                }
                print sec
                exit
            }
            }')

            # Generate commit link if repository URL is available
            commit_link=""
            if [ -n "$repo_url" ]; then
                commit_link="([$(echo "$commit_hash" | cut -c1-7)]($repo_url/commit/$commit_hash))"
            fi

            # Output structured data for sorting: priority|scope|section|message|link
            # Using "!!!!" as placeholder for empty scope to ensure proper sorting
            printf "%s|%s|%s|%s|%s\n" "$priority" "${commit_scope}" "${section:-Other changes}" "$clean_msg" "$commit_link"
        done | sort -t'|' -k1,1g -k2,2
}

# Build markdown changelog from structured data
# Takes structured data from list_changelog_between and formats it into markdown
build_changelog() {
    zz_log i "Building markdown changelog..."

    # Format the sorted data into markdown changelog structure
    awk -F'|' -v version="$1" '
    BEGIN { 
        prev_scope = ""
        prev_section = ""
        breaking_printed = 0
    }
    {
        entry = substr($1, 1, 1)
        current_ref = $2
        scope = $3
        section = $4
        message = $5
        link = $6
        
        # Handle range information (1_RANGE) - generate version header
        if (entry == 1) {
            # Generate version header with appropriate label and date
            if (current_ref == "HEAD") {
                version_label = (version ? version : "Unreleased")
                version_date = strftime("%Y-%m-%d")
            } else {
                # It is a tag, use tag name and get date from git
                version_label = current_ref
                cmd = "git log -1 --format=\"%ai\" " current_ref " 2>/dev/null | cut -d\" \" -f1"
                cmd | getline version_date
                close(cmd)
                if (!version_date) version_date = "unknown"
            }
            
            prev_scope = "!"
            print "## " version_label " (" version_date ")"
            print ""
            print "*Commits from: " $5 "*"
            next
        }
        
        # Handle commit entries (3_BREAKING for breaking, 4_CHANGES for normal)
        if (entry<3) {
            next  # Skip unknown entry types
        }
        
        # Adjust field positions since we removed 0_VERSION
        scope = $2
        section = $3  
        message = $4
        link = $5
        
        # Handle breaking changes section - always appears first
        if (entry == 3 && !breaking_printed) {
            if (prev_scope != "" || prev_section != "") print ""
            print "### 💥 BREAKING CHANGES"
            print ""
            breaking_printed = 1
            prev_scope = "BREAKING"
            prev_section = "BREAKING"
        }
        
        # Handle scope changes (organize commits by package/module scope)
        if (entry > 3 && scope != prev_scope) {
            if (prev_scope != "" && prev_scope != "BREAKING") print ""
            if (scope != "") {
                print "### 📦 " scope " changes"
                print ""
            } else {
                # No scope specified - use "main" as default
                print "### 📂 Unscoped changes"
                print ""
            }
            prev_scope = scope
            prev_section = ""
        }
        
        # Handle section changes within scope (feat, fix, docs, etc.)
        if (entry > 3 && section != prev_section && prev_section != "BREAKING") {
            if (prev_section != "" && scope == prev_scope) print ""
            print "#### " section
            print ""
            prev_section = section
        }
        
        # Output the actual commit line with optional link
        if (link != "") {
            print "- " message " " link
        } else {
            print "- " message
        }
    }
    END {
        print ""
    }'

    zz_log s "Changelog built."
}

# Rebuild complete changelog by iterating through all git tags
# Processes each tag pair to generate changelog sections chronologically
list_changelog() {

    local prev_tag="HEAD"

    # Process all existing tags in reverse chronological order
    while read -r tag; do

        # if $tag is on a commit that is the most recent commit, skip it to avoid empty range
        tag_commit=$(git rev-list -n 1 "$tag" 2>/dev/null)
        head_commit=$(git rev-parse "$prev_tag" 2>/dev/null)
        if [ "$tag_commit" = "$head_commit" ]; then
            zz_log w "Skipping tag $tag as it points to the same commit as $prev_tag"
            continue
        fi
        
        # Calculate range for this tag pair and pipe it to list_changelog_between
        echo "${prev_tag:-HEAD}" "$tag" | list_changelog_range | list_changelog_between
        prev_tag="$tag"
    done
}

# ===== MAIN EXECUTION LOGIC =====

# bump-version is dry run only if dry_run is set and bump is not set
bump_version_dry_run=""
if [ -n "$dry_run" ] || [ -z "$bump" ]; then
    bump_version_dry_run="-d"
fi

# Determine version and range using the bump-version script
determined_version=$(bump-version $minimal ${bump_version_dry_run} $version)
version=$(echo "$determined_version" | awk '{print $2}')
range=$(echo "$determined_version" | awk '{print $1}')
if [ -n "$version" ] && [ -n "$range" ]; then
    zz_log - "Using git range: $range"
    zz_log - "Using version: $version"
else
    zz_log e "Failed to determine version and range"
    exit 1
fi

# Echo version to stdout for consumption by calling scripts
echo "$version"

# If tag flag is set, create git tag after bumping files
if [ -n "$tag" ]; then
    zz_log i "Creating git tag for version $version using bump-tag"
    if bump-tag "$version"; then
        zz_log s "Git tag created successfully"
    else
        zz_log e "Failed to create git tag"
        exit 1
    fi
fi

# Main execution flow - handles both rebuild and incremental update modes
if [ -n "$rebuild" ]; then
    # REBUILD MODE: Generate complete changelog from all git history
    zz_log i "Rebuilding complete $file from all git history..."
    get_all_tags | list_changelog
else
    # INCREMENTAL MODE: Add new entry for current version since last tag
    zz_log i "Generating $file entry for version $version since last tag..."
    echo "$range" | list_changelog_between
fi | if [ -n "$dry_run" ]; then
    # DRY RUN MODE: Show what would be written without making changes
    zz_log w "Dry run mode - no changes will be made."
    cat
else
    # LIVE MODE: Write changes to file with safety measures

    # Create temporary file for atomic operations - prevents corruption
    temp_changelog=$(mktemp "${TMPDIR:-/tmp}/changelog.XXXXXX")

    # Ensure temporary file cleanup on script exit (success or failure)
    trap 'rm -f "$temp_changelog"' EXIT

    # Combine new changelog content with existing file content if not rebuilding
    if [ -z "$rebuild" ] && [ -f "$file" ]; then
        build_changelog "$version"
        # Extract existing content: start from first ## (version header) and stop at --- (footer)
        cat "$file" | sed -n '/^## /,$p' | sed '/^---/,$d'
    else
        build_changelog "$version"
    fi | {
        echo "# Changelog"
        echo ""
        cat # Insert the generated changelog content here
        echo ""
        echo "---"
        echo "*Generated on $(date +%Y-%m-%d) by [tomgrv/devcontainer-features](https://github.com/tomgrv/devcontainer-features)*"

    } > "$temp_changelog"

    # Validate temporary file before proceeding with replacement
    if [ -f "$temp_changelog" ] && [ -s "$temp_changelog" ]; then

        # Atomic replacement - either succeeds completely or fails completely
        mv "$temp_changelog" "$file"
        zz_log s "$file updated."

        # Stage the file for git commit
        git add "$file"

        # If tag flag is set and we're not in dry run mode, create git tag
        if [ -n "$tag" ] && [ -z "$bump" ]; then
            zz_log i "Creating git tag for version $version using bump-tag"
            if bump-tag "$version"; then
                zz_log s "Git tag created successfully"
            else
                zz_log w "Failed to create git tag (continuing anyway)"
            fi
        fi
    else
        # Error handling - temporary file creation failed
        zz_log e "Failed to generate changelog - temporary file is empty or missing"
        exit 1
    fi
fi
