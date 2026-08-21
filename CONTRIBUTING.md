# For Contributors

**This document is for developers who want to build, modify or extend the plugin.**

The project lives at <https://github.com/michal-ruzicka/hexpair>. Bug
reports and patches are welcome via the project's
[issue tracker](https://github.com/michal-ruzicka/hexpair/issues) and
[pull requests](https://github.com/michal-ruzicka/hexpair/pulls).

## Prerequisites

- **Vim 8+** with the bundled `xxd` — that is the complete development
  toolchain; the plugin is pure VimScript.
- `python3` (3.8+) — generates the test fixtures and runs the release
  packaging. On Windows either install it natively (winget or the
  Microsoft Store) or package under WSL — the tarball is byte-identical
  wherever it is produced.

## Repo Layout

| Path | Description |
|---|---|
| `.github/` | GitHub Actions CI workflow (`workflows/build.yml`) |
| `dist/` | Packaged release tarballs (gitignored) |
| `plugin/hexpair.vim` | The base plugin (whole-buffer toggle); its header carries `Version:` and `Date:` — the single source of truth parsed by the packaging scripts |
| `ftplugin/xxd.vim` | Dump-editing defaults for `filetype=xxd`, bundled with the plugin |
| `doc/hexpair.txt` | Vim help documentation (`:help hexpair`) |
| `hexpair.bashrc` | The `vimhex` shell wrapper, to be sourced from `~/.bashrc`; bundled in every release tarball |
| `test/` | Headless regression tests (`run-tests.sh`, see *Testing*) |
| `.gitattributes` | Line-ending normalization rules |
| `.gitignore` | Excludes `build/` and `dist/` from version control |
| `pack-release` | POSIX wrapper around `pack-release.py` |
| `pack-release.cmd` | Windows wrapper around `pack-release.py` |
| `pack-release.py` | The packaging implementation — produces the reproducible release tarball |
| `CHANGELOG.md` | Release notes in Keep a Changelog format; bundled in every release tarball |
| `CLAUDE.md` | Project notes for Claude Code; bundled in every release tarball |
| `CONTRIBUTING.md` | Developer documentation (this file); bundled in every release tarball |
| `LICENSE.md` | Vim License; bundled in every release tarball |
| `README.md` | End-user documentation; bundled in every release tarball |

## Testing

The regression suite runs Vim headless (`vim -es`) against generated
binary fixtures and asserts byte-exact behaviour of the conversions,
the cursor-position mapping and the write path:

```sh
test/run-tests.sh
```

Every behavioural change must come with a test that fails before the
change and passes after it. The suite is intentionally dependency-free
beyond `vim`, `xxd` and `python3` (fixture generation), so it runs
identically on a developer machine and in CI.

## Packaging

```sh
./pack-release          # Linux / WSL / macOS
pack-release.cmd        # Windows (py launcher or python on PATH)
```

Both are thin wrappers around `pack-release.py` (Python standard
library only), which reads `Version:` and `Date:` from the header of
`plugin/hexpair.vim` and produces
`dist/hexpair.v<version>.tar` containing a `hexpair/` directory
ready to be extracted into `~/.vim/pack/plugins/start/`. Bump the
version *and* the date in the plugin header before tagging a release.

### Reproducible Builds

Every packaging run from the same source commit must produce a
byte-identical tarball, so users can independently verify that a
published archive was built from the published source without having
to trust the packaging machine. All platforms run the same single
implementation (`pack-release.py`), so cross-platform byte-identity
holds by construction — system tar toolchains, whose ustar writers
genuinely differ, are not involved at all.
The script normalizes every source of non-determinism:

| Source | Normalization |
|---|---|
| File modification times | Every entry carries `Date:` from the plugin header (00:00:00 UTC) |
| Archive entry order | Files are enumerated in an explicit, fixed, sorted list — no directory-walk order dependency |
| Owner / permission metadata | uid/gid `0`, empty user/group names, mode `0644` |
| Tar format variance | ustar (`tarfile.USTAR_FORMAT`) — no pax extended headers that embed sub-second times |
| Compression | None — the artifact is a plain, uncompressed `.tar` (see below) |

The archive is deliberately not compressed: compressed deflate
streams are not stable across compressor builds (classic zlib and
zlib-ng emit different, equally valid bytes for the same input), and
for an archive this small the larger size is a fair price for a
byte-identity guarantee that cannot drift with any toolchain.
Integrity and authenticity of the published artifact are covered by
its GPG signature.

The CI workflow packages the tarball on both Linux and Windows and
fails if the two SHA-256 hashes differ, which continuously guards the
claim.

## CI

The GitHub Actions workflow (`.github/workflows/build.yml`) runs on
every push and pull request. It executes the test suite on Linux and on
Windows — the same `test/run-tests.sh`, under Git Bash against the Vim
project's own Windows build, because Windows is the platform the
portability rules exist for — then both packaging scripts, and compares
the resulting hashes.

That Vim is pinned by version *and* SHA-256 (`VIM_VERSION` /
`VIM_SHA256` in the workflow), downloaded from the
`vim/vim-win32-installer` releases rather than installed by a package
manager: the same discipline the rest of the project's dependencies get.
Bump the two together, in their own commit.

The suite runs whatever `$HEXPAIR_VIM` and `$HEXPAIR_XXD` name, falling
back to `vim` and `xxd` on `PATH` — which is how the Windows job pins the
binaries under test, and how you can point the suite at one particular
Vim locally. On Windows it must be a native build: an MSYS one (Git for
Windows ships one, first on `PATH` in any Git Bash step) understands
POSIX paths and would pass the suite without testing anything the
portability rules are about, so the job checks for `MS-Windows` in
`--version` and fails if it is missing. Releases are
**not** published from CI — artifacts are signed locally and uploaded
to GitHub Releases by hand (see *Release Process* below).

All actions in the workflow are pinned to a full commit SHA (required
by the repository's *Require actions to be pinned to a full-length
commit SHA* policy).

## Signing Policy

All commits merged into `main` must be signed. Tags `v*` must also be
signed. The repository's branch and tag protection rules enforce this
server-side — unsigned commits and tags are rejected on push.

Two distinct signing mechanisms are in use:

| What | Method | Key type |
|------|--------|----------|
| Git commits and annotated tags | SSH key signing | Your SSH key |
| Release tarballs | GPG detached signature | Separate GPG key |

### Setting up SSH commit signing

You can reuse the same SSH key you already use to authenticate to GitHub.

**1. Register the key as a signing key on GitHub.**

Go to **Settings → SSH and GPG keys → New signing key** and paste your
public key. This is a separate entry from the authentication key, but
both entries can use the same key material.

**2. Configure Git for this repository.**

```
git config gpg.format ssh
git config user.signingkey "~/.ssh/id_ed25519.pub"
git config commit.gpgsign true
```

Replace `id_ed25519.pub` with your actual public key filename if
different. Omitting `--global` scopes these settings to this repository
only.

**3. Verify.**

```
git commit --allow-empty -m "test signing"
git log -1 --show-signature
```

Git should report `Good "git" signature` with your key fingerprint.

The same `gpg.format = ssh` setting is picked up by `git tag -s`, so
the release tagging step in *Release Process* below also uses your SSH
key automatically — no separate GPG key is needed for tags.

### GPG signing of release tarballs

The distributable tarball is signed with a GPG key (not the SSH key)
to produce a detached `.asc` signature that end users can verify
without having to trust GitHub's infrastructure. The signing key
fingerprint is
`489C 5EC8 0FD6 2BE8 9E59  B4F7 19C1 3E8C E0F5 DB61` (available on
<https://keys.openpgp.org/>). The exact signing steps are in the
*Release Process* section below.

## Release Process

Releases are built and signed locally; no private key ever leaves the
developer's machine.

1. On a feature branch, bump `Version:` and `Date:` in the header of
   `plugin/hexpair.vim` and add a `## [X.Y.Z] – YYYY-MM-DD` entry to
   `CHANGELOG.md`. Versions follow
   [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
   (`MAJOR.MINOR.PATCH`).
2. Open a PR, get it reviewed (CI must be green, including the
   cross-platform reproducibility check), and merge into `main`.
3. On `main`, tag and push:
   ```
   git fetch && git checkout main && git pull
   git tag -s vX.Y.Z -m "Release vX.Y.Z"
   git push origin vX.Y.Z
   ```
4. Run `./pack-release` locally to produce `dist/hexpair.vX.Y.Z.tar`.
5. GPG-sign the tarball:
   ```
   gpg --detach-sign --armor dist/hexpair.vX.Y.Z.tar
   ```
   This creates `dist/hexpair.vX.Y.Z.tar.asc`.
6. On the GitHub repository page, go to **Releases → Draft a new release**,
   select the `vX.Y.Z` tag, paste the CHANGELOG entry as the description,
   and attach both files (`.tar` and `.tar.asc`).

The CI workflow also produces the tarball as a downloadable Actions
artifact, but that copy is unsigned and is intended for testing PRs only.

## License

This project is distributed under the same terms as Vim itself (the
Vim License) — see [LICENSE.md](LICENSE.md) for the full text. The
plugin source carries an SPDX identifier
(`SPDX-License-Identifier: Vim`). Release notes are in
[CHANGELOG.md](CHANGELOG.md).
