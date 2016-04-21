dim objFileSys, file, folderName, folderObj, fileColl, objRegEx, newFile
 
set objFileSys = CreateObject("Scripting.FileSystemObject")
folderName = InputBox("Enter the full path where the files are located.", "Full path is required") 
 
set folderObj = objFileSys.GetFolder(folderName)
set fileColl = folderObj.Files
set objRegEx = new RegExp
 
objRegEx.Pattern = "__" ' characters that you want removed. 
objRegEx.Global = true
 
for each objFile in fileColl
newFile = objRegEx.Replace(objFile.Name, "_") ' This is what you will replace the characters with
 
objFileSys.MoveFile objFile, folderName & "\" & newFile
next 
