# check-large-file.ps1 - prove hexpair's writes on a file over 2 GiB,
# on native Windows, with nothing installed that Windows does not ship.
#
# Maintainer:  Michal Ruzicka <ruzicka.mich@gmail.com>
# URL:         https://github.com/michal-ruzicka/hexpair
# License:     Vim License - same terms as Vim itself (see LICENSE.md
#              or :help license); SPDX-License-Identifier: Vim
#
# Run it through test\check-large-file.cmd, which is the DRIVER and not a
# wrapper. Read that file first: it runs Vim, and this one never does.
#
# WHY IT IS SPLIT THAT WAY. Every arrangement in which PowerShell started
# Vim - Start-Process with redirected handles, `& cmd /c` with the path as
# an argument, `start /wait`, with and without capturing stdout - hung on
# the maintainer's machine, on a read of eight bytes from a 256-byte file,
# while plain `vim -es -u NONE -S file <nul` from a batch never did. Five
# explanations for that were argued and all five were wrong; the hang later
# stopped happening on its own, on the same commits, so the sixth is worth
# no more than the rest. What survives is the shape that never failed:
# BATCH RUNS VIM, PowerShell computes. It costs nothing to keep and it is
# the only arrangement with evidence behind it.
#
# That inversion is why this is a phase machine. The checks genuinely have
# to interleave with the edits - "the file grew by two bytes" cannot be
# asked after the shrink has undone it - so the driver alternates: a phase
# here writes the next edit.vim and checks the results of the last one, the
# driver runs Vim on it, and round again. State between phases lives in
# state.json beside the fixture.
#
# There is a POSIX counterpart, test/check-large-file.sh, which does the
# same checks through Git Bash and python3 - useful for Linux, WSL, and for
# exercising the Vim that Git Bash launches. This one exists because
# neither is a thing to require on a Windows machine: python3 is an install
# and cmd's `set /a` is 32-bit, while the offsets here are around 2.7
# billion. PowerShell is already what hexpair uses past 2 GiB, so this
# needs nothing the feature under test does not.
#
# WHAT IT CANNOT TELL YOU, said plainly: past 2 GiB it reads the file back
# through the same .NET FileStream calls the plugin wrote it with. A fault
# in Seek that affected reads and writes IDENTICALLY would displace the
# data consistently and go unnoticed here. What that leaves it able to
# catch is still most of what can go wrong - the expected bytes are a
# function of their offset, so a read or a write landing anywhere else
# produces a mismatch - and the length checks and the untouched-head check
# go through other calls entirely.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('setup', 'fixture', 'check1', 'check2', 'check3', 'check4')]
    [string]$Phase,
    [int]$SizeGiB = 3,
    [string]$Work = ''
)

$ErrorActionPreference = 'Stop'

# xxd's seek is a C long, 32 bits on Windows, and this is where it stops.
$XxdSeekMax = 2147483647
# The edits below rewrite the FIRST byte columns of the dump line the cursor
# is on, so the offset must be aligned to a line. Unaligned, the line starts
# up to fifteen bytes earlier and every expectation is off by that much -
# which is a fault in this script and not in the plugin, and cost a
# three-gigabyte run to find.
$BytesPerLine = 16
# Prime, and coprime with every power of two, so the pattern lines up with
# no page or block boundary: a write that is out by a whole page cannot land
# on bytes that happen to match what was expected there.
$Period = 251

$Xxd = if ($env:HEXPAIR_XXD) { $env:HEXPAIR_XXD } else { 'xxd' }
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Plugin = Join-Path (Join-Path $Root 'plugin') 'hexpair.vim'

# ---------------------------------------------------------------------------
# Predicted from the offset alone, so nothing has to be kept to compare
# against - which is the only way to check a range of a file this size.
function ExpectedHex([int64]$off, [int]$n) {
    $sb = New-Object Text.StringBuilder
    for ($i = 0; $i -lt $n; $i++) {
        [void]$sb.Append('{0:x2}' -f [int](($off + $i) % $Period))
    }
    $sb.ToString()
}

function ActualHex([string]$path, [int64]$off, [int]$n) {
    $fs = [IO.File]::OpenRead($path)
    try {
        [void]$fs.Seek($off, 'Begin')
        $buf = New-Object byte[] $n
        $got = 0
        while ($got -lt $n) {
            $r = $fs.Read($buf, $got, $n - $got)
            if ($r -le 0) { break }
            $got += $r
        }
    } finally { $fs.Close() }
    ([BitConverter]::ToString($buf, 0, $got) -replace '-', '').ToLower()
}

