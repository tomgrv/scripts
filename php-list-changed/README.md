<!-- @format -->

# php-list-changed

List the PHP test parts (`core`, modules, packages) affected by a change, so
only those test suites need to run.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `php-list-changed`.

## Usage

```sh
php-list-changed [-b <base>] [-f names|paths|suites|json] [-a]
```

- Parts are discovered from `extra.merge-plugin.include` globs in the root
  `composer.json` (e.g. `modules/*/composer.json`, `packages/*/*/composer.json`).
- A change inside a part selects that part, then every part whose
  `composer.json` `require`s it (transitively).
- A change to `tests/` selects `core`.
- A change to a shared file (`app/`, `config/`, `bootstrap/`, `database/`,
  `routes/`, `resources/`, `.github/`, `composer.json|lock`, `phpunit.xml`,
  `tests/Pest.php`, `tests/TestCase.php`) selects every part.
- Parts without a `tests/` directory are never listed.
- `-b` defaults to `origin/$GITHUB_BASE_REF`, then `origin/develop`, `origin/main`.
  The diff is taken from the merge-base, so uncommitted changes count.

Formats: `names` (part paths, default), `paths` (test directories, safe to pass
to pest/phpunit whatever the testsuite names are), `suites` (testsuite names
assuming they match directory names, `core` is `Unit,Feature`), `json` (`[{name,suite,path}]`, ready for a CI matrix).

## Dependencies

`jq`, `zz_args`.

## Tests

```sh
bats test.bats
```
