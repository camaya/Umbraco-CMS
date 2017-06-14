
# Umbraco.Build.psm1
#
# $env:PSModulePath = "$pwd\build\Modules\;$env:PSModulePath"
# Import-Module Umbraco.Build -Force -DisableNameChecking
#
# PowerShell Modules:
# https://msdn.microsoft.com/en-us/library/dd878324%28v=vs.85%29.aspx?f=255&MSPPError=-2147217396
#
# PowerShell Module Manifest:
# https://msdn.microsoft.com/en-us/library/dd878337%28v=vs.85%29.aspx?f=255&MSPPError=-2147217396
#
# See also
# http://www.powershellmagazine.com/2014/08/15/pstip-taking-control-of-verbose-and-debug-output-part-5/


. "$PSScriptRoot\Utilities.ps1"
. "$PSScriptRoot\Get-VisualStudio.ps1"

. "$PSScriptRoot\Get-UmbracoBuildEnv.ps1"
. "$PSScriptRoot\Set-UmbracoVersion.ps1"
. "$PSScriptRoot\Get-UmbracoVersion.ps1"

#
# Prepare-Build
# Prepares the build
#
function Prepare-Build
{
  param (
    $uenv # an Umbraco build environment (see Get-UmbracoBuildEnv)
  )

  Write-Host ">> Prepare-Build"
  
  $src = "$($uenv.SolutionRoot)\src"
  $tmp = "$($uenv.SolutionRoot)\build.tmp"
  $out = "$($uenv.SolutionRoot)\build.out"

  # clear
  Write-Host "Clear folders and files"

  Remove-Directory "$src\Umbraco.Web.UI.Client\build"
  Remove-Directory "$src\Umbraco.Web.UI.Client\bower_components"

  Remove-Directory "$tmp"
  mkdir "$tmp" > $null
  
  Remove-Directory "$out"
  mkdir "$out" > $null

  # prepare web.config
  $webUi = "$src\Umbraco.Web.UI"
  if (test-path "$webUi\web.config")
  {
    if (test-path "$webUi\web.config.temp-build")
    {
      Write-Host "Found existing web.config.temp-build"
      $i = 0
      while (test-path "$webUi\web.config.temp-build.$i")
      {
        $i = $i + 1
      }
      Write-Host "Save existing web.config as web.config.temp-build.$i"
      Write-Host "(WARN: the original web.config.temp-build will be restored during post-build)"
      mv "$webUi\web.config" "$webUi\web.config.temp-build.$i"
    }
    else
    {
      Write-Host "Save existing web.config as web.config.temp-build"
      Write-Host "(will be restored during post-build)"
      mv "$webUi\web.config" "$webUi\web.config.temp-build"
    }
  }
  Write-Host "Create clean web.config"
  Copy-File "$webUi\web.Template.config" "$webUi\web.config"
}

#
# Compile-Belle
# Builds the Belle UI project
#
function Compile-Belle
{
  param (
    $uenv, # an Umbraco build environment (see Get-UmbracoBuildEnv)
    $version # an Umbraco version object (see Get-UmbracoVersion)
  )

  $tmp = "$($uenv.SolutionRoot)\build.tmp"
  $src = "$($uenv.SolutionRoot)\src"
  
  Write-Host ">> Build Belle"
  Write-Host "Logging to $tmp\belle.log"

  push-location "$($uenv.SolutionRoot)\src\Umbraco.Web.UI.Client"
  $p = $env:path
  $env:path = $uenv.NpmPath + ";" + $uenv.NodePath + ";" + $env:path
  
  write "cache clean" > $tmp\belle.log
  &npm cache clean --quiet >> $tmp\belle.log 2>&1
  &npm install --quiet >> $tmp\belle.log 2>&1
  &npm install -g grunt-cli --quiet >> $tmp\belle.log 2>&1
  &npm install -g bower --quiet >> $tmp\belle.log 2>&1
  &grunt build --buildversion=$version.Release >> $tmp\belle.log 2>&1
  
  # fixme - should we filter the log to find errors?
  #get-content .\build.tmp\belle.log | %{ if ($_ -match "build") { write $_}}
  
  pop-location
  $env:path = $p

  
  # setting node_modules folder to hidden
  # used to prevent VS13 from crashing on it while loading the websites project
  # also makes sure aspnet compiler does not try to handle rogue files and chokes
  # in VSO with Microsoft.VisualC.CppCodeProvider -related errors
  # use get-item -force 'cos it might be hidden already
  write "Set hidden attribute on node_modules"
  $dir = get-item -force "$src\Umbraco.Web.UI.Client\node_modules"
  $dir.Attributes = $dir.Attributes -bor ([System.IO.FileAttributes]::Hidden)
}

