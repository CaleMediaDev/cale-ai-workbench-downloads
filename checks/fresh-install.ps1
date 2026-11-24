param([Parameter(Mandatory)][ValidatePattern('^rust-v[0-9]+\.[0-9]+\.[0-9]+$')][string]$Tag)
$ErrorActionPreference='Stop'
$version=$Tag.Substring(6)
$base=Join-Path $env:LOCALAPPDATA 'Programs/Cale Workbench Preview'
$exe=Join-Path $base 'cale-workbench-next.exe'
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
}
'@
$timer=[Diagnostics.Stopwatch]::StartNew()
$setup=Start-Process -PassThru -FilePath $package -ArgumentList '/P'
$seen=$false
while(!$setup.HasExited -and $timer.Elapsed.TotalMinutes -lt 7){
    $setup.Refresh()
    if($setup.MainWindowHandle){$panel=[InstallerWindow]::FindWindowEx($setup.MainWindowHandle,[IntPtr]::Zero,'CaleProjectionProgress',$null); if($panel -and [InstallerWindow]::IsWindowVisible($panel)){$seen=$true}}
    Start-Sleep -Milliseconds 150
}
if(!$setup.HasExited -or $setup.ExitCode -ne 0){throw 'Setup failed or timed out'}
$timer.Stop()
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
$app=Start-Process -FilePath $exe -PassThru
try{
    $deadline=(Get-Date).AddSeconds(70)
    do{$app.Refresh();if($app.HasExited){throw 'Workbench exited before first launch'}
        $view=Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe' AND ParentProcessId=$($app.Id)"
        if($app.MainWindowHandle -and $view){break};Start-Sleep -Seconds 1
    }while((Get-Date) -lt $deadline)
    if(!$app.MainWindowHandle -or !$view){throw 'The application window and WebView2 did not start'}
    $shortcuts=@(Get-ChildItem ([Environment]::GetFolderPath('DesktopDirectory')),([Environment]::GetFolderPath('Programs')) -Filter '*Cale*lnk' -Recurse -File)
    if(!$shortcuts.Count){throw 'Workbench shortcut missing'}
    if([version]$version -ge [version]'0.24.76' -and !$seen){throw 'Projection Room did not appear'}
    if([version]$version -ge [version]'0.24.76' -and (Test-Path "$env:PLAYWRIGHT_BROWSERS_PATH/chromium_headless_shell-1252")){throw 'Redundant browser shipped'}
    $bytes=(Get-ChildItem $base -Recurse -File|Measure-Object Length -Sum).Sum
    $receipt="Windows $([Environment]::OSVersion.Version), Workbench $version, setup $($timer.Elapsed.TotalSeconds.ToString('0.0')) seconds, download $($asset[0].size) bytes, installed $bytes bytes, projection visible $seen, first launch and offline bundled Chromium passed."
    $receipt
    if($env:GITHUB_STEP_SUMMARY){Add-Content $env:GITHUB_STEP_SUMMARY $receipt}
}finally{if(!$app.HasExited){[void]$app.CloseMainWindow()}}
