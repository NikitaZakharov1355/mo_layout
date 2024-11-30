# Workflows

## Deploy to Servers
Use *deploy.cmd* terminal command to upload files to the server using FTP, with basic configuration JSON file.

### Deploy Command 
In order to upload files to the FTP, open IDE terminal or PowerShell from project's root, and execute the command:
```
./workflow/deploy.cmd {environment}
```
With the wanted environment name (default enviroment is *test*):<br />
```
./workflow/deploy.cmd prod
```
*OR*<br />
```
./workflow/deploy.cmd qa
```
*OR*<br />
```
./workflow/deploy.cmd test
```

For example, executing this command, would upload the files to 'QA' server FTP according to the settings in file *workflow/settings_qa.json*:
```
./workflow/deploy.cmd qa
```

### Settings JSON 

Inside 'workflow' folder we can write settings JSON files, one for each environment.<br />
The name of the file starts with "settings_" and ends with environment name. For example, for QA environment we will write a settings file called *settings_qa.json*.<br />
This is the JSON file structue:

- **url** - The URL to open after successfully executing the script.
- **success_message** - A message that will display on the terminal after successfully executing the script.
- **ftp** - Array of FTP servers to upload the files to, each array object is consist of these parameters:
   - **host** - The IP address of the server.
   - **username** - FTP user name.
   - **password** - FTP password, encrypted with base64 .
   - **remote_dir** - The directory that the files will upload to.
- **upload**:
   - **local_dir** - The local directory (relative from root) of the files that will be uploaded.
   - **include** - List of files and directories, inside the global directory (as set in *upload>dir*), to upload.
   - **exclude** - List of files and directories, inside the global directory (as set in *upload>dir*), to ignore and not upload. (If both the 'include' and 'exclude' lists were provided, only the 'include' list will be considered).
- **trigger**:
    - **before_upload** - List of scripts URLs we want to execute before the upload proccess.
    - **after_upload** - List of scripts URLs we want to execute after the upload proccess.
### Example Settings JSON

The following example is JSON for 'Test2' enviroment.<br />
The file name would be *settings_test2.json*, located inside *workflow* folder.<br />
This would be the command to upload to 'Test2' enviroment:
```
./workflow/deploy.cmd test2
```
And this would be the content of the *workflow/settings_test2.json* file:<br />
```
{
    "url": "https://example.com/test2/v1/",
    "ftp": [{
        "host": "20.116.22.112",
        "username": "ftp_user",
        "password": "bXlfcGFzc3dvcmQ=",
        "remote_dir": "/public_html/test2/v1"
    }],
    "upload": {
        "dir": "app",
        "include": ["assets_dir/", "file.html", "file.js", "file.css"],
        "exclude": ["excluded_dir/", "excluded_file.txt"]
    },
    "trigger": {
        "before_upload": ["https://example.com/script_1/", "https://example.com/script_2/"],
        "after_upload": ["https://example.com/script_3/"]
    }
}
```

### Assets Cache Versioning

In order to add cache versioning to our assets on our HTML files, we can use the variable *{cache_version}*, and it would be replaced with a random version number  when the HTML file is uploaded to the server.<br />
For example:
```
<link rel="stylesheet" href="./styles.css?{cache_version}" />
<script src="./main.js?{cache_version}"></script>
```

### JavaScript Obfuscator

In order to obfuscate JavaScript files when uploaded to the FTP, we can use *data-compile* attribute in HTML files. This is done by adding the attribute *data-compile="true"* to the script tag of each Javascript file we wish to obfuscate.<br />
For example:<br />
```
<script data-compile="true" src="./main.js?{cache_version}"></script>
```
<br /><br />
## Fast Push

In order to make git commands of "add" + "commit" + "push" (to main branch) in one single command - you can use the command:
```
./workflow/fast-push.cmd "{commit message}"
```
You don't have to specifiy a commit message, you can simpley use:
```
./workflow/fast-push.cmd
```
