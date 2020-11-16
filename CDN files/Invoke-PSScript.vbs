p = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
location = p &"\"& WScript.Arguments(0)
command = "powershell.exe -nologo -ExecutionPolicy Bypass -File """ &location &""""
set shell = CreateObject("WScript.Shell")
shell.Run command,0