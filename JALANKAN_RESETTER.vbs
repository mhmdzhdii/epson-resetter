' Launcher senyap tanpa jendela konsol hitam (Direct Windows GUI)
Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
strDir = objFSO.GetParentFolderName(WScript.ScriptFullName)
strCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & strDir & "\EpsonResetter.ps1"""
objShell.Run strCommand, 0, False
