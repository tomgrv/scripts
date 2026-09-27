#!/bin/sh

# Generates structured changelogs from git commit history using conventional
# commit format. Used by git-release-changelog. Supports incremental updates
# and full rebuilds, with buffered writing for safety.

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

file="${file:-CHANGELOG.md}"

cd "$(git rev-parse --show-toplevel)" > /dev/null

# Get supported commit types and their sections from package.json or use defaults
# (feat -> Features, fix -> Bug Fixes, etc.)
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

get_repo_url() {
    [ -f "package.json" ] && command -v jq > /dev/null 2>&1 \
        && jq -r '.repository.url // empty' package.json 2> /dev/null | sed -e 's/^git+//' -e 's/\.git$//' || echo ""
}

get_all_tags() {
    git tag -l --sort=-version:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+' || echo ""
    # Include the initial commit as a reference point
    git rev-list --max-parents=0 HEAD
}

get_latest_tag() {
    get_all_tags | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Output: git range specification (e.g., "v1.0.0..HEAD", "abc123..def456")
list_changelog_range() {
    read -r current_ref previous_ref

    if [ -n "$previous_ref" ]; then
        echo "${previous_ref}..${current_ref}"
    else
        # From repo origin (initial commit) to current ref
        local initial_commit=$(git rev-list --max-parents=0 HEAD 2> /dev/null | head -1)
        if [ -n "$initial_commit" ]; then
            echo "${initial_commit}..${current_ref}"
        else
            echo "$current_ref"
        fi
    fi
}

# Extracts and processes commits between two refs into structured data
# (without formatting them into markdown).
# Input: range via stdin (e.g., "v1.0.0..HEAD")
# Output: pipe-separated data: priority|scope|section|message|link
list_changelog_between() {
    local range
    read -r range

    local repo_url="$(get_repo_url)"

    local current_ref="${range##*..}"
    local previous_ref="${range%%...*}"
    if [ "$current_ref" = "$range" ]; then
        # No .. in range, it's just a single ref
        current_ref="$range"
        previous_ref=""
    else
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

    if [ -n "$scope" ]; then
        zz_log w "Filtering commits to scope: $scope"
    fi

    git log --oneline --format="%H|%s" "$range" 2> /dev/null \
        | while IFS='|' read -r commit_hash commit_msg; do
            # Extract scope from conventional commit format: type(scope): message
            commit_scope=$(echo "$commit_msg" | sed -n 's/^[^(]*(\([^)]*\)):.*/\1/p')

            if [ -n "$scope" ] && [ "$commit_scope" != "$scope" ]; then
                continue
            fi

            clean_msg=$(echo "$commit_msg" | sed 's/^[^:]*: //')

            # Breaking changes get the highest priority so they sort first
            if git show --format="%B" -s "$commit_hash" | grep -q "BREAKING CHANGE:" || echo "$commit_msg" | grep -q "!:"; then
                breaking_desc=$(git show --format="%B" -s "$commit_hash" | sed -n 's/.*BREAKING CHANGE: //p' | head -1)
                [ -n "$breaking_desc" ] && clean_msg="$breaking_desc"
                priority="3_BREAKING"
            else
                priority="4_CHANGES"
            fi

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

            commit_link=""
            if [ -n "$repo_url" ]; then
                commit_link="([$(echo "$commit_hash" | cut -c1-7)]($repo_url/commit/$commit_hash))"
            fi

            # "!!!!" as placeholder for empty scope to ensure proper sorting
            printf "%s|%s|%s|%s|%s\n" "$priority" "${commit_scope}" "${section:-Other changes}" "$clean_msg" "$commit_link"
        done | sort -t'|' -k1,1g -k2,2
}

# Takes structured data from list_changelog_between and formats it into markdown
build_changelog() {
    zz_log i "Building markdown changelog..."

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

        if (entry<3) {
            next  # Skip unknown entry types
        }

        # Adjust field positions since we removed 0_VERSION
        scope = $2
        section = $3  
        message = $4
        link = $5

        # Breaking changes section always appears first
        if (entry == 3 && !breaking_printed) {
            if (prev_scope != "" || prev_section != "") print ""
            print "### 💥 BREAKING CHANGES"
            print ""
            breaking_printed = 1
            prev_scope = "BREAKING"
            prev_section = "BREAKING"
        }

        # Organize commits by package/module scope
        if (entry > 3 && scope != prev_scope) {
            if (prev_scope != "" && prev_scope != "BREAKING") print ""
            if (scope != "") {
                print "### 📦 " scope " changes"
                print ""
            } else {
                print "### 📂 Unscoped changes"
                print ""
            }
            prev_scope = scope
            prev_section = ""
        }

        if (entry > 3 && section != prev_section && prev_section != "BREAKING") {
            if (prev_section != "" && scope == prev_scope) print ""
            print "#### " section
            print ""
            prev_section = section
        }

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

# Rebuild complete changelog by iterating through all git tags,
# processing each tag pair chronologically
list_changelog() {

    local prev_tag="HEAD"

    while read -r tag; do

        # if $tag is on a commit that is the most recent commit, skip it to avoid empty range
        tag_commit=$(git rev-list -n 1 "$tag" 2>/dev/null)
        head_commit=$(git rev-parse "$prev_tag" 2>/dev/null)
        if [ "$tag_commit" = "$head_commit" ]; then
            zz_log w "Skipping tag $tag as it points to the same commit as $prev_tag"
            continue
        fi

        echo "${prev_tag:-HEAD}" "$tag" | list_changelog_range | list_changelog_between
        prev_tag="$tag"
    done
}

# bump-version is dry run only if dry_run is set and bump is not set
bump_version_dry_run=""
if [ -n "$dry_run" ] || [ -z "$bump" ]; then
    bump_version_dry_run="-d"
fi

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

if [ -n "$tag" ]; then
    zz_log i "Creating git tag for version $version using bump-tag"
    if bump-tag "$version"; then
        zz_log s "Git tag created successfully"
    else
        zz_log e "Failed to create git tag"
        exit 1
    fi
fi

if [ -n "$rebuild" ]; then
    zz_log i "Rebuilding complete $file from all git history..."
    get_all_tags | list_changelog
else
    zz_log i "Generating $file entry for version $version since last tag..."
    echo "$range" | list_changelog_between
fi | if [ -n "$dry_run" ]; then
    zz_log w "Dry run mode - no changes will be made."
    cat
else
    # Create temporary file for atomic operations - prevents corruption
    temp_changelog=$(mktemp "${TMPDIR:-/tmp}/changelog.XXXXXX")

    trap 'rm -f "$temp_changelog"' EXIT

    if [ -z "$rebuild" ] && [ -f "$file" ]; then
        build_changelog "$version"
        # Extract existing content: start from first ## (version header) and stop at --- (footer)
        cat "$file" | sed -n '/^## /,$p' | sed '/^---/,$d'
    else
        build_changelog "$version"
    fi | {
        echo "# Changelog"
        echo ""
        cat
        echo ""
        echo "---"
        echo "*Generated on $(date +%Y-%m-%d) by [tomgrv/devcontainer-features](https://github.com/tomgrv/devcontainer-features)*"

    } > "$temp_changelog"

    # Validate temporary file before proceeding with replacement
    if [ -f "$temp_changelog" ] && [ -s "$temp_changelog" ]; then

        # Atomic replacement - either succeeds completely or fails completely
        mv "$temp_changelog" "$file"
        zz_log s "$file updated."

        git add "$file"

        if [ -n "$tag" ] && [ -z "$bump" ]; then
            zz_log i "Creating git tag for version $version using bump-tag"
            if bump-tag "$version"; then
                zz_log s "Git tag created successfully"
            else
                zz_log w "Failed to create git tag (continuing anyway)"
            fi
        fi
    else
        zz_log e "Failed to generate changelog - temporary file is empty or missing"
        exit 1
    fi
fi