function FileLength([string]$path) { (Get-Item -LiteralPath $path).Length }

# The failure count lives in the state file, because each phase is its own
# process and nothing else survives between them.
function Check($what, $want, $got) {
    if ("$want" -ceq "$got") {
        Write-Host "ok   - $what"
    } else {
        Write-Host "FAIL - $what"
        Write-Host "       expected: $want"
        Write-Host "       actual:   $got"
        $script:S.Failed++
    }
}

# What the last Vim run made of its script: 'ok', or the exception it threw,
# or nothing at all if it never got that far.
function VimSaid() {
    $f = Join-Path $script:S.Work 'edit.out'
    if (-not (Test-Path $f)) {
        return 'vim wrote no result (its own output, if any, is above)'
    }
    $first = @(Get-Content -LiteralPath $f -TotalCount 1)
    if ($first.Count -eq 0) { return 'vim wrote an EMPTY result file' }
    return ([string]$first[0]).Trim()
}

# Exactly the lines given, and nothing around them. The preflight uses this
# rather than WriteEdit so that it is character for character the shape
# the simplest thing that can exercise the path - source, one call,
# write, quit. The first check to run should carry nothing it does not
# need, so that a failure there is about the plugin.
function WriteEditRaw([string[]]$lines) {
    Remove-Item -LiteralPath (Join-Path $script:S.Work 'edit.out') `
        -ErrorAction SilentlyContinue
    $lines | Set-Content -LiteralPath (Join-Path $script:S.Work 'edit.vim') -Encoding ASCII
}

# The next thing for the driver to run. `edit.out` is removed first, so a
# Vim that never starts is not credited with the previous run's answer.
function WriteEdit([string]$body) {
    $vimPlugin = $Plugin -replace '\\', '/'
    $vimOut = (Join-Path $script:S.Work 'edit.out') -replace '\\', '/'
    Remove-Item -LiteralPath (Join-Path $script:S.Work 'edit.out') `
        -ErrorAction SilentlyContinue
    # A TRACE FILE, one marker per statement, each overwriting the last. If
    # the run stops, that file holds the last statement that COMPLETED, so a
    # hang has a line number instead of a shrug.
    #
    # writefile() and not g:hexpair_debug: that traces through :echomsg, and
    # `vim -es` is SILENT Ex mode, where messages are not displayed at all.
    # An instrument that cannot report in the mode under test is no
    # instrument. HEXPAIR_DEBUG still sets the flag, for a run watched some
    # other way, but these markers are what answer the question here.
    $trace = (Join-Path $script:S.Work 'trace.out') -replace '\\', '/'
    Remove-Item -LiteralPath (Join-Path $script:S.Work 'trace.out') `
        -ErrorAction SilentlyContinue
    $debug = if ($env:HEXPAIR_DEBUG) { @('let g:hexpair_debug = 1') } else { @() }
    # HEXPAIR_NO_TRACE leaves the markers out. They cost a writefile() per
    # statement and are worth it: a run that stops leaves the last
    # statement that COMPLETED in trace.out, so a hang has a location
    # rather than a shrug.
    $traced = @()
    $n = 0
    foreach ($stmt in ($body -split "`n")) {
        if ($env:HEXPAIR_NO_TRACE) { $traced += $stmt; continue }
        if (-not $stmt.Trim()) { continue }
        $n++
        $traced += $stmt
        # Doubled quotes: the statement goes inside a Vim single-quoted
        # string, and these are dump patterns full of them.
        $safe = $stmt.Trim() -replace "'", "''"
        $traced += "  call writefile(['done $n : $safe'], '$trace')"
    }
    @(
        "source $vimPlugin"
        $debug
        'let g:hexpair_page_confirm = 0'
        "call writefile(['sourced the plugin'], '$trace')"
        'try'
        $traced
        "  call writefile(['ok'], '$vimOut')"
        'catch'
        "  call writefile(['THREW ' . v:exception], '$vimOut')"
        'endtry'
        'qa!'
    ) | Set-Content -LiteralPath (Join-Path $script:S.Work 'edit.vim') -Encoding ASCII
}

# The two lines every edit starts with: open the fixture, put the cursor on
# the byte under test. Vim spells paths with forward slashes here.
function GotoLines() {
    return ("  HexPairOpen " + ($script:S.Big -replace '\\', '/') + "`n" +
            "  HexPairGoOffset " + ($script:S.Off + 1))
}

