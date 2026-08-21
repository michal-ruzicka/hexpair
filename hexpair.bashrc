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
#     vimhex FILE PAGE     that page, 1-based
#     vimhex FILE @BYTE    the page holding that byte, cursor on it;
#                          decimal or 0x-prefixed, and 1-based, so a
#                          position :HexPairPages reported can be typed
#                          straight back in
#     vimhex - [...]       read from standard input instead of a file
#
#     vimhex disk.img
#     vimhex disk.img 37
#     vimhex disk.img @0x4a2000
#     cat disk.img | vimhex -
#     dd if=/dev/sda bs=1M count=64 | vimhex - @1024
#
# Only the page on screen is read, so the size of the file does not matter.
# Set VIMHEX_VIM to use a particular Vim, e.g. VIMHEX_VIM=/usr/bin/vim.

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
