# Third-party notices

`hexpair` itself is under the Vim License — see `LICENSE.md`. This file
carries the notices that third-party material inside it requires, and
nothing here changes the terms of the plugin as a whole.

## The Unicode block table

`plugin/hexpair.vim` contains a table of Unicode block ranges and names,
used by `:HexPairInspect` to say which block a code point belongs to. It is
derived from `Blocks.txt` of the Unicode Character Database, version 16.0.0,
by `make-unicode-blocks.py` in this repository — the ranges and their names,
mechanically extracted, with nothing added and nothing interpreted.

Source: <https://www.unicode.org/Public/16.0.0/ucd/Blocks.txt>
SHA-256: `f3907b395d410f1b97342292ca6bc83dd12eb4b205f2a0c48efdef99e517d7b0`
SPDX-License-Identifier: `Unicode-3.0`

The Unicode License V3 permits use, modification and distribution of the
Data Files provided its copyright and permission notice appears with the
copies or in the associated documentation. It is reproduced in full below,
verbatim, which is how this project satisfies that condition.

Unicode and the Unicode Logo are registered trademarks of Unicode, Inc. in
the United States and other countries. Naming the source of the data here
is a statement of provenance and not an endorsement, and the name is not
used to promote this plugin.

---

```
UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.
```