function LoadState() {
    $script:S = Get-Content -LiteralPath (Join-Path $Work 'state.json') -Raw |
        ConvertFrom-Json
}

function SaveState() {
    $script:S | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $script:S.Work 'state.json') -Encoding ASCII
}

# ---------------------------------------------------------------------------
switch ($Phase) {

'setup' {
    if ($SizeGiB -lt 3) {
        Write-Error ("check-large-file: needs at least 3 GiB - the point is " +
            "the offsets past 2 GiB, and a smaller file never reaches them.")
        exit 1
    }
    if (-not (Test-Path -LiteralPath $Plugin)) {
        Write-Error ("check-large-file: no plugin at $Plugin - run this from " +
            "the test\ directory of a hexpair checkout.")
        exit 1
    }
    $w = Join-Path ([IO.Path]::GetTempPath()) `
        ("hexpair-large-" + [Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $w)
    $script:S = [pscustomobject]@{
        Work    = $w
        Big     = (Join-Path $w 'large.bin')
        Copy    = (Join-Path $w 'copy.bin')
        SizeGiB = $SizeGiB
        Off     = [int64]0
        Size    = [int64]0
        Tail    = ''
        Far     = ''
        Failed  = 0
        Keep    = $false
    }
    SaveState

    # The driver needs one thing from here: where the work is. A batch file
    # of `set` lines is the only way to hand it back that cmd can consume
    # without any quoting rules being involved.
    # A fixed, known name in %TEMP%: the driver has to learn where the work
    # is, and it cannot read a file inside a directory it does not know yet.
    # A batch of `set` lines is the only handoff cmd can consume with no
    # quoting rules involved - which is the whole point of this split.
    @("set WORK=$w") | Set-Content -Encoding ASCII `
        -LiteralPath (Join-Path ([IO.Path]::GetTempPath()) 'hexpair-check-large.cmd')
    Write-Host "  work directory: $w"
    Write-Host "  if a run stops, the last statement that finished is in"
    Write-Host "    $w\trace.out"

    # PREFLIGHT, before three gigabytes of disk go anywhere. Every check
    # drives Vim the same way and reads bytes through the same PowerShell
    # path, so if that does not work there is nothing to learn from building
    # the fixture first - and finding out afterwards has cost days.
    $probe = Join-Path $w 'preflight.bin'
    [IO.File]::WriteAllBytes($probe, [byte[]](0..255))
    $vimProbe = $probe -replace '\\', '/'
    $vimPlugin = $Plugin -replace '\\', '/'
    $vimOut = (Join-Path $w 'edit.out') -replace '\\', '/'
    WriteEditRaw @(
        "source $vimPlugin"
        'try'
        "  let g:hp = HexPairPagedSeekReadHexForTest('$vimProbe', 0, 8)"
        "  call writefile([g:hp], '$vimOut')"
        'catch'
        "  call writefile(['THREW ' . v:exception], '$vimOut')"
        'endtry'
        'qa!'
    )
}

'fixture' {
    LoadState
    $said = VimSaid
    if ($said -ne '0001020304050607') {
        Write-Host "check-large-file: the preflight read FAILED, so nothing below"
        Write-Host "  would mean anything. No fixture was built."
        Write-Host "  $said"
        Write-Host "  Vim is run from a batch file here, with stdin closed;"
        Write-Host "  try that command by hand to see what it says."
        exit 1
    }
    Write-Host '  preflight read ok, so the fixture is worth building'

    # An EXISTING fixture, when one is offered. Two reasons, and the second
    # is not just convenience: rebuilding three gigabytes per attempt is a
    # tax on every investigation, AND the one difference nothing has been
    # able to reproduce is that in a real run the file was written SECONDS
    # ago. Three gigabytes of dirty pages are still being flushed while Vim
    # reads at offset 2.68 GB. Point HEXPAIR_LARGE_FILE at a fixture a
    # previous run left behind and that difference is gone - if the hang
    # goes with it, that was the answer; if it stays, it never was.
    #
    # A file given this way is NOT deleted at the end, whatever the outcome.
    if ($env:HEXPAIR_LARGE_FILE -and (Test-Path -LiteralPath $env:HEXPAIR_LARGE_FILE)) {
        $script:S.Big = (Resolve-Path -LiteralPath $env:HEXPAIR_LARGE_FILE).Path
        $script:S.Keep = $true
        $script:S.Size = FileLength $script:S.Big
        Write-Host ("Reusing the fixture at {0}" -f $script:S.Big)
        if ($script:S.Size -lt 3221225472) {
            Write-Host ("  it is only {0} bytes - this needs at least 3 GiB, " -f $script:S.Size)
            Write-Host "  since the whole point is the offsets past 2 GiB."
            exit 1
        }
    } else {

    $total = [int64]$script:S.SizeGiB * 1024 * 1024 * 1024
    Write-Host ("Building a {0} GiB file with a known byte at every offset..." -f $script:S.SizeGiB)
    $block = New-Object byte[] ($Period * 4096)
    for ($i = 0; $i -lt $block.Length; $i++) { $block[$i] = $i % $Period }
    $doubled = New-Object byte[] ($block.Length * 2)
    [Array]::Copy($block, 0, $doubled, 0, $block.Length)
    [Array]::Copy($block, 0, $doubled, $block.Length, $block.Length)
    $fs = [IO.File]::Create($script:S.Big)
    try {
        [int64]$written = 0
        while ($written -lt $total) {
            $take = [Math]::Min([int64]$block.Length, $total - $written)
            # The pattern is a function of ABSOLUTE offset, so each block
            # starts where the last one left off rather than at zero.
            $start = [int]($written % $Period)
            $fs.Write($doubled, $start, [int]$take)
            $written += $take
        }
    } finally { $fs.Close() }

    $script:S.Size = FileLength $script:S.Big
    }
    Write-Host ("  {0} is {1} bytes" -f $script:S.Big, $script:S.Size)

    # Past 2 GiB, and far enough from either end that a grow and a shrink
    # both have a real tail to move. Derived from the size rather than
    # fixed, so a bigger fixture still edits somewhere sensible.
    [int64]$off = $XxdSeekMax + [int64](($script:S.Size - $XxdSeekMax) / 2)
    $script:S.Off = $off - ($off % $BytesPerLine)
    Write-Host ("  editing at byte {0}, which is past the {1} xxd can seek to here" `
        -f $script:S.Off, $XxdSeekMax)

    # Before anything is edited: the fixture really does hold the byte the
    # pattern predicts, where the edits will go. If this fails, every check
    # below compares against the wrong expectation and the run is
    # meaningless rather than red.
    Check "the fixture holds the predicted byte where the edits go" `
        (ExpectedHex $script:S.Off 8) (ActualHex $script:S.Big $script:S.Off 8)
    if ($script:S.Failed -gt 0) {
        # FATAL, not merely red. Its own comment says why: every check below
        # compares against a prediction from the offset, so a fixture that
        # does not hold what the pattern says makes the whole run
        # meaningless rather than failing. The usual cause is a REUSED
        # fixture that something has already written to: the checks below
        # edit the file they are given, so a fixture reused after a run
        # that got part way holds deadbeef where the pattern is expected.
        Write-Host ''
        Write-Host 'check-large-file: stopping - the fixture does not hold the'
        Write-Host '  bytes its own pattern predicts, so nothing below could mean'
        Write-Host '  anything. If it was reused, something has edited it since:'
        Write-Host '  unset HEXPAIR_LARGE_FILE to build a clean one.'
        exit 1
    }

    # --- 1. Same length -----------------------------------------------------
    WriteEdit ((GotoLines) + "`n" +
        "  call setline(line('.'), substitute(getline('.'), " +
        "'^\(\x\+: \)\x\x \x\x \x\x \x\x', '\1de ad be ef', ''))`n" +
        "  write")
    SaveState
}

'check1' {
    LoadState
    Check "a same-length write is accepted" 'ok' (VimSaid)
    Check "  the four bytes are what was typed" 'deadbeef' `
        (ActualHex $script:S.Big $script:S.Off 4)
    Check "  the 16 bytes before are untouched" (ExpectedHex ($script:S.Off - 16) 16) `
        (ActualHex $script:S.Big ($script:S.Off - 16) 16)
    Check "  the 16 bytes after are untouched" (ExpectedHex ($script:S.Off + 4) 16) `
        (ActualHex $script:S.Big ($script:S.Off + 4) 16)
    Check "  the length is unchanged" $script:S.Size (FileLength $script:S.Big)

    # --- 2. Grow ------------------------------------------------------------
    # Everything after the insertion moves right by two, so what was at
    # off+4 is now at off+6 - which is the assertion that the tail actually
    # SLID, rather than the file merely being longer.
    $script:S.Tail = ActualHex $script:S.Big ($script:S.Off + 4) 32
    $script:S.Far = ActualHex $script:S.Big ($script:S.Size - 32) 32
    WriteEdit ((GotoLines) + "`n" +
        "  call setline(line('.'), substitute(getline('.'), " +
        "'^\(\x\+: \)', '\1ca fe ', ''))`n" +
        "  write")
    SaveState
}

'check2' {
    LoadState
    Check "a growing write is accepted" 'ok' (VimSaid)
    Check "  the file grew by two bytes" ($script:S.Size + 2) (FileLength $script:S.Big)
    Check "  the inserted bytes are at the cursor" 'cafe' `
        (ActualHex $script:S.Big $script:S.Off 2)
    Check "  what followed moved along, intact" $script:S.Tail `
        (ActualHex $script:S.Big ($script:S.Off + 6) 32)
    Check "  and the far end of the file moved too" $script:S.Far `
        (ActualHex $script:S.Big ($script:S.Size + 2 - 32) 32)

    # --- 3. Shrink ----------------------------------------------------------
    # The one no other platform can do in place: neither Vim nor xxd can
    # shorten a file except by rewriting it, and SetLength can.
    WriteEdit ((GotoLines) + "`n" +
        "  call setline(line('.'), substitute(getline('.'), " +
        "'^\(\x\+: \)\x\x \x\x ', '\1', ''))`n" +
        "  write")
    SaveState
}

