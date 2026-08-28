# hexpair - the recording at the top of README.md
#
# Maintainer:  Michal Růžička <ruzicka.mich@gmail.com>
# URL:         https://github.com/michal-ruzicka/hexpair
# License:     Vim License - same terms as Vim itself (see LICENSE.md
#              or :help license); SPDX-License-Identifier: Vim
#
# A tape for vhs (https://github.com/charmbracelet/vhs). Record it with
# docs/hexpair-demo.sh, which makes the GIF out of the MP4 written here.
#
# What it edits is the plugin's own v2.1.0 release tarball, downloaded live.
# Three things follow from that, and all three are the point:
#
#   - it is a file anyone watching can fetch and follow along in, byte for
#     byte, because that tarball is built reproducibly - the copy the release
#     publishes is the copy on screen;
#   - it is an uncompressed ustar archive, so the ASCII column reads as
#     text - the header says `hexpair/CHANGELOG.md` and the payload is the
#     project's own documentation, multi-byte characters and all;
#   - it is renamed to .bin on the way in, and that rename is deliberate:
#     Vim's own tar plugin takes over a file called .tar and shows the
#     archive's listing, which is not what a hex editor is being shown for.
#
# Both surfaces are used on purpose. The :HP* commands are what a viewer can
# type back verbatim; the key mappings are what the maintainer actually
# presses, and a recording made only of typed commands reads as if the plugin
# had no keys. Each mapping is typed as two Type commands - the leader, a
# pause, the key - and docs/hexpair-demo.vimrc does the rest: 'showcmdloc'
# puts the half-typed mapping in the statusline where it can be seen, and a
# decoy mapping makes Vim wait on it long enough to read. See that file for
# why the leader here is `,` and not the maintainer's `§`.
#
# `:Say` is the narrator - a caption line above everything, from the demo
# vimrc. Each caption is a sentence, spells the key as `<Leader>` rather than
# as the `,` this recording happens to use, and stands for three seconds
# afterwards: a caption nobody finishes reading is worse than no caption.
#
# **Every line is left on the screen before it is sent.** Two seconds between
# the last character and the Enter, on captions, on :HP* commands and on shell
# commands alike - what somebody is meant to be able to type back has to be
# readable before it disappears into its own result. That, and the caption
# dwell, is most of the running time; the rest of the tape is barely a minute.
#
# It runs about seven minutes. Nothing breaks if it grows - the GIF is made from
# an MP4 and neither pass buffers - but every second is ten frames in a file
# that sits at the top of a README, so a second added here is paid for by
# everyone who loads that page.

Output hexpair-demo.mp4

Require vhs
Require vim
Require curl

Set Shell bash
# Wide enough for two 16-byte dump lines with their ASCII columns side by
# side once vimhexdiff splits the window - which is what sets this, since one
# of them needs barely half of it. Fifteen frames a second because the things
# worth seeing here are a progress bar and single keystrokes.
Set Width 1160
Set Height 620
Set FontSize 12
Set Padding 10
Set Margin 0
Set Framerate 15
Set Theme "Dracula"
Set WindowBar Colorful
Set TypingSpeed 45ms

# --- setup, not part of the picture ----------------------------------------
Hide
# C.UTF-8, not the machine's own locale: Vim translates its messages, and a
# recording that says "Vse" where the documentation says "All" is a recording
# of somebody's desktop. The .UTF-8 half matters as much: the bytes the demo
# stops on are a `ů`.
Type "PS1='$ ' ; unset PROMPT_COMMAND ; export HISTFILE=/dev/null LC_ALL=C.UTF-8"
Enter
# `vim` is the demo's vim (this working tree's plugin, docs/hexpair-demo.vimrc),
# and vimhex/vimhexdiff are told to use it too - they take VIMHEX_VIM.
Type 'vim() { "$HEXPAIR_DEMO_VIM" "$@" ; } ; export VIMHEX_VIM="$HEXPAIR_DEMO_VIM"'
Enter
Type 'source "$HEXPAIR_DEMO_BASHRC"'
Enter
# ~/Downloads, because the page banner carries the file's whole path and a
# recording is a nicer place for a path somebody recognises than for the
# scratch directory the recorder happened to make.
Type 'mkdir -p ~/Downloads && cd ~/Downloads'
Enter
Type "clear"
Enter
Show

