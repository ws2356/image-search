# Function to search for makeappx.exe (equivalent to search_makeappx function)
function Search-MakeAppx {
    # Return the hardcoded path like the bash script
    # return 'D:\Windows Kits\10\bin\10.0.22621.0\x64\makeappx.exe'
    return (Join-Path (WindowsKitBinDir) "makeappx.exe")
}

function Search-Codesign {
    return (Join-Path (WindowsKitBinDir) "signtool.exe")
}

function WindowsKitBinDir {
    # Return the hardcoded path like the bash script
    return 'D:\Windows Kits\10\bin\10.0.22621.0\x64'
}