'check3' {
    LoadState
    Check "a shrinking write is accepted" 'ok' (VimSaid)
    Check "  the file is back to its original length" $script:S.Size `
        (FileLength $script:S.Big)
    Check "  what followed is back where it was" $script:S.Tail `
        (ActualHex $script:S.Big ($script:S.Off + 4) 32)
    Check "  and so is the far end" $script:S.Far `
        (ActualHex $script:S.Big ($script:S.Size - 32) 32)
    # The head is the part no edit should ever have touched, the part a
    # mis-seeked write is likeliest to have landed in - and, being under
    # 2 GiB, the one range xxd itself can be asked about, which makes it the
    # one check here that does not go through .NET at all.
    #
    # -join FIRST: xxd wraps its output, so `& $Xxd` hands back an ARRAY of
    # lines, and an array interpolated into a string is joined with SPACES -
    # which -replace then has no chance to see, having been applied to each
    # element separately. It showed up as an expectation that matched except
    # for a space in the middle of it.
    $headByXxd = ((& $Xxd -p -s 0 -l 32 $script:S.Big) -join '') -replace '\s', ''
    Check "  the start of the file was never touched (asked of xxd)" `
        (ExpectedHex 0 32) $headByXxd.ToLower()

    # --- 4. ':w {file}' -----------------------------------------------------
    WriteEdit ((GotoLines) + "`n  write " + ($script:S.Copy -replace '\\', '/'))
    SaveState
}