#
# Compile-Umbraco
# Compiles Umbraco
#
function Compile-Umbraco
{
  param (
    $uenv # an Umbraco build environment (see Get-UmbracoBuildEnv)
  )

  $src = "$($uenv.SolutionRoot)\src"
  $tmp = "$($uenv.SolutionRoot)\build.tmp"
  $out = "$($uenv.SolutionRoot)\build.out"

  $buildConfiguration = "Release"
  
  if ($uenv.VisualStudio -eq $null)
  {
    Write-Error "Build environment does not provide VisualStudio."
    break
  }
  
  $toolsVersion = "4.0"
  if ($uenv.VisualStudio.Major -eq 15)
  {
    $toolsVersion = "15.0"
  }
    
  Write-Host ">> Compile Umbraco"
  Write-Host "Logging to $tmp\msbuild.umbraco.log"

  # beware of the weird double \\ at the end of paths
  # see http://edgylogic.com/blog/powershell-and-external-commands-done-right/
  &$uenv.VisualStudio.MsBuild "$src\Umbraco.Web.UI\Umbraco.Web.UI.csproj" `
    /p:WarningLevel=0 `
    /p:Configuration=$buildConfiguration `
    /p:UseWPP_CopyWebApplication=True `
    /p:PipelineDependsOnBuild=False `
    /p:OutDir=$tmp\bin\\ `
    /p:WebProjectOutputDir=$tmp\WebApp\\ `
    /p:Verbosity=minimal `
    /t:Clean`;Rebuild `
    /tv:$toolsVersion `
    /p:UmbracoBuild=True `
    > $tmp\msbuild.umbraco.log
    
  # /p:UmbracoBuild tells the csproj that we are building from PS
}

#
# Prepare-Tests
# Prepare Tests
#
function Prepare-Tests
{
  param (
    $uenv # an Umbraco build environment (see Get-UmbracoBuildEnv)
  )
  
  $src = "$($uenv.SolutionRoot)\src"
  $tmp = "$($uenv.SolutionRoot)\build.tmp"
  
  Write-Host ">> Prepare-Tests"

  # fixme - idea is to avoid rebuilding everything for tests
  # but because of our weird assembly versioning (with .* stuff)
  # everything gets rebuilt all the time...
  #Copy-Files "$tmp\bin" "." "$tmp\tests"
  
  # data
  Write-Host "Copy data files"
  mkdir "$tmp\tests\Packaging" > $null
  Copy-Files "$src\Umbraco.Tests\Packaging\Packages" "*" "$tmp\tests\Packaging\Packages"
}

#
# Compile-Tests
# Compiles Tests
#
function Compile-Tests
{
  param (
    $uenv # an Umbraco build environment (see Get-UmbracoBuildEnv)
  )

  $src = "$($uenv.SolutionRoot)\src"
  $tmp = "$($uenv.SolutionRoot)\build.tmp"
  $out = "$tmp\tests"

  $buildConfiguration = "Release"
  
  if ($uenv.VisualStudio -eq $null)
  {
    Write-Error "Build environment does not provide VisualStudio."
    break
  }
  
  $toolsVersion = "4.0"
  if ($uenv.VisualStudio.Major -eq 15)
  {
    $toolsVersion = "15.0"
  }
    
  Write-Host ">> Compile Tests (logging to $tmp\msbuild.tests.log)"

  # beware of the weird double \\ at the end of paths
  # see http://edgylogic.com/blog/powershell-and-external-commands-done-right/
  &$uenv.VisualStudio.MsBuild "$src\Umbraco.Tests\Umbraco.Tests.csproj" `
    /p:WarningLevel=0 `
    /p:Configuration=$buildConfiguration `
    /p:UseWPP_CopyWebApplication=True `
    /p:PipelineDependsOnBuild=False `
    /p:OutDir=$out\\ `
    /p:Verbosity=minimal `
    /t:Build `
    /tv:$toolsVersion `
    /p:UmbracoBuild=True `
    > $tmp\msbuild.tests.log
    
  # /p:UmbracoBuild tells the csproj that we are building from PS
}