# --- 1. a real file, and one anybody can fetch -----------------------------
# -# and not -s: the progress bar is the only thing on the screen that says a
# 480 KiB file is ARRIVING, and a silent curl looks like nothing happened at
# all. The URL goes in at 0ms, all at once - nobody types a URL that long, and
# watching one appear character by character is forty seconds of nothing.
Type@40ms "# The plugin's own v2.1.0 release tarball - 480 KiB, four pages."
Sleep 2s
Enter
Sleep 2s
Type "curl -#L -o original.bin '"
Type@0ms "https://github.com/michal-ruzicka/hexpair/releases/download/v2.1.0/hexpair.v2.1.0.tar"
Type "'"
Sleep 2s
Enter
Sleep 5s
Type "cp -v original.bin sample.bin"
Sleep 2s
Enter
Sleep 2s

# --- 2. an ordinary Vim, one command, and which key is <Leader> ------------
# The plugin is not a different editor and not a different way of opening a
# file: this is the file already open, in the Vim it was going to be opened in
# anyway, one command later.
Type "vim sample.bin"
Sleep 2s
Enter
Sleep 3s
# Also the first keys this Vim gets, and that matters: the very first key
# SEQUENCE a freshly started Vim receives here is swallowed - it is still
# negotiating with the terminal - so a mapping typed as the first thing does
# nothing and the recording shows Vim's own operator waiting for a motion.
# Anything typed at the : prompt is safe, so every Vim in this tape opens with
# a : command.
Type@40ms ":Say In this recording <Leader> is the comma key."
Sleep 2s
Enter
Sleep 3s
Type ":echo 'mapleader is ' . string(mapleader)"
Sleep 2s
Enter
Sleep 3s
Type@40ms ":Say Yours is whatever your own vimrc says. Every key below hangs off it."
Sleep 2s
Enter
Sleep 4s
Type@40ms ":Say One command turns this Vim into a hex editor."
Sleep 2s
Enter
Sleep 3s
Type ":HexPairToggle"
Sleep 2s
Enter
Sleep 4s
Type ":q!"
Sleep 2s
Enter
# Vim asks the terminal for its background colour on the way in, the answer
# comes back a second after it has gone, and the shell at the prompt echoes it
# as a line of escape rubbish. The wait for it and the clear that wipes it both
# happen with the recording switched off - Hide costs real time, which is
# exactly what is wanted here.
Hide
Sleep 2500ms
Type "clear"
Enter
Show
Sleep 1s

# --- 3. the other way in: name a byte, get its page ------------------------
Type@40ms "# And for a file too big to load at all, start on a page instead."
Sleep 2s
Enter
Sleep 2s
Type "vimhex sample.bin @0x50000"
Sleep 2s
Enter
Sleep 4s
Type@40ms ":Say That opened only the page holding that byte. Where are we?"
Sleep 2s
Enter
Sleep 3s
Type ":HPPages"
Sleep 2s
Enter
Sleep 4s
Type@40ms ":Say Page 3 of 4. The other three pages were never read at all."
Sleep 2s
Enter
Sleep 4s

# --- 4. hex and text, paired - shown by moving the cursor ------------------
Type@40ms ":Say Byte positions are 1-based here, the way :HPPages reports them."
Sleep 2s
Enter
Sleep 3s
Type ":HPGoOffset 1"
Sleep 2s
Enter
Sleep 3s
Type@40ms ":Say Page 1, first byte. The byte and its character light up together."
Sleep 2s
Enter
Sleep 3s
Type@450ms "lllll"
Sleep 2s
Type@450ms "jjl"
Sleep 3s
Type@40ms ":Say <Leader>> puts the cursor in the ASCII column, <Leader>< back in the hex."
Sleep 2s
Enter
Sleep 3s
Type ","
Sleep 1200ms
Type ">"
Sleep 2500ms
Type@450ms "llll"
Sleep 2500ms
Type ","
Sleep 1200ms
Type "<"
Sleep 2500ms
Type@450ms "lll"
Sleep 2500ms

# --- 5. searching: by text, and by bytes ----------------------------------
Type@40ms ":Say Searching reads the whole file a megabyte at a time, not the page on screen."
Sleep 2s
Enter
Sleep 3s
Type ":HPFindText byte-pair"
Sleep 2s
Enter
Sleep 4s
Type@40ms ":Say It turned to page 3 to land on it. Bytes work the same way."
Sleep 2s
Enter
Sleep 4s
Type ":HPFind 7573746172"
Sleep 2s
Enter
Sleep 4s
Type@40ms ":Say 75 73 74 61 72 is 'ustar' - the magic every tar header carries."
Sleep 2s
Enter
Sleep 4s