'check4' {
    LoadState
    Check "':w {file}' is accepted" 'ok' (VimSaid)
    if (Test-Path $script:S.Copy) {
        Check "  the copy is the same length" $script:S.Size (FileLength $script:S.Copy)
        Check "  and matches at a large offset" `
            (ExpectedHex ($script:S.Off - 4096) 16) `
            (ActualHex $script:S.Copy ($script:S.Off - 4096) 16)
    } else {
        Check "  the copy exists" 'yes' 'no'
    }

    $failed = $script:S.Failed
    Write-Host ''
    if ($failed -gt 0) {
        # The fixture stays: a failure here is about bytes in a specific
        # file at a specific offset, and deleting it takes the only copy of
        # the evidence with it. Six gigabytes is a fair price for that once.
        Write-Host "Some large-file checks FAILED ($failed)."
        Write-Host ("  the fixture is left behind: " + $script:S.Work)
        exit 1
    }
    # The work directory goes either way - it holds the copy the ':w {file}'
    # check made, which is another whole fixture's worth of disk. A SUPPLIED
    # fixture lives outside it and is left alone.
    Remove-Item -LiteralPath $script:S.Work -Recurse -Force -ErrorAction SilentlyContinue
    if ($script:S.Keep) {
        Write-Host ("The fixture was supplied, so it is left where it was: " +
            $script:S.Big)
        Write-Host "  its bytes are as they started - the grow and the shrink undo each other."
    }
    Write-Host 'All large-file checks passed.'
    exit 0
}

}

# Every phase but the last saves its own state; getting here means the phase
# ran without deciding the outcome, which is success as far as the driver is
# concerned.
if ($Phase -ne 'setup') { SaveState }
exit 0
