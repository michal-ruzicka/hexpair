#!/usr/bin/env python3
"""hexpair's three Explorer context-menu icons.

A gVim-ish base mark - a white V on Vim's own green, original rather than
extracted from a real gvim.exe (there is no Windows box handy to pull the
real one off of) - plus two badges:

- bottom-right, smaller: a "0x" chip in the blocky 5x7 font, marking these
  as hexpair's own entries.
- bottom-left, bigger, only on the diff pair: two window panes side by
  side, echoing vimhexdiff's own actual `vsplit` - blue on the left,
  orange on the right, the side THIS icon represents shown at full colour
  and the other dimmed. Chosen over a top-right diff mark plus a top-left
  L/R letter (the first design) because at 16px neither text nor an arrow
  reads reliably - colour still does.
"""

from rasticon import fill_rect, fill_round_rect, fill_triangle, draw_text

VIM_GREEN = (1, 152, 51, 255)
WHITE = (255, 255, 255, 255)
DARK_FRAME = (17, 24, 39, 255)  # near-black - both badges' backdrop

LEFT_ON = (37, 99, 235, 255)    # blue - left pane, active
RIGHT_ON = (249, 115, 22, 255)  # orange - right pane, active
LEFT_OFF = (24, 50, 108, 255)   # same blue, dimmed toward DARK_FRAME
RIGHT_OFF = (98, 56, 33, 255)   # same orange, dimmed toward DARK_FRAME


def base_mark(c):
    fill_round_rect(c, 0.04, 0.04, 0.96, 0.96, 0.22, VIM_GREEN)
    fill_triangle(c, (0.22, 0.16), (0.42, 0.16), (0.50, 0.58), WHITE)
    fill_triangle(c, (0.58, 0.16), (0.78, 0.16), (0.50, 0.58), WHITE)


def hex_badge(c):
    fill_round_rect(c, 0.55, 0.58, 0.94, 0.94, 0.06, DARK_FRAME)
    draw_text(c, "0x", 0.60, 0.66, 0.90, 0.87, WHITE)


def diff_split_badge(active):
    """active: 'left' or 'right' - which pane this icon lights up."""
    left = LEFT_ON if active == "left" else LEFT_OFF
    right = RIGHT_ON if active == "right" else RIGHT_OFF

    def draw(c):
        x0, y0, x1, y1 = 0.04, 0.50, 0.50, 0.94
        r = 0.05
        fill_round_rect(c, x0, y0, x1, y1, r, DARK_FRAME)
        mid = (x0 + x1) / 2
        fill_rect(c, x0 + r, y0 + r, mid, y1 - r, left)
        fill_rect(c, mid, y0 + r, x1 - r, y1 - r, right)

    return draw


def compose(*layers):
    def spec(canvas):
        for layer in layers:
            layer(canvas)

    return spec


# name -> spec, name also used as the shipped .ico's basename
ICONS = {
    "hexpair-open": compose(base_mark, hex_badge),
    "hexpair-pick": compose(base_mark, hex_badge, diff_split_badge("left")),
    "hexpair-with": compose(base_mark, hex_badge, diff_split_badge("right")),
}
