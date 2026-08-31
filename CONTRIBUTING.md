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
| `demo/` | The animation at the top of `README.md` and what records it (see *The README demo*); not part of a release tarball |
| `hexpair.bashrc` | The `vimhex`/`vimhexdiff` shell wrappers, and the `gvimhex`/`gvimhexdiff` GUI variants, to be sourced from `~/.bashrc`; bundled in every release tarball |
| `hexpair.vimrc` | The ready-made mappings, to be sourced from the user's vimrc; bundled in every release tarball |
| `vimhex.cmd`, `vimhexdiff.cmd` | The `cmd.exe` counterparts of the two shell functions, same names and arguments; CRLF, bundled in every release tarball |
| `gvimhex.cmd`, `gvimhexdiff.cmd` | The same two, defaulting `VIMHEX_VIM` to `gvim` — what a context-menu verb needs. They `call` the `vimhex*.cmd` beside them, so keep all four together |
| `vimhex-contex-entry.add.reg`, `.remove.reg` | Explorer context-menu submenu, added and removed. **Generated** — see `make-context-entry-reg.py`; bundled in every release tarball |
| `make-unicode-blocks.py` | Regenerates the Unicode block table inside `plugin/hexpair.vim` from `Blocks.txt`, which it pins by version and SHA-256. The data inspector names a code point's block with it; Vim has no Unicode database of its own. Development-only, not in the tarball |
| `make-context-entry-reg.py` | Generates the two `.reg` files above (they carry `REG_EXPAND_SZ` values, which `.reg` can only write as `hex(2):` plus UTF-16LE bytes). Takes an optional install path. Development-only, not in the tarball |
| `icons/` | The three context-menu icons and what draws them: `build.py` renders `hexpair-{open,pick,with}.ico` from `design.py` via `rasticon.py`, a from-scratch PNG/ICO encoder. Only the `.ico` files are bundled in a release tarball; the generators are development-only |
| `test/` | Headless regression tests (`run-tests.sh`, see *Testing*) and the large-file checks, which the suite cannot replace: they build a multi-gigabyte file and edit it past 2 GiB, the only way to exercise what Windows does there. Run by hand. `check-large-file.cmd` (`.ps1`) is the native-Windows one and needs nothing Windows does not ship — PowerShell being what hexpair itself uses past 2 GiB; `check-large-file.sh` is the POSIX one, for Linux, WSL, and the Vim that Git Bash launches, and needs `python3` |
| `.gitattributes` | Line-ending normalization rules |
| `.gitignore` | Excludes `build/`, `dist/` and the demo MP4 from version control |
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

## The README demo

`README.md` opens with `demo/hexpair-demo.gif`, about seven minutes of the
plugin at work, narrated step by step. It is recorded, not hand-made, so it can be
re-recorded whenever what it shows stops being true:

```sh
demo/hexpair-demo.sh                 # writes demo/hexpair-demo.{gif,mp4}
demo/hexpair-demo.sh /tmp/try.gif    # or somewhere else, to look first
```

Four files, and one of them is the picture:

| Path | Description |
|---|---|
| `demo/hexpair-demo.tape` | The script, for [vhs](https://github.com/charmbracelet/vhs) — what is typed, and how long each thing stays on the screen |
| `demo/hexpair-demo.vimrc` | The Vim the recording uses: the plugin out of *this* working tree, and nothing of whoever is recording |
| `demo/hexpair-demo.sh` | The runner — records the tape and turns the MP4 into the GIF |
| `demo/hexpair-demo.gif` | The result, committed because `README.md` points at it |
| `demo/hexpair-demo.mp4` | The same recording before the palette, a third of the size — a better thing to link from a blog post, and what another GIF can be made from without recording again. **Gitignored**: only one of the two belongs in a repository, and the one `README.md` points at is the GIF |

Needs `vhs` (which needs `ttyd` and `ffmpeg`), `vim`, `curl` and a network
connection. Linux only, deliberately — vhs is.

**What it edits is the plugin's own v2.1.0 release tarball**, fetched live
from the GitHub release. That is worth keeping: the tarball is built
reproducibly, so the bytes on screen are the bytes anybody else gets —
fetch the same 480 KiB and follow along, offset for offset. It is also an uncompressed `ustar` archive, so the ASCII
column reads as text — the header says `hexpair/CHANGELOG.md`, the payload
is the project's own documentation, and the `ů` in `Michal Růžička` is the
multi-byte character the data inspector stops on. The `.bin` name is
deliberate too: Vim's own `tar` plugin takes over a file called `.tar` and
shows the archive's listing instead of its bytes.

Things about it that are deliberate and worth keeping:

- **Both surfaces are shown.** The `:HP*` commands are what a viewer can
  type back verbatim; the key mappings are what the maintainer actually
  presses, and a recording made only of typed commands reads as if the
  plugin had no keys.
- **Three things in the demo vimrc make a key press visible**, and all
  three are needed. A mapping Vim can complete is executed the instant its
  last key arrives, so the key never appears: `'showcmd'` shows only a
  mapping Vim is still *waiting* on. Hence the **decoys** — `,ix` is
  mapped to `<Nop>` so that `,i` is ambiguous and Vim has to wait out
  `'timeoutlen'`, which is the second and a half the whole mapping spends
  on the screen. And `'showcmdloc=statusline'` moves it out of the bottom
  right, where nobody is looking, into the statusline beside the file
  name, in a highlight of its own. The decoys do nothing else and are the
  reason that file is not something to copy into a real vimrc.
- **Nothing is sent until it has been read.** Two seconds between the last
  character typed and the `Enter`, on captions, on `:HP*` commands and on
  shell commands alike. What a viewer is meant to be able to type back has to
  be readable before it disappears into its own result, and a command that
  flashes past is a command nobody learns. That, and the caption dwell, is
  most of the running time — the tape itself is barely a minute of keystrokes.
- **Byte positions are 1-based, and the tape says so out loud.** Every number
  this plugin reports as a position — `:HexPairPages`, the banner, the
  statusline, `:HexPairInspect`, `:HexPairMarks` — counts the file's first byte
  as 1, so a position can be read off the screen and typed straight back into
  `:HexPairGoOffset`, and "go to the first byte" is the 1 a person would
  naturally write. The offset *column* is `xxd`'s own 0-based address, left
  exactly as `xxd` writes it. The two are one apart by design.

  It earns a caption because a viewer following along hits it in the first
  minute, and because the tape's own author did not read his own documentation:
  the first cut asked for `:HPGoOffset 0`, was refused, and narrated the wrong
  bytes for three sections. Recording a tour of a plugin is a good way to find
  out which of its rules you only thought you knew.
- **`:Say` is the narrator** — a caption line in the tabline, from the
  demo vimrc, so a viewer knows what is about to happen rather than
  working it out afterwards. It uses `redraw!` and not `redraw`: setting a
  variable does not make Vim think the tabline changed, so the plain one
  repaints everything except the line it is for. The tape types each
  caption at a reading pace and then leaves it standing for three seconds,
  which is where most of the running time goes — a caption nobody finishes
  reading is worse than no caption. Each is a sentence, and each spells the
  key as `<Leader>`, not as the `,` this recording happens to use.
- **`curl -#`, and the URL at `Type@0ms`.** The progress bar is the only
  thing on the screen that says a 480 KiB file is *arriving*; a silent curl
  looks like nothing happened. (`-v` was tried and dropped: four screens of
  TLS handshake scrolling past is evidence of nothing anybody was asking
  about, and it cost more of the GIF than the whole download was worth.) The
  URL goes in all at once because nobody types a URL that long, and watching
  one appear character by character is forty seconds of nothing.
- **The leader in the recording is `,`, not the maintainer's `§`.** vhs
  cannot type a non-ASCII character reliably — it sends those by a
  different path and they arrive out of order, so `§>` reaches Vim as `>`
  followed by `§` and the mapping never matches.
- **The first keys after Vim starts are a `:` command, not a mapping.**
  A freshly started Vim here swallows the first key sequence — it is
  still negotiating with the terminal — and a mapping typed as the very
  first thing does nothing. The tour opens with `:HPPages` for that
  reason as much as for what it says.
- **It records to MP4 and the GIF is made from that.** vhs's own GIF
  writer builds the whole file in memory and is OOM-killed on a recording
  this long, leaving a zero-byte file and no error; the two-pass palette
  conversion streams and does not care how long the tape is. The runner
  also keeps its work out of `/tmp` — where that is a tmpfs, the frames
  fill it — and out of any deep directory, because the headless browser
  vhs renders with puts a unix socket there and the path may not exceed
  about 104 characters. `HEXPAIR_DEMO_TMP` says where to put it instead.
- **The terminal queries are turned off with `--cmd`, not in the vimrc.**
  Vim asks the terminal for its background colour during startup, before a
  vimrc is read, and the answer arrives seconds *after* Vim has exited —
  where the shell at the prompt echoes it as a line of escape rubbish in
  the middle of the recording.
- **No dithering, 24 colours, 8 fps.** A terminal has a dozen or so colours
  to begin with — a theme, a handful of highlight groups, and one font's
  anti-aliasing — so dithering invents noise that nothing can compress.
  Both knobs are worth turning, and how much each buys depends on how much
  of the screen moves, which is worth knowing before turning either.
  Measured on the current tape:

  |          | fps=6 | fps=8 | fps=10 |
  |---|---|---|---|
  | 16 colours | 4.8M | 5.4M | 6.0M |
  | 24 colours | 5.2M | 6.1M | 6.6M |
  | 32 colours | 5.7M | — | 7.5M |

  A *short* recording is mostly a still screen, and the frame rate then costs
  almost nothing — three per cent between 10 and 15 on the two-minute version
  of this tape, which is where the old defaults came from and why this file
  used to say the frame rate was not a knob at all. It is, once the tape is
  seven minutes and moving most of the time. `HEXPAIR_DEMO_COLORS` and
  `HEXPAIR_DEMO_FPS` are the knobs; the MP4 is never resampled, so a different
  GIF costs a conversion and not a recording.

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
   `plugin/hexpair.vim` and finish the `## [X.Y.Z] – YYYY-MM-DD` entry in
   `CHANGELOG.md`. Versions follow
   [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
   (`MAJOR.MINOR.PATCH`).

   Before bumping, read the release as a stranger would. A changelog
   entry written over a long cycle describes the cycle, not the release,
   and the last time this was checked it contradicted itself four ways —
   so it is worth going through:

   - **Does the entry describe the release, or its history?** Nothing may
     announce a feature as unfinished that a later bullet then finishes,
     or credit a file that no release ever contained. One section per
     type, and `Fixed` is what a *released* version did wrong: a bug
     introduced and fixed inside one cycle names code no release ever
     shipped, so it belongs in `CLAUDE.md`'s bug table, next to the test
     that keeps it from coming back.
   - **Is every runtime message still true?** They outlive the behaviour
     they describe. Grep the strings the plugin can print and read them
     against what the code now does.
   - **Is every code path tested from every entry point it has?** Two
     views reach the same write path by different routes; a test that
     only drives one of them covers half of it.
   - **Do `CLAUDE.md` and the help still speak in the future tense** about
     anything that now ships?
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
