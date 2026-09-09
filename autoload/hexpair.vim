vim9script
# ===========================================================================
# hexpair - searching a block of a file for a byte pattern
#
# The one part of this plugin written in Vim9 script, and the only reason
# for it is speed. Everything else lives in plugin/hexpair.vim, which is
# legacy script and runs on Vim 8.0; nothing here is required for the
# plugin to work, and plugin/hexpair.vim calls into this file only where
# has('vim9script') and readblob()'s offset argument are both there
# (|HexPairPagedBlobRangeSupported()|). Where they are not, the search
# reads the block as hex out of xxd and matches it with a regexp, exactly
# as it always did.
#
# WHY IT IS HERE. A search has to look at every byte of the file, and Vim
# has no primitive that finds a multi-byte pattern in a Blob. What it has
# is index(), which finds ONE byte value, and that is enough: walk every
# occurrence of one byte of the pattern and check the rest by hand. The
# walk is a loop with one builtin call per candidate, which is precisely
# the shape legacy script is slowest at and a compiled :def function is
# fastest at - measured over an 8 MiB block of random data, 210 ms in
# legacy against 45 ms here, where reading the block as hex and matching
# it costs 262 ms.
#
# WHICH BYTE TO WALK decides everything, because the walk costs one
# iteration per occurrence of it. In random data any byte is one in 256
# and it hardly matters; in a real file it matters enormously, and in the
# wrong direction - a pattern beginning 00 in a run of zeros would make
# every byte a candidate, which measured at 6.2 s for one 8 MiB block
# against 1.7 s for the same block through xxd. So the block is SAMPLED
# first, cheaply, and the pattern byte that looks rarest in it is the one
# walked. If even that one looks common, this says so (-2) and lets the
# caller read the block as hex instead: the fast path is allowed to
# decline, per block, on the block's own bytes.
#
# THE PATTERN arrives as two Blobs of the same length rather than as
# bytes, because |:HexPairFind| takes '?' for any nibble: byte k matches
# when and(hay[p + k], mask[k]) == value[k]. A fully specified byte has
# mask 0xff, "d?" has 0xf0, "??" has 0x00 - and only a fully specified
# one can be walked with index(), which is why a pattern of nothing but
# wildcards declines as well.
# ===========================================================================

# How many bytes of a block are looked at to guess how common a byte
# value is in it. A thousand is enough to tell "rare" from "common",
# which is the only question being asked, and costs about a third of a
# millisecond.
const SAMPLES = 1024

# Above this many hits out of SAMPLES, walking that byte is not worth it:
# a block is handed back for the hex reader instead. One in 32 is where
# the two cost about the same - at that density an 8 MiB block holds some
# 260 000 candidates, which walk in roughly the 260 ms the same block
# takes to read as hex and match - so it is a break-even and not a taste.
const TOODENSE = SAMPLES / 32

# Which byte of the pattern to walk, as an index into it, or -1 when
# there is none worth walking.
#
# The stride is forced ODD so that the sample cannot fall into step with
# the data. Binary files are full of powers of two - a 16-byte record, a
# 512-byte sector, a 4096-byte page - and a stride sharing a factor with
# one of those would look at the same column of every record and answer a
# question nobody asked.
def Anchor(hay: blob, mask: blob, value: blob): number
  var hl = len(hay)
  var step = hl / SAMPLES
  if step < 1
    step = 1
  elseif step % 2 == 0
    step += 1
  endif
  var best = -1
  var fewest = SAMPLES + 1
  var k = 0
  while k < len(mask)
    if mask[k] == 0xff
      var want = value[k]
      var seen = 0
      var i = 0
      while i < hl
        if hay[i] == want
          seen += 1
        endif
        i += step
      endwhile
      if seen < fewest
        fewest = seen
        best = k
      endif
      if seen == 0
        break
      endif
    endif
    k += 1
  endwhile
  return fewest > TOODENSE ? -1 : best
enddef

# Does the pattern match hay at p? The anchor byte is known to match
# already, and a byte whose mask is 0 constrains nothing.
def Matches(hay: blob, mask: blob, value: blob, p: number, skip: number): bool
  var k = 0
  var n = len(mask)
  while k < n
    if k != skip && mask[k] != 0 && and(hay[p + k], mask[k]) != value[k]
      return false
    endif
    k += 1
  endwhile
  return true
enddef

# The first byte at which the pattern matches inside hay, or -1 for no
# match, or -2 for "not searched - read this block as hex instead".
export def FindForward(hay: blob, mask: blob, value: blob): number
  var n = len(mask)
  var last = len(hay) - n
  if n == 0 || last < 0
    return -1
  endif
  var k = Anchor(hay, mask, value)
  if k < 0
    return -2
  endif
  var want = value[k]
  var i = index(hay, want, k)
  while i >= 0
    var p = i - k
    if p > last
      return -1
    endif
    if Matches(hay, mask, value, p, k)
      return p
    endif
    i = index(hay, want, i + 1)
  endwhile
  return -1
enddef

# The LAST byte at which the pattern matches and STARTS BEFORE limit, or
# -1, or -2 as above. Walked forwards and remembered, because index()
# only goes one way and a block is small enough that one pass over it is
# the cheapest way to reach its last match.
export def FindBackward(hay: blob, mask: blob, value: blob, limit: number): number
  var n = len(mask)
  var last = len(hay) - n
  if n == 0 || last < 0
    return -1
  endif
  var k = Anchor(hay, mask, value)
  if k < 0
    return -2
  endif
  var want = value[k]
  var found = -1
  var i = index(hay, want, k)
  while i >= 0
    var p = i - k
    if p >= limit || p > last
      break
    endif
    if Matches(hay, mask, value, p, k)
      found = p
    endif
    i = index(hay, want, i + 1)
  endwhile
  return found
enddef
