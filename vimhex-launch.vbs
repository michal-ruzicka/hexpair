' ===========================================================================
' vimhex-launch.vbs - run a hexpair .cmd with no console window at all
'
' Maintainer:  Michal Ruzicka <ruzicka.mich@gmail.com>
' URL:         https://github.com/michal-ruzicka/hexpair
' License:     Vim License - same terms as Vim itself (see LICENSE.md
'              or :help license); SPDX-License-Identifier: Vim
'
'     wscript.exe vimhex-launch.vbs <path to .cmd> [args ...]
'
' Why this exists. A context-menu verb whose command is "cmd.exe /c ..."
' creates a console window for as long as the batch runs. That is a
' fraction of a second, but it is not free: it flashes, and - reported from
' the field - if a Windows Terminal window is already open, the new console
' is attached to it and STEALS THE FOCUS, so the file manager the menu was
' invoked from (Total Commander in that report) ends up in the background
' and has to be clicked back into. wscript.exe is a GUI-subsystem program,
' so nothing here ever allocates a console: the .cmd runs with window style
' 0 (hidden) and the focus stays where the user left it.
'
' The catch that comes with hiding it: a batch that stops at "pause" would
' now wait forever where nobody can see it or press a key. So this sets
' HEXPAIR_NO_PAUSE for the child, which vimhex.cmd/vimhexdiff.cmd check
' before pausing - hidden runs report through the message box below
' instead, and a run from a real console still pauses so the message can be
' read there.
'
' Output is redirected to a log file rather than captured through .Exec(),
' because .Exec() is what WOULD create the console window this exists to
' avoid. On a nonzero exit the log becomes the text of a message box - a
' real dialog rather than a console that has already closed, which is the
' whole point for "no left-hand file picked yet".
' ===========================================================================

Option Explicit

Dim shell, fso, args, i, child, logPath, rc, message, stream

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
Set args = WScript.Arguments

If args.Count < 1 Then
    MsgBox "vimhex-launch.vbs: no command to run was given." & vbCrLf & _
           "Usage: wscript.exe vimhex-launch.vbs <command.cmd> [args ...]", _
           vbExclamation, "hexpair"
    WScript.Quit 2
End If

' Inherited by the child: tells the .cmd not to stop at a "pause" it would
' be hiding behind. See the header.
shell.Environment("Process")("HEXPAIR_NO_PAUSE") = "1"

logPath = fso.BuildPath(shell.ExpandEnvironmentStrings("%TEMP%"), _
                        "hexpair-launch.log")

' Re-quote every argument. The .cmd is called with its own path first, so a
' directory or a file name holding a space survives; the .cmd files
' themselves already take care of everything past that point.
child = """" & args(0) & """"
For i = 1 To args.Count - 1
    child = child & " """ & args(i) & """"
Next

' cmd.exe's own quoting rule: with more than two quote characters present it
' strips the OUTER pair and runs the rest verbatim - which is why the whole
' command, redirection included, is wrapped in one more pair here. /d skips
' any AutoRun command a user has configured, so nothing unrelated can write
' into the log and be reported as this command's failure.
rc = shell.Run("cmd.exe /d /c """ & child & " > """ & logPath & """ 2>&1""", _
               0, True)

If rc <> 0 Then
    message = ""
    If fso.FileExists(logPath) Then
        Set stream = fso.OpenTextFile(logPath, 1)
        If Not stream.AtEndOfStream Then message = stream.ReadAll
        stream.Close
    End If
    If Trim(message) = "" Then
        message = "The command failed with exit code " & rc & "."
    End If
    MsgBox message, vbExclamation, "hexpair"
End If

WScript.Quit rc
