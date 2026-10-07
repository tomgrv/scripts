#!/bin/sh

eval $(
    zz-args "Manage tag & following tags" $0 "$@" <<-help
            f -        force      Force tag creation even if it exists
            p -        prefix     Prefix to use for the tag (default: v)
            b blame    blame      Tag the last commit where the version field in the specified JSON file was changed to the current version
		    - tag      tag        Tag to create or follow
	help
)

if [ -z "$prefix" ]; then
    prefix=$(git config gitflow.prefix.versiontag || echo "v")
fi

if [ -n "$blame" ]; then
    if [ ! -f "$blame" ]; then
        zz-log e "Blame file '$blame' does not exist"
        exit 1
    fi

    if ! echo "$blame" | grep -q "\.json$"; then
        zz-log e "Blame file '$blame' must be a JSON file"
        exit 1
    fi

    current_version=""
    if [ -n "$tag" ]; then
        # Extract version from provided tag (remove prefix)
        tag=$(echo "$tag" | sed -E "s/^$prefix//")
    else
        zz-log i "Extracting current version from '$blame'"
        tag=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$blame" | sed -E 's/.*"([^"]*)"$/\1/')
    fi

    if [ -z "$tag" ]; then
        zz-log e "Could not determine current version for blame search"
        exit 1
    fi

    zz-log i "Searching for commit where version '$current_version' was introduced in '$blame'"

    # Find the commit where the version field was last changed to the current version
    blame_commit=$(git log --follow --patch -S"$tag" --source --all -- "$blame" | grep "^commit" | head -n1 | cut -c8-47)

    if [ -z "$blame_commit" ]; then
        zz-log w "No commit found where version '$tag' was introduced in '$blame', using current HEAD"
        blame_commit="HEAD"
    else
        zz-log s "Found commit $blame_commit where version '$tag' was introduced"
    fi
fi

if [ -n "$tag" ]; then
    # Ensure tag starts with the configured prefix, defaulting to "v"
    tag=$(echo "$tag" | sed -E "s/^([0-9.]+)/$prefix\1/g; s/^[^${prefix:-0-9}]//")

    found=$(git tag --sort=v:refname | grep "$tag" | tail -n1)
else
    # If no tag is specified, use gitversion to find the release tag
    tag=$prefix$(gitversion -config .gitversion -showvariable SemVer)
    zz-log s "Tag from gitversion: $tag"
fi

if [ -z "$found" ]; then
    zz-log w "No tags found in the repository, creating a new tag: $tag"
    git tag ${force:+-f} $tag $blame_commit || exit 1
    zz-log i "Tag $tag created successfully"
elif [ -n "$force" ]; then
    zz-log w "Force flag set, moving existing tag $tag to current commit"
    git tag -f $tag $blame_commit || exit 1
    zz-log i "Tag $tag moved successfully"
else
    zz-log i "Tag $tag already exists as $found"
    tag=$found
fi

# If blame not activated and tag is a main version tag (ie: can start with prefix but does not have an hyphen), create dependent tags
if [ -z "$blame" ] && echo "$tag" | grep -qv "-"; then
    zz-log i "Creating dependent tags for $tag"

    git tag -f $(echo $tag | cut -d. -f1) $tag
    git tag -f $(echo $tag | cut -d. -f1-2) $tag

else
    zz-log i "No dependent tags created for $tag"
fi

zz-log i "Pushing tags to the remote repository"
git push --tags --force