# --- 6. type over a byte, and watch the ASCII column catch up -------------
Type ":HPPageGoto 1"
Sleep 2s
Enter
Sleep 2s
Type ":HPGoOffset 1"
Sleep 2s
Enter
Sleep 2s
Type@40ms ":Say The first byte is 68, the 'h' of hexpair. Type 71 over it - a 'q'."
Sleep 2s
Enter
Sleep 3s
Type@700ms "R71"
Escape
Sleep 3s
Type@40ms ":Say Changed, and marked as changed. The ASCII column still says 'h'."
Sleep 2s
Enter
Sleep 4s
Type ":HPRefresh"
Sleep 2s
Enter
Sleep 3s
Type@40ms ":Say :HPRefresh rebuilds the view from the bytes as they are now. Disk untouched."
Sleep 2s
Enter
Sleep 4s

# --- 7. the two bytes the ASCII column cannot show -------------------------
# The `ů` of `Michal Růžička`, in the LICENSE text inside the archive: two
# bytes, two dots on the right, one character.
#
# :HexPairGoOffset 0x9976 and not 0x9975, and the tape says why in a caption
# a moment earlier. Byte POSITIONS in this plugin are 1-based - the same
# numbers :HexPairPages, the banner, the statusline, the inspector and the
# marks all report, so a position can be read off the screen and typed
# straight back in, and "the first byte" is 1 rather than 0. The offset
# COLUMN is xxd's own 0-based address and is left exactly as xxd writes it.
# The two are one apart by design; the tape's first cut assumed otherwise
# and narrated the wrong bytes for three sections.
Type ":HPGoOffset 0x9976"
Sleep 2s
Enter
Sleep 3s
Type@40ms ":Say Two bytes here, two dots, one character. <Leader>i says which."
Sleep 2s
Enter
Sleep 3s
Type ","
Sleep 1200ms
Type "i"
Sleep 5s
Enter
Sleep 1s
Type@40ms ":Say Change the second of the two and the character is gone."
Sleep 2s
Enter
Sleep 3s
Type "w"
Sleep 1500ms
Type@700ms "R61"
Escape
Sleep 2s
Type ":HPRefresh"
Sleep 2s
Enter
Sleep 4s
Type@40ms ":Say A stray byte and an 'a'. Now write a character back in, by its bytes."
Sleep 2s
Enter
Sleep 4s

# --- 8. writing a character in, by its bytes -------------------------------
Type ":HPGoOffset 0x9976"
Sleep 2s
Enter
Sleep 2s
Type ","
Sleep 1200ms
Type "I"
Sleep 2500ms
Type "Č"
Sleep 1500ms
Enter
Sleep 3s
Type@40ms ":Say c4 8c went in, and everything behind it moved along."
Sleep 2s
Enter
Sleep 4s

# --- 9. walking what has changed and not been written ----------------------
Type@40ms ":Say <Leader>e walks between the bytes you changed. There are two places."
Sleep 2s
Enter
Sleep 3s
Type ":HPGoOffset 1"
Sleep 2s
Enter
Sleep 2s
Type ","
Sleep 1200ms
Type "e"
Sleep 3s
Type ","
Sleep 1200ms
Type "e"
Sleep 3s

# --- 10. :w writes the bytes, and says what a longer file costs ------------
Type@40ms ":Say The file is two bytes longer now, so :w says what that costs."
Sleep 2s
Enter
Sleep 3s
Type ":w"
Sleep 2s
Enter
Sleep 4s
Type "W"
Sleep 3s
Type ":q"
Sleep 2s
Enter
Hide
Sleep 3s
Type "clear"
Enter
Show
Sleep 1s

# --- 11. two files side by side, each marking what the other has not -------
Type@40ms "# And the two files side by side, each marking what the other has not."
Sleep 2s
Enter
Sleep 2s
Type "vimhexdiff original.bin sample.bin"
Sleep 2s
Enter
Sleep 5s
Type@40ms ":Say <Leader>] and <Leader>[ walk between changes. A run of bytes is one change."
Sleep 2s
Enter
Sleep 3s
Type ","
Sleep 1200ms
Type "]"
Sleep 3s
Type ","
Sleep 1200ms
Type "["
Sleep 3s

# --- 12. and out, the way anybody leaves Vim -------------------------------
Type@40ms ":Say That is hexpair. :qa! to leave, like any other Vim."
Sleep 2s
Enter
Sleep 4s
Type ":qa!"
Sleep 2s
Enter
Sleep 4s
Type "ls -l original.bin sample.bin"
Sleep 2s
Enter
Sleep 4s

Hide
Type "rm -f ~/Downloads/original.bin ~/Downloads/sample.bin"
Enter
Sleep 500ms
