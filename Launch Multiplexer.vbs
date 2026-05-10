Set WshShell = CreateObject("WScript.Shell")
' This finds the folder the script is in
strPath = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
' Runs the PS1 file with a hidden window (0)
WshShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & strPath & "\multiplexer.ps1""", 0, False