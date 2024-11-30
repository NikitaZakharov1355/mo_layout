param(
    [string]$dir
)
[Console]::TreatControlCAsInput = $true

function Check-QuitEvent {
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if (($key.Modifiers -band [ConsoleModifiers]::Control) -and ($key.Key -eq 'C') -or 
         $key.Key -eq 'Q' -or $key.Key -eq 'q' -or $key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') {
            Write-Host "Exiting..."
            exit(0)
        }
    }
}
Check-QuitEvent
if([string]::IsNullOrEmpty($dir)){
    $dir= "test"
}
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentDir = Split-Path -Parent $scriptDir
try{

$jsonFilePath= "$($scriptDir)/settings_$($dir).json"
$jsonContent = Get-Content -Path $jsonFilePath -Raw 2>$null
if(-not $jsonContent){
    Write-Host "Environment settings file doesn't exist. Exiting..." -ForegroundColor Red
    exit 0
}
$config = $jsonContent | ConvertFrom-Json
}catch{
   Write-Host "Error loading the JSON file. Please check its structure and try again." -ForegroundColor Red
    exit 0
}

$localDir = Join-Path -Path $parentDir -ChildPath "$($config.upload.local_dir)"
$ftpConfig = $config.ftp
$filesToInclude = $config.upload.include
$filesToExclude = $config.upload.exclude
if($filesToExclude -and $filesToInclude){
    $filesToExclude=$null
    Write-host "Both the include and exclude lists were provided; only the include list will be considered." -ForegroundColor Yellow
}
if ($filesToInclude) {
    for ($i = 0; $i -lt $filesToInclude.Count; $i++) {
        $filesToInclude[$i] = "$($config.upload.dir)/$($filesToInclude[$i])"
    }
}
if($filesToExclude) {
    for ($i = 0; $i -lt $filesToExclude.Count; $i++) {
        $filesToExclude[$i] = "$($config.upload.dir)/$($filesToExclude[$i])"
    }
}
Check-QuitEvent
Write-host "Press 'q' to exit" -ForegroundColor Yellow
if($dir -eq "prod"){
    $userInput = Read-Host "You are about to upload files to production environment. Are you sure you want to proceed? (Press Y)"
    if($userInput -ne "Y" -and $userInput -ne "y"){
        exit(0)
    }
}
function Test-FTPLogin {
    param (
        [string]$ftpHost,
        [string]$ftpUser,
        [string]$ftpPassword
    )

    # # Ensure the ftpHost starts with 'ftp://'
    # if (-not $ftpHost.StartsWith("ftp://")) {
    #     $ftpHost = "ftp://$ftpHost"
    # }

    try {
        # Create an FTP WebRequest
        $request = [System.Net.FtpWebRequest]::Create("ftp://$($ftpHost)")
        $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $request.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPassword)
        $request.UseBinary = $true
        $request.KeepAlive = $false 

        # Get response to test credentials
        $response = $request.GetResponse()
        $response.Close()
        Write-Output "FTP login successful."
        return $true
    } catch {
        Write-Output "FTP login failed: $($_.Exception.Message)"
        return $false
    }
}
# Function to get the remote file size and modification time
function Get-RemoteFileDetails($ftpUri) {
    $ftpRequest = [System.Net.FtpWebRequest]::Create($ftpUri)
    $ftpRequest.Method = [System.Net.WebRequestMethods+Ftp]::GetFileSize
    $ftpRequest.Credentials = New-Object System.Net.NetworkCredential($ftpUsername, $ftpPassword)

    try {
        $ftpResponse = $ftpRequest.GetResponse()
        $size = $ftpResponse.ContentLength
        $ftpResponse.Close()

        # Fetch last modification time
        $ftpRequest = [System.Net.FtpWebRequest]::Create($ftpUri)
        $ftpRequest.Method = [System.Net.WebRequestMethods+Ftp]::GetDateTimestamp
        $ftpRequest.Credentials = New-Object System.Net.NetworkCredential($ftpUsername, $ftpPassword)
        
        $ftpResponse = $ftpRequest.GetResponse()
        $modTime = $ftpResponse.LastModified
        $ftpResponse.Close()

        return @{ Size = $size; LastModified = $modTime }
    }
    catch {
        return $null
    }
}
# Check if a file or directory path exactly matches any of the included paths
function Is-Included {
    param (
        [array]$includePaths,
        [string]$path
    )

    foreach ($includePath in $includePaths) {
        # Check if it's an exact match for a file
        if ($path -eq $includePath) {
            return $true
        }
        # Check if the file is within an included directory (for directories ending with / or \)
        if ($includePath.EndsWith("/") -or $includePath.EndsWith("\")) {
            if ($path -like "$includePath*") {
                return $true
            }
        }
    }
    return $false
}
function Is-Excluded {
    param (
        [array]$ExcludePaths,
        [string]$path
    )

    foreach ($ExcludePath in $ExcludePaths) {
        # Check if it's an exact match for a file
        if ($path -eq $ExcludePath) {
            return $true
        }
        # Check if the file is within an included directory (for directories ending with / or \)
        if ($ExcludePath.EndsWith("/") -or $ExcludePath.EndsWith("\")) {
            if ($path -like "$ExcludePath*") {
                return $true
            }
        }
    }
    return $false
}

# Function to update cache version in HTML files
function Update-CacheVersion($filePath) {
    $randomNumber = Get-Random -Minimum 10000 -Maximum 99999
    $content = Get-Content -Path $filePath -Raw
    $updatedContent = $content -replace '\{cache_version\}', $randomNumber
    $tempFilePath = Join-Path -Path $env:TEMP -ChildPath (Split-Path -Leaf $filePath)
    $updatedContent | Set-Content -Path $tempFilePath
    return $tempFilePath
}

function Create-FtpDirectory($ftpUri) {
     # Convert the URI to a path format we can work with
    $baseUri = $ftpUri.Substring(0, $ftpUri.IndexOf("/", 6)) # Get base FTP url
    $pathParts = $ftpUri.Substring($ftpUri.IndexOf("/", 6) + 1).Split("/")
    
    # Initialize the current path
    $currentPath = $baseUri

    # Try to create each directory in the path
    foreach ($part in $pathParts) {
        if ($part) {  # Skip empty parts
            $currentPath = "$currentPath/$part"
            
            # Check if directory exists
            $ftpRequest = [System.Net.FtpWebRequest]::Create($currentPath)
            $ftpRequest.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
            $ftpRequest.Credentials = New-Object System.Net.NetworkCredential($ftpUsername, $ftpPassword)
            
            try {
                $ftpResponse = $ftpRequest.GetResponse()
                $ftpResponse.Close()
                # Directory already exist
            }
            catch {
                # Directory doesn't exist, try to create it
                try {
                    $ftpRequest = [System.Net.FtpWebRequest]::Create($currentPath)
                    $ftpRequest.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
                    $ftpRequest.Credentials = New-Object System.Net.NetworkCredential($ftpUsername, $ftpPassword)
                    
                    $ftpResponse = $ftpRequest.GetResponse()
                    $ftpResponse.Close()
                    
                }
                catch {
                    Write-Error $_.Exception.Message
                    return $false
                }
            }
        }
    }
    
    return $true
}



# Function to check if remote directory exists
function Check-FtpDirectoryExists($ftpUri) {
    $ftpRequest = [System.Net.FtpWebRequest]::Create($ftpUri)
    $ftpRequest.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
    $ftpRequest.Credentials = New-Object System.Net.NetworkCredential($ftpUsername, $ftpPassword)

    try {
        $ftpResponse = $ftpRequest.GetResponse()
        $ftpResponse.Close()
        return $true
    }
    catch {
        return $false
    }
}
function Show-Notification() {
    $ErrorActionPreference = "Stop"
    $notificationTitle = "Transfers finished"
    $notificationMessage = "Files were transferred successfully!"

    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
    $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)

    $toastXml = [xml] $template.GetXml()

    # Set the title and message text
    $toastXml.GetElementsByTagName("text").Item(0).AppendChild($toastXml.CreateTextNode($notificationTitle)) > $null
    $toastXml.GetElementsByTagName("text").Item(1).AppendChild($toastXml.CreateTextNode($notificationMessage)) > $null

    # Create the toast notification
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml.OuterXml)

    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $toast.Tag = "Test1"
    $toast.Group = "Test2"
    $toast.ExpirationTime = [DateTimeOffset]::Now.AddSeconds(5)

    # Show the toast notification without specifying a custom application identifier
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe")
    $notifier.Show($toast)

}

function Invoke-ExternalScript {
    param (
        [string]$url
    )

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get
        Write-Host "Executed script at $($url) successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to execute script at $($url): $_" -ForegroundColor Red
    }
}

#START SCRIPT WORKFLOW
Write-Host "Fetching the latest changes from the remote repository..."
& git -C $localDir fetch origin

$localCommit = & git -C $localDir rev-parse HEAD
$remoteCommit = & git -C $localDir rev-parse origin/main

if ($localCommit -ne $remoteCommit) {
    Write-Host "Local branch is not up to date with the remote. Exiting..." -ForegroundColor Red
    exit 1
}

$uncommittedChanges = & git -C $localDir status --porcelain

if ($uncommittedChanges) {
    Write-Host "There are uncommitted changes in the working directory. Exiting..." -ForegroundColor Red
    exit 1
}
#
 Write-Host "Local files match the latest version in GitHub. Proceeding with FTP upload." -ForegroundColor Green

# Execute scripts before uploading
if ($config.trigger.before_upload) {
    Write-Host "Executing 'before upload' scripts..." -ForegroundColor Yellow
    foreach ($scriptUrl in $config.trigger.before_upload) {
        Invoke-ExternalScript -url $scriptUrl
    }
}
Check-QuitEvent
$numOfDirExist=0
# Upload files and directories preserving the structure
foreach($ftp in $ftpConfig){
    $ftpHost = $ftp.host
    $ftpUsername = $ftp.username
    $ftpPassword = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ftp.password))
    if(-not (Check-FtpDirectoryExists("ftp://$($ftpHost)"))){
        Write-Host "Could not login to FTP with the credentials you provided." -ForegroundColor Red
        continue
    }
    $remoteDir = $ftp.remote_dir
    if (-not $remoteDir.StartsWith("/")) {
        $remoteDir = "/" + $remoteDir
    }

    # Ensure the path ends with a "/"
    if (-not $remoteDir.EndsWith("/")) {
        $remoteDir = $remoteDir + "/"
    }
    $ftpUri = "ftp://$($ftpHost)$($remoteDir)"
    Write-Host "Start upload process to $($ftpHost)$($remoteDir)"
    Write-Host $ftpUri
    # Ensure remote directory exists
    if (-not (Check-FtpDirectoryExists $ftpUri)) {
        $readInput=Read-Host "Remote directory '$($remoteDir)' does not exist. Would you like to create this folder? (press Y)"
        if($readInput -eq "y" -or $readInput -eq "Y"){

            if(Create-FtpDirectory $ftpUri){
                Write-Host "Remote directory $($remoteDir) successfully created" -ForegroundColor Green 
            }else{
                Write-Host "Remote directory '$remoteDir' could not be created. Cancelling upload..." -ForegroundColor Red
                continue 
            }
        }else{
            Write-Host "Skipping..." -ForegroundColor Yellow
            continue
        }
       
    } 
    $numOfDirExist++
    $allItems = Get-ChildItem -Path $localDir -Recurse
    $dirs = $allItems | Where-Object { $_.PSIsContainer }
    $files = $allItems | Where-Object { -not $_.PSIsContainer }

    Write-Host "Found $($dirs.Count) directories and $($files.Count) files to upload." -ForegroundColor Green

    # Upload directories first (including empty ones)
    foreach ($dirItem in $dirs) {
        $relativePath = "$($dirItem.FullName.Substring($localDir.Length).TrimStart("\").Replace("\", "/"))/"
          if($filesToInclude){
            if (-not (Is-Included $filesToInclude "$($config.upload.dir)/$($relativePath)")) {
                continue
            }
        }
        if($filesToExclude){
            if(Is-Excluded $filesToExclude "$($config.upload.dir)/$($relativePath)"){
                continue
            }
        }
        $ftpDirUri = "ftp://$($ftpHost)$($remoteDir)$($relativePath)"
        if (-not (Check-FtpDirectoryExists $ftpDirUri)) {
            Write-Host "Creating directory on FTP: $ftpDirUri" -ForegroundColor Yellow
            if(-not (Create-FtpDirectory $ftpDirUri)){
                Write-Host "Remote directory $($remoteDir) could not be created. skipping..."
            }
        }
        
    }
    # Create an empty array to store the JavaScript file names
$filesToObfuscate = @()

# Get all HTML files in the specified directory
$htmlFiles = Get-ChildItem -Path $localDir -Filter *.html -Recurse
# Define a regex to match script tags with 'data-compile="true"'
    
    $regex = '<script\s(?=(?:[^>]*\s)?data-compile=[''"]true[''"])(?=(?:[^>]*\s)?src=[''"]([^''"]*)[''"]).*?>'
# Iterate through each HTML file
foreach ($file in $htmlFiles) {
    # Read the content of the HTML file
    $content = Get-Content $file.FullName -Raw
    # Find all matches in the content
    $matches = [regex]::Matches($content, $regex)
  
    # Iterate over each match found
    foreach ($match in $matches) {
        # Extract the full src path
        $fullPath = $match.Groups[1].Value
        # Extract just the filename without path or query parameters
        $filename = [System.IO.Path]::GetFileNameWithoutExtension($fullPath) + ".js"    
        # Add the file name to the array if it's not already there
        if ($filesToObfuscate -notcontains $filename) {
            $filesToObfuscate += $filename
        }
    }
}

    # Upload files
    $uploadedFiles = 0
    $scannedFiles=0
    foreach ($file in $files) {
        if (Check-QuitEvent) {
        write-host "Exiting..."
        exit(0)
        }
        $relativePath = $file.FullName.Substring($localDir.Length).TrimStart("\").Replace("\", "/")
       $scannedFiles++
        $ftpFileUri = "ftp://$($ftpHost)$($remoteDir)/$($relativePath)"
        if($filesToInclude){
            if (-not (Is-Included $filesToInclude "$($config.upload.dir)/$($relativePath)")) {
                Write-Host "File excluded; skipping file: $($file.name) (File $($scannedFiles)/$($files.Count))" -ForegroundColor Yellow
                continue
            }
        }
        if($filesToExclude){
            if(Is-Excluded $filesToExclude "$($config.upload.dir)/$($relativePath)"){
                Write-Host "File excluded; skipping file: $($file.name) (File $($scannedFiles)/$($files.Count))" -ForegroundColor Yellow
                continue
            }
        }
        if (Check-QuitEvent) { 
            write-host "Exiting..."
            exit(0)
        }
        # Get remote file details
        $remoteFileDetails = Get-RemoteFileDetails $ftpFileUri
        if (-not $remoteFileDetails -or $file.Length -ne $remoteFileDetails.Size -or $file.LastWriteTime -gt $remoteFileDetails.LastModified -or $file.Extension -eq ".html" -or $filesToObfuscate -contains $file.Name) {
            Write-Host "Changes detected - uploading file: $($file.Name)"
            $uploadFilePath = $file.FullName
            if (Check-QuitEvent) { 
                write-host "Exiting..."
                exit(0)
            }
             if ($file.Extension -eq ".js") {              
                if($filesToObfuscate -contains $file.Name){

                    # Create a temporary obfuscated copy for JavaScript files
                    $tempFilePath = Join-Path -Path $env:TEMP -ChildPath $file.Name
                    & "javascript-obfuscator" $file.FullName --output $tempFilePath

                    if ($LASTEXITCODE -eq 0) {
                        # Write-Host "Successfully obfuscated $($file.Name) for upload."
                        $uploadFilePath = $tempFilePath
                    } else {
                        Write-Host "Failed to obfuscate $($file.Name). Skipping upload. (File $($scannedFiles)/$($files.Count))" -ForegroundColor Red
                        continue
                    }
                }
            } elseif ($file.Extension -eq ".html") {
                # Update cache version in HTML files
                # Write-Host "Updating cache version in HTML file: $($file.Name)"
                $uploadFilePath = Update-CacheVersion $file.FullName
            }
            if (Check-QuitEvent) { 
                write-host "Exiting..."
                exit(0)
            }
            try {
                $result = & "C:\Windows\System32\curl.exe" -T $uploadFilePath --ftp-create-dirs -u "${ftpUsername}:${ftpPassword}" $ftpFileUri
                if ($LASTEXITCODE -eq 0) {
                    
                    $uploadedFiles++
                    Write-Host "Successfully uploaded $($file.Name) (File $($scannedFiles)/$($files.Count))" -ForegroundColor Green
                } else {
                    Write-Host "Failed to upload $($file.Name). Curl exit code: $LASTEXITCODE" -ForegroundColor Red
                }
            } catch {
                Write-Host "Error uploading $($file.Name): $_" -ForegroundColor Red
            }
        } else {
            Write-Host "No changes detected; skipping file: $($file.Name) (File $($scannedFiles)/$($files.Count))" -ForegroundColor Green
        }
        if (Check-QuitEvent) { 
            write-host "Exiting..."
            exit(0)
        }
    }
    Write-Host "Upload process completed for server: $($ftpHost). Total files uploaded: $($uploadedFiles)" -ForegroundColor Green
}

if($numOfDirExist -gt 0){
Show-Notification 
[Console]::Beep(1000,500)
$userInput = $null
if (-not [string]::IsNullOrEmpty($config.url)) {
    Write-Host "Upload process completed to $($config.url) press O to open it in browser" -ForegroundColor Green
    
    $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
    

    while ($stopWatch.Elapsed.TotalSeconds -lt 10 -and -not $userInput) {
        if ([console]::KeyAvailable) {
            $userInput = [console]::ReadKey($true).KeyChar
            $stopWatch.Stop()
        }
        Start-Sleep -Milliseconds 100
    }
    
    if ($userInput -eq "o" -or $userInput -eq "O") {
        Start-Process $config.url
    } 
}
if(-not $userInput){
    Write-Host "Upload process completed for all servers" -ForegroundColor Green
}
if(-not [string]::IsNullOrEmpty($config.success_message)){
    Write-host $config.success_message -ForegroundColor Green
}

# Execute scripts after uploading
if ($config.trigger.after_upload) {
    Write-Host "Executing 'after upload' scripts..." -ForegroundColor Yellow
    foreach ($scriptUrl in $config.trigger.after_upload) {
        Invoke-ExternalScript -url $scriptUrl
    }
}
}

