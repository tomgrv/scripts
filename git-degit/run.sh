#!/bin/sh

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <github repository> [<directory>]"
    exit 1
fi

eval $(
    zz_args "Clone and degit a repository" $0 "$@" <<-help
		    - repo      repo        repository to clone
			- directory directory   directory to degit into
	help
)

host=$(echo "${repo}" | sed -E 's/https?:\/\/([^/]+)\/.*/\1/')

# Keep only the repository name, dropping any .git suffix
repo=$(echo "${repo}" | sed -E -e 's/.*github.com\/([^/]+)\/([^/]+).*/\1\/\2/' -e 's/\.git$//')

if [ -z "${directory}" ]; then
    directory=.
fi

zz_log i "Repository: ${repo}"
zz_log i "Directory: ${directory}"

mkdir -p "${directory}"

case $host in
"gitlab.com")
    curl --location "https://gitlab.com/${repo}/-/archive/master/${repo}-master.tar.gz" |
        tar --extract --ungzip --strip-components=1 --directory "${directory}"
    ;;
"bitbucket.org")
    curl --location "https://bitbucket.org/${repo}/get/master.tar.gz" |
        tar --extract --ungzip --strip-components=1 --directory "${directory}"
    ;;
"github.com")
    curl --location "https://api.github.com/repos/${repo}/tarball" |
        tar --extract --ungzip --strip-components=1 --directory "${directory}"
    ;;
*)
    zz_log e "Unsupported host: {U ${host}}"
    exit 1
    ;;
esac
