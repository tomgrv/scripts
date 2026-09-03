#!/bin/sh

#### GOTO DIRECTORY
cd "$(git rev-parse --show-toplevel)"

pwd

#### CONFIGURE REPO
git config core.autocrlf false

#### INTEGRATE MODIFICATIONS
echo 'Integrate modifications...'
git status --porcelain | sed 's/\(.*\)/-\1/g' | while read status; do
	index=$(echo $status | cut -c2 | sed -e 's/^ *//' -e 's/ *$//')
	local=$(echo $status | cut -c3 | sed -e 's/^ *//' -e 's/ *$//')
	file=$(echo $status | cut -c4- | sed -e 's/^ *//' -e 's/ *$//')

	if [ "$local" = 'M' -o "$local" = '?' ]; then
		if git diff -a -b -w --quiet HEAD -- "$file" 2>/dev/null; then
			if git checkout --quiet -- "$file" 2>/dev/null; then
				echo -n "."
			else
				echo "Add new file: $file"
				git add -- "$file"
			fi
		else
			echo
			echo "File changed: $file"
			git add -- "$file"
		fi
	fi
done

#### BACK
cd - >/dev/null
