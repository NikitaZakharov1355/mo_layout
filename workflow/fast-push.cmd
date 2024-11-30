@echo off
set commitMessage=Fast commit

:: Check if an argument is passed
if NOT "%~1"=="" set commitMessage=%~1

:: Run the Git commands
git add .
git commit -m "%commitMessage%"
git push origin main