#
# Build-Post
# Cleans things up and prepare files after compilation
#
function Build-Post
{
  param (
    $uenv # an Umbraco build environment (see Get-UmbracoBuildEnv)
  )

  Write-Host "Post-Compile" 
  
  $src = "$($uenv.SolutionRoot)\src"
  $tmp = "$($uenv.SolutionRoot)\build.tmp"
  $out = "$($uenv.SolutionRoot)\build.out"

  $buildConfiguration = "Release"

  # restore web.config
  $webUi = "$src\Umbraco.Web.UI"
  if (test-path "$webUi\web.config.temp-build")
  {
    Write-Host "Restoring existing web.config"
    Remove-File "$webUi\web.config"
    mv "$webUi\web.config.temp-build" "$webUi\web.config"
  }

  # cleanup build
  write "Clean build"

  Remove-File "$tmp\bin\*.dll.config"
  Remove-File "$tmp\WebApp\bin\*.dll.config"

  # cleanup presentation
  write "Cleanup presentation"

  Remove-Directory "$tmp\WebApp\umbraco.presentation"

  # create directories
  write "Create directories"

  mkdir "$tmp\Configs" > $null
  mkdir "$tmp\Configs\Lang" > $null
  mkdir "$tmp\WebApp\App_Data" > $null
  #mkdir "$tmp\WebApp\Media" > $null
  #mkdir "$tmp\WebApp\Views" > $null

  # copy various files
  write "Copy xml documentation"

  cp -force "$tmp\bin\*.xml" "$tmp\WebApp\bin"

  write "Copy transformed configs and langs"

  Copy-Files "$tmp\WebApp\config" "*.config" "$tmp\Configs"
  Copy-Files "$tmp\WebApp\config" "*.js" "$tmp\Configs"
  Copy-Files "$tmp\WebApp\config\lang" "*.xml" "$tmp\Configs\Lang"
  Copy-File "$tmp\WebApp\web.config" "$tmp\Configs\web.config.transform"

  write "Copy transformed web.config"

  Copy-File "$src\Umbraco.Web.UI\web.$buildConfiguration.Config.transformed" "$tmp\WebApp\web.config"

  # offset the modified timestamps on all umbraco dlls, as WebResources
  # break if date is in the future, which, due to timezone offsets can happen.
  write "Offset dlls timestamps"
  ls -r "$tmp\*.dll" | foreach {
    $_.CreationTime = $_.CreationTime.AddHours(-11)
    $_.LastWriteTime = $_.LastWriteTime.AddHours(-11)
  }

  # copy libs
  write "Copy SqlCE libraries"

  Copy-Files "$src\packages\SqlServerCE.4.0.0.1" "*.*" "$tmp\bin" `
    { -not $_.Extension.StartsWith(".nu") -and -not $_.RelativeName.StartsWith("lib\") }
  Copy-Files "$src\packages\SqlServerCE.4.0.0.1" "*.*" "$tmp\WebApp\bin" `
    { -not $_.Extension.StartsWith(".nu") -and -not $_.RelativeName.StartsWith("lib\") }
          
  # copy Belle
  write "Copy Belle"

  Copy-Files "$src\Umbraco.Web.UI.Client\build\belle" "*" "$tmp\WebApp\umbraco" `
    { -not ($_.RelativeName -eq "index.html") }

  # zip webapp
  write "Zip WebApp"

  &$uenv.Zip a -r "$out\UmbracoCms.AllBinaries.$($version.Semver).zip" `
    "$tmp\bin\*" `
    -x!dotless.Core.dll `
    > $null
    
  &$uenv.Zip a -r "$out\UmbracoCms.$($version.Semver).zip" `
    "$tmp\WebApp\*" `
    -x!dotless.Core.dll -x!Content_Types.xml `
    > $null

  # prepare and zip WebPI
  write "Zip WebPI"

  Remove-Directory "$tmp\WebPi"
  mkdir "$tmp\WebPi" > $null
  mkdir "$tmp\WebPi\umbraco" > $null

  Copy-Files "$tmp\WebApp" "*" "$tmp\WebPi\umbraco"
  Copy-Files "$src\WebPi" "*" "$tmp\WebPi"
      
  &$uenv.Zip a -r "$out\UmbracoCms.WebPI.$($version.Semver).zip" `
    "$tmp\WebPi\*" `
    -x!dotless.Core.dll `
    > $null
    
  # clear
  # fixme - NuGet needs $tmp ?!
  #write "Delete build folder"
  #Remove-Directory "$tmp"

  # hash the webpi file
  write "Hash the WebPI file"

  $hash = Get-FileHash "$out\UmbracoCms.WebPI.$($version.Semver).zip"
  write $hash | out-file "$out\webpihash.txt" -encoding ascii

  # add Web.config transform files to the NuGet package
  write "Add web.config transforms to NuGet package"

  mv "$tmp\WebApp\Views\Web.config" "$tmp\WebApp\Views\Web.config.transform"
  
  # fixme - that one does not exist in .bat build either?
  #mv "$tmp\WebApp\Xslt\Web.config" "$tmp\WebApp\Xslt\Web.config.transform"
}

#
# Package-NuGet
# Creates the NuGet packages
#
function Package-NuGet
{
  param (
    $uenv, # an Umbraco build environment (see Get-UmbracoBuildEnv)
    $version # an Umbraco version object (see Get-UmbracoVersion)
  )
  
  $src = "$($uenv.SolutionRoot)\src"
  $tmp = "$($uenv.SolutionRoot)\build.tmp"
  $out = "$($uenv.SolutionRoot)\build.out"
  $nuspecs = "$($uenv.SolutionRoot)\build\NuSpecs"
  
  Write-Host "Create NuGet packages"

  # see https://docs.microsoft.com/en-us/nuget/schema/nuspec
  # note - warnings about SqlCE native libs being outside of 'lib' folder,
  # nothing much we can do about it as it's intentional yet there does not
  # seem to be a way to disable the warning
  
  &$uenv.NuGet Pack "$nuspecs\UmbracoCms.Core.nuspec" `
    -Properties BuildTmp="$tmp" `
    -Version $version.Semver.ToString() `
    -Symbols -Verbosity quiet -outputDirectory $out

  &$uenv.NuGet Pack "$nuspecs\UmbracoCms.nuspec" `
    -Properties BuildTmp="$tmp" `
    -Version $version.Semver.ToString() `
    -Verbosity quiet -outputDirectory $out
}

#
# Build-Umbraco
# Builds Umbraco
#
#   -Target all|pre|post|belle
#   (default: all)
#
function Build-Umbraco
{
  [CmdletBinding()]
  param (
    [string]
    $target = "all"
  )
  
  $target = $target.ToLowerInvariant()
  Write-Host ">> Build-Umbraco <$target>"

  Write-Host "Get Build Environment"
  $uenv = Get-UmbracoBuildEnv
  
  Write-Host "Get Version"
  $version = Get-UmbracoVersion
  Write-Host "Version $($version.Semver)"

  if ($target -eq "pre-build")
  {
    Prepare-Build $uenv
    Compile-Belle $uenv $version

    # set environment variables
    $env:UMBRACO_VERSION=$version.Semver.ToString()
    $env:UMBRACO_RELEASE=$version.Release
    $env:UMBRACO_COMMENT=$version.Comment
    $env:UMBRACO_BUILD=$version.Build

    # set environment variable for VSO
    # https://github.com/Microsoft/vsts-tasks/issues/375
    # https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md
    Write-Host ("##vso[task.setvariable variable=UMBRACO_VERSION;]$($version.Semver.ToString())")
    Write-Host ("##vso[task.setvariable variable=UMBRACO_RELEASE;]$($version.Release)")
    Write-Host ("##vso[task.setvariable variable=UMBRACO_COMMENT;]$($version.Comment)")
    Write-Host ("##vso[task.setvariable variable=UMBRACO_BUILD;]$($version.Build)")
    
    Write-Host ("##vso[task.setvariable variable=UMBRACO_TMP;]$($uenv.SolutionRoot)\build.tmp")
  }
  elseif ($target -eq "pre-tests")
  {
    Prepare-Tests $uenv
  }
  elseif ($target -eq "compile-tests")
  {
    Compile-Tests $uenv
  }
  elseif ($target -eq "compile-umbraco")
  {
    Compile-Umbraco $uenv
  }
  elseif ($target -eq "post")
  {
    Build-Post $uenv
  }
  elseif ($target -eq "compile-belle")
  {
    Compile-Belle $uenv $version
  }
  elseif ($target -eq "all")
  {
    Prepare-Build $uenv
    Compile-Belle $uenv $version
    Compile-Umbraco $uenv
    Prepare-Tests $uenv
    Compile-Tests $uenv
    # not running tests...
    Build-Post $uenv
    Package-NuGet $uenv $version
  }
  else
  {
    Write-Error "Unsupported target `"$target`"."
  }
}

#
# export functions
#
Export-ModuleMember -function Get-UmbracoBuildEnv
Export-ModuleMember -function Set-UmbracoVersion
Export-ModuleMember -function Get-UmbracoVersion
Export-ModuleMember -function Build-Umbraco

#eof