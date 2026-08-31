# hexpair.bashrc - open a file, or piped input, straight in hexpair's hex view
#
# Maintainer:  Michal Růžička <ruzicka.mich@gmail.com>
# URL:         https://github.com/michal-ruzicka/hexpair
# License:     Vim License - same terms as Vim itself (see LICENSE.md
#              or :help license); SPDX-License-Identifier: Vim
#
# Source it from ~/.bashrc, e.g. after installing the plugin as a Vim 8
# package:
#
#     source ~/.vim/pack/plugins/start/hexpair/hexpair.bashrc
#
# It defines one function:
#
#     vimhex FILE          the first page
#     vimhex FILE PAGE     that page, 1-based; also '$' for the last one,
#                          '$-N' for N pages back from it, and '+N' / '-N'
#                          to step from the first
#     vimhex FILE @BYTE    the page holding that byte, cursor on it;
#                          decimal or 0x-prefixed, and 1-based, so a
#                          position :HexPairPages reported can be typed
#                          straight back in. '@$' is the last byte and
#                          '@$-N' is N back from it.
#     vimhex - [...]       read from standard input instead of a file
#
#     vimhex disk.img
#     vimhex disk.img 37
#     vimhex disk.img '$'          the end of the file, without counting pages
#     vimhex disk.img '$-5'        five pages back from the end
#     vimhex disk.img '@$-0x100'   0x100 bytes back from the last one
#     vimhex disk.img @0x4a2000
#     cat disk.img | vimhex -
#     dd if=/dev/sda bs=1M count=64 | vimhex - @1024
#
# Quote anything containing a '$', or the shell reads it as a variable.
#
# A block device (/dev/sda) cannot be paged directly: the size the system
# reports for it is 0, and hexpair pages what a file says it holds. Read a
# slice of it into a file, or pipe one in as above.
#
# It also defines a second one:
#
#     vimhexdiff FILE1 FILE2   the two files side by side, each marking the
#                              bytes that differ from the other, cursors on
#                              the first difference
#
#     vimhexdiff old.img new.img
#
# The two windows are scroll-bound and both cursors land on the first
# difference. That last step is :HexPairSyncViews, and it is not decoration:
# 'scrollbind' syncs movement made from the moment a window was bound, and
# everything here happens inside VimEnter - before the loop that would have
# done the syncing has run even once. Without it the left window jumps to the
# first difference and the right one stays at the top of page 1.
#
# Afterwards they keep showing the same bytes: scrolling keeps them level, and
# a JUMP in either one - a diff jump, a search landing, :HexPairGoOffset, or a
# page turn made directly - takes the other to the same byte
# (g:hexpair_bind_pages). Moving the cursor by hand is the one thing that does
# not, since that is about this window and not about the file; :HexPairSyncViews
# is the way back from it.
#
# Only the page on screen is read, so the size of the file does not matter.
# Set VIMHEX_VIM to use a particular Vim, e.g. VIMHEX_VIM=/usr/bin/vim.
#
# gvimhex and gvimhexdiff are the same two commands, taking the same
# arguments, but opening gVim instead - VIMHEX_VIM defaults to "gvim"
# rather than "vim" there; a VIMHEX_VIM already set in the environment is
# left alone.

vimhex()
{
    if [ $# -lt 1 ] || [ $# -gt 2 ]; then
        echo "usage: vimhex FILE|- [PAGE|@BYTE]" >&2
        return 1
    fi

    local where="${2:-1}" jump

    case "$where" in
        @*)
            # A byte rather than a page number. hexpair works out which
            # page holds it - pages are plain fixed-size slices, so that is
            # a division, and it follows g:hexpair_page_size even if
            # ~/.vimrc changes it.
            where="${where#@}"
            jump='execute "HexPairGoOffset" $HEXPAIR_OPEN_WHERE'
            ;;
        *)
            # A page number, '$' for the last page, '$-N' for N back from
            # it, or '+N' / '-N' from the first. :HexPairPageGoto parses
            # them all; passing the value through the environment keeps
            # the shell out of it, which is what lets a '$' survive.
            jump='execute "HexPairPageGoto" $HEXPAIR_OPEN_WHERE'
            ;;
    esac

    # Both steps run from VimEnter, the only point that is after the
    # content has arrived in BOTH cases below: a plain -c runs after a
    # named file has been read, but BEFORE standard input has.
    if [ "$1" = "-" ]; then
        # Reading from stdin: there is no file for :HexPairOpen to page, so
        # Vim reads it all and hexpair pages the buffer it produced. The -b
        # matters - without it Vim may transcode the input on the way in,
        # and unlike a named file there is nothing to re-read with ++bin
        # afterwards. Save it with ':w FILE'; a plain ':w' has no file to
        # write back to.
        HEXPAIR_OPEN_WHERE="$where" \
            "${VIMHEX_VIM:-vim}" -b -c 'autocmd VimEnter * HexPairToggle' \
                                    -c "autocmd VimEnter * $jump" -
        return
    fi

    # HexPairOpenFile(), not `-c 'HexPairOpen ...'`: a name containing a
    # space or a literal '$' does not fully round-trip through the Ex
    # command's own argument parsing, but passing it through the environment
    # and calling the function form directly needs no escaping at all.
    HEXPAIR_OPEN_FILE="$1" HEXPAIR_OPEN_WHERE="$where" \
        "${VIMHEX_VIM:-vim}" \
            -c 'autocmd VimEnter * call HexPairOpenFile($HEXPAIR_OPEN_FILE)' \
            -c "autocmd VimEnter * $jump"
}

vimhexdiff()
{
    if [ $# -ne 2 ]; then
        echo "usage: vimhexdiff FILE1 FILE2" >&2
        return 1
    fi

    # HexPairOpenFile() and HexPairDiffWith(), not the :Ex commands, for the
    # reason given at vimhex above: a name with a space or a literal '$'
    # does not survive the Ex command line's own argument parsing, and the
    # environment plus a function call need no escaping at all.
    #
    # Everything runs from VimEnter, again for vimhex's reason, and in
    # order: open the left file, tell it what it is compared against, split
    # and open the right one in the new window, tell it the same the other
    # way round, bind the two windows' scrolling, and land on the first
    # difference.
    # Three -c options rather than eight: Vim takes at most ten, and an
    # :autocmd swallows the bars after it, so each step is one autocommand
    # made of several commands. No :windo either - IT would swallow them
    # too, and run "wincmd t" once per window. The split is "rightbelow"
    # so that FILE1 stays on the left whatever 'splitright' says.
    HEXPAIR_DIFF_A="$1" HEXPAIR_DIFF_B="$2" \
        "${VIMHEX_VIM:-vim}" \
            -c 'autocmd VimEnter * call HexPairOpenFile($HEXPAIR_DIFF_A) | call HexPairDiffWith($HEXPAIR_DIFF_B)' \
            -c 'autocmd VimEnter * rightbelow vsplit | call HexPairOpenFile($HEXPAIR_DIFF_B) | call HexPairDiffWith($HEXPAIR_DIFF_A) | setlocal scrollbind' \
            -c 'autocmd VimEnter * wincmd t | setlocal scrollbind | HexPairDiffNext | HexPairSyncViews'
}

# gvimhex and gvimhexdiff delegate to vimhex and vimhexdiff above rather
# than duplicating them, so the argument grammar stays defined in ONE
# place. (The Windows .cmd counterparts additionally share the /left and
# /right side-selection state that way.) ":-" leaves an already-set
# VIMHEX_VIM (a full gvim path, say) alone and only supplies "gvim" as the
# default vimhex/vimhexdiff would otherwise fall back to "vim" for.

gvimhex()
{
    VIMHEX_VIM="${VIMHEX_VIM:-gvim}" vimhex "$@"
}

gvimhexdiff()
{
    VIMHEX_VIM="${VIMHEX_VIM:-gvim}" vimhexdiff "$@"
}
