param([Parameter(Mandatory)][ValidatePattern('^rust-v[0-9]+\.[0-9]+\.[0-9]+$')][string]$Tag,[switch]$Interactive)
$ErrorActionPreference='Stop'
$version=$Tag.Substring(6)
$base=Join-Path $env:LOCALAPPDATA 'Cale Workbench Preview'
$key='HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/Cale Workbench Preview'
if((Test-Path $base) -or (Test-Path $key) -or (Test-Path "$env:APPDATA/com.calemedia.workbench.next")){throw 'A fresh profile is required'}
$release=Invoke-RestMethod "https://api.github.com/repos/CaleMediaDev/cale-ai-workbench-downloads/releases/tags/$Tag"
$asset=@($release.assets|Where-Object name -eq 'Cale-AI-Workbench-light-Setup.exe')
if($asset.Count -ne 1 -or $asset[0].digest -notmatch '^sha256:[0-9a-f]{64}$'){throw 'Expected one verified installer'}
$package=Join-Path $env:RUNNER_TEMP 'CaleSetup.exe'
Invoke-WebRequest $asset[0].browser_download_url -OutFile $package
if("sha256:$((Get-FileHash $package).Hash.ToLowerInvariant())" -cne $asset[0].digest){throw 'Release payload differs'}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class InstallerWindow {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string title);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam);
}
'@
$timer=[Diagnostics.Stopwatch]::StartNew()
$themed=[version]$version -ge [version]'0.24.76'
$manual=$themed -and $Interactive
$setup=if($manual){Start-Process -PassThru -FilePath $package}else{Start-Process -PassThru -FilePath $package -ArgumentList '/P'}
$seen=$false
$clickedInstall=$false
$clickedFinish=$false
while(!$setup.HasExited -and $timer.Elapsed.TotalMinutes -lt 7){
    $setup.Refresh()
    if($setup.MainWindowHandle -ne [IntPtr]::Zero){
        $panel=[InstallerWindow]::FindWindowEx($setup.MainWindowHandle,[IntPtr]::Zero,'CaleProjectionProgress','C.A.L.E. installation progress')
        if($panel -ne [IntPtr]::Zero -and [InstallerWindow]::IsWindowVisible($panel)){
            $details=[InstallerWindow]::FindWindowEx($panel,[IntPtr]::Zero,'Button','Show details')
            if($details -ne [IntPtr]::Zero -and [InstallerWindow]::IsWindowVisible($details)){$seen=$true}
            if($manual){
                $caption=if(!$clickedInstall){'Install Workbench'}else{'Finish'}
                $action=[InstallerWindow]::FindWindowEx($panel,[IntPtr]::Zero,'Button',$caption)
                if(!$clickedFinish -and $action -ne [IntPtr]::Zero -and [InstallerWindow]::IsWindowVisible($action)){
                    if(![InstallerWindow]::PostMessage($action,245,[IntPtr]::Zero,[IntPtr]::Zero)){throw "Could not click $caption"}
                    if($clickedInstall){$clickedFinish=$true}else{$clickedInstall=$true}
                }
            }
        }
    }
    Start-Sleep -Milliseconds 150
}
if(!$setup.HasExited -or $setup.ExitCode -ne 0){throw 'Setup failed or timed out'}
if($manual -and (!$clickedInstall -or !$clickedFinish)){throw 'Interactive installation did not complete all three pages'}
$timer.Stop()
$base=(Get-ItemPropertyValue -Path $key -Name InstallLocation).Trim('"')
$exe=Join-Path $base 'cale-workbench-next.exe'
if((Get-Item $exe).VersionInfo.ProductVersion -ne $version -or !(Test-Path $key)){throw 'Missing installed version or registration'}
$node=Join-Path $base 'runtime/node.exe'
$env:PLAYWRIGHT_BROWSERS_PATH=Join-Path $base 'runtime/browsers'
$playwright=Join-Path $base 'runtime/node_modules/playwright'
$env:CHECK_PLAYWRIGHT=$playwright
$source=@'
const {chromium}=require(process.env.CHECK_PLAYWRIGHT);
(async()=>{const b=await chromium.launch({channel:'chromium',headless:true,chromiumSandbox:true});try{const page=await b.newPage();await page.setContent('<title>Local project</title>');if(await page.title()!=='Local project')throw Error('Bundled browser could not render');}finally{await b.close()}})().catch(e=>{console.error(e);process.exitCode=1});
'@
& $node -e $source
if($LASTEXITCODE){throw 'Installed browser failed'}
$app=Get-Process -Name 'cale-workbench-next' -ErrorAction SilentlyContinue |Where-Object Path -eq $exe |Select-Object -First 1
if(!$app){$app=Start-Process -FilePath $exe -PassThru}
try{
    $deadline=(Get-Date).AddSeconds(70)
    do{$app.Refresh();if($app.HasExited){throw 'Workbench exited before first launch'}
        $view=Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe' AND ParentProcessId=$($app.Id)"
        if($app.MainWindowHandle -ne [IntPtr]::Zero -and $view){break};Start-Sleep -Seconds 1
    }while((Get-Date) -lt $deadline)
    if($app.MainWindowHandle -eq [IntPtr]::Zero -or !$view){throw 'The application window and WebView2 did not start'}
    $shortcuts=@(Get-ChildItem ([Environment]::GetFolderPath('DesktopDirectory')),([Environment]::GetFolderPath('Programs')) -Filter '*Cale*lnk' -Recurse -File)
    if(!$shortcuts.Count){throw 'Workbench shortcut missing'}
    if([version]$version -ge [version]'0.24.76' -and !$seen){throw 'Projection Room did not appear'}
    if([version]$version -ge [version]'0.24.76' -and (Test-Path "$env:PLAYWRIGHT_BROWSERS_PATH/chromium_headless_shell-1252")){throw 'Redundant browser shipped'}
    $bytes=(Get-ChildItem $base -Recurse -File|Measure-Object Length -Sum).Sum
    $receipt="Windows $([Environment]::OSVersion.Version), Workbench $version, setup $($timer.Elapsed.TotalSeconds.ToString('0.0')) seconds, download $($asset[0].size) bytes, installed $bytes bytes, projection visible $seen, interactive welcome and finish $clickedFinish, first launch and offline bundled Chromium passed."
    $receipt
    if($env:GITHUB_STEP_SUMMARY){Add-Content $env:GITHUB_STEP_SUMMARY $receipt}
}finally{if(!$app.HasExited){[void]$app.CloseMainWindow()}}
