#!/bin/sh

# Function to print help and manage arguments
eval $(
    zz_args "Manage tag & following tags" $0 "$@" <<-help
            f -        force      Force tag creation even if it exists
            p -        prefix     Prefix to use for the tag (default: v)
            b blame    blame      Tag the last commit where the version field in the specified JSON file was changed to the current version
		    - tag      tag        Tag to create or follow
	help
)

if [ -z "$prefix" ]; then
    prefix=$(git config gitflow.prefix.versiontag || echo "v")
fi

# Handle blame option to find commit where version field was changed
if [ -n "$blame" ]; then
    if [ ! -f "$blame" ]; then
        zz_log e "Blame file '$blame' does not exist"
        exit 1
    fi
    
    # Ensure blame file is a JSON file
    if ! echo "$blame" | grep -q "\.json$"; then
        zz_log e "Blame file '$blame' must be a JSON file"
        exit 1
    fi
    
    # Get the current version from the specified file
    current_version=""
    if [ -n "$tag" ]; then
        # Extract version from provided tag (remove prefix)
        tag=$(echo "$tag" | sed -E "s/^$prefix//")
    else
        # Extract current version from the JSON file
        zz_log i "Extracting current version from '$blame'"
        tag=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$blame" | sed -E 's/.*"([^"]*)"$/\1/')
    fi
    
    if [ -z "$tag" ]; then
        zz_log e "Could not determine current version for blame search"
        exit 1
    fi
    
    zz_log i "Searching for commit where version '$current_version' was introduced in '$blame'"
    
    # Find the commit where the version field was last changed to the current version
    blame_commit=$(git log --follow --patch -S"$tag" --source --all -- "$blame" | grep "^commit" | head -n1 | cut -c8-47)

    if [ -z "$blame_commit" ]; then
        zz_log w "No commit found where version '$tag' was introduced in '$blame', using current HEAD"
        blame_commit="HEAD"
    else
        zz_log s "Found commit $blame_commit where version '$tag' was introduced"
    fi
fi

if [ -n "$tag" ]; then
    # Ensure tag starts with the configured prefix, defaulting to "v"
    tag=$(echo "$tag" | sed -E "s/^([0-9.]+)/$prefix\1/g; s/^[^${prefix:-0-9}]//")

    # Check if the tag already exists in the repository
    found=$(git tag --sort=v:refname | grep "$tag" | tail -n1)
else
    # If no tag is specified, use gitversion to find the release tag
    tag=$prefix$(gitversion -config .gitversion -showvariable SemVer)
    zz_log s "Tag from gitversion: $tag"
fi

# Create or move tag
if [ -z "$found" ]; then
    zz_log w "No tags found in the repository, creating a new tag: $tag"
    git tag ${force:+-f} $tag $blame_commit || exit 1
    zz_log i "Tag $tag created successfully"
elif [ -n "$force" ]; then
    zz_log w "Force flag set, moving existing tag $tag to current commit"
    git tag -f $tag $blame_commit || exit 1
    zz_log i "Tag $tag moved successfully"
else
    zz_log i "Tag $tag already exists as $found"
    tag=$found
fi

# If blame not activated and tag is a main version tag (ie: can start with prefix but does not have an hyphen), create dependent tags
if [ -z "$blame" ] && echo "$tag" | grep -qv "-"; then
    zz_log i "Creating dependent tags for $tag"

    # Force update dependent tags
    git tag -f $(echo $tag | cut -d. -f1) $tag
    git tag -f $(echo $tag | cut -d. -f1-2) $tag

else
    zz_log i "No dependent tags created for $tag"
fi

zz_log i "Pushing tags to the remote repository"
git push --tags --force
