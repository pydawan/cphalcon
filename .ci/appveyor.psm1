#
# This file is part of the Phalcon Framework.
#
# (c) Phalcon Team <team@phalconphp.com>
#
# For the full copyright and license information, please view the LICENSE.txt
# file that was distributed with this source code.
#

Set-Variable `
	-name PHP_SDK_URI `
	-value "https://github.com/Microsoft/php-sdk-binary-tools" `
	-Scope Global `
	-Option ReadOnly `
	-Force

Set-Variable `
	-name PHP_URI `
	-value "http://windows.php.net/downloads/releases" `
	-Scope Global `
	-Option ReadOnly `
	-Force

Set-Variable `
	-name PECL_URI `
	-value "https://windows.php.net/downloads/pecl/releases" `
	-Scope Global `
	-Option ReadOnly `
	-Force

function SetupPrerequisites {
	Ensure7ZipIsInstalled

	EnsureRequiredDirectoriesPresent `
		-Directories C:\Downloads,C:\Downloads\Choco,C:\Projects
}

function Ensure7ZipIsInstalled  {
	if (-not (Get-Command "7z" -ErrorAction SilentlyContinue)) {
		$7zipInstallationDirectory = "${Env:ProgramFiles}\7-Zip"

		if (-not (Test-Path "${7zipInstallationDirectory}")) {
			throw "The 7-zip file archiver is needed to use this module"
		}

		$Env:Path += ";$7zipInstallationDirectory"
	}
}

function EnsureRequiredDirectoriesPresent {
	param (
		[Parameter(Mandatory=$true)] [String[]] $Directories
	)

	foreach ($Dir in $Directories) {
		if (-not (Test-Path $Dir)) {
			New-Item -ItemType Directory -Force -Path ${Dir} | Out-Null
		}
	}
}

function InstallPhpSdk {
	param (
		[Parameter(Mandatory=$false)] [System.String] $InstallPath = "C:\Projects\php-sdk"
	)

	Write-Host "Install PHP SDK binary tools: ${Env:PHP_SDK_VERSION}"

	$FileName  = "php-sdk-${Env:PHP_SDK_VERSION}"
	$RemoteUrl = "${PHP_SDK_URI}/archive/${FileName}.zip"
	$Archive   = "C:\Downloads\${FileName}.zip"

	if (-not (Test-Path $InstallPath)) {
		if (-not [System.IO.File]::Exists($Archive)) {
			DownloadFile $RemoteUrl $Archive
		}

		$UnzipPath = "${Env:Temp}\php-sdk-binary-tools-${FileName}"
		If (-not (Test-Path "${UnzipPath}")) {
			Write-Host "Unpack to ${UnzipPath}"
			Expand-Item7zip $Archive $Env:Temp
		}

		Move-Item -Path $UnzipPath -Destination $InstallPath
	}
}

function DownloadFile {
	param (
		[Parameter(Mandatory=$true)] [System.String] $RemoteUrl,
		[Parameter(Mandatory=$true)] [System.String] $Destination
	)

	$RetryMax   = 5
	$RetryCount = 0
	$Completed  = $false

	$WebClient = New-Object System.Net.WebClient
	$WebClient.Headers.Add('User-Agent', 'AppVeyor PowerShell Script')

	Write-Host "Downloading: ${RemoteUrl} => ${Destination} ..."

	while (-not $Completed) {
		try {
			$WebClient.DownloadFile($RemoteUrl, $Destination)
			$Completed = $true
		} catch  {
			if ($RetryCount -ge $RetryMax) {
				$ErrorMessage = $_.Exception.Message
				Write-Error -Message "${ErrorMessage}"
				$Completed = $true
			} else {
				$RetryCount++
			}
		}
	}
}

function Expand-Item7zip {
	param(
		[Parameter(Mandatory=$true)] [System.String] $Archive,
		[Parameter(Mandatory=$true)] [System.String] $Destination
	)

	if (-not (Test-Path -Path $Archive -PathType Leaf)) {
		throw "Specified archive file does not exist: ${Archive}"
	}

	if (-not (Test-Path -Path $Destination -PathType Container)) {
		New-Item $Destination -ItemType Directory | Out-Null
	}

	$Result   = (& 7z x "$Archive" "-o$Destination" -aoa -bd -y -r)
	$ExitCode = $LASTEXITCODE

	If ($ExitCode -ne 0) {
		throw "An error occurred while unzipping '${Archive}' to '${Destination}'"
	}
}

function InstallPhp {
	param (
		[Parameter(Mandatory=$true)]  [System.String] $Version,
		[Parameter(Mandatory=$true)]  [System.String] $BuildType,
		[Parameter(Mandatory=$true)]  [System.String] $VC,
		[Parameter(Mandatory=$true)]  [System.String] $Platform,
		[Parameter(Mandatory=$false)] [System.String] $InstallPath = "C:\Projects\php"
	)

	$Version = SetupPhpVersionString $Version
	Write-Host "Install PHP: ${Version}"

	$RemoteUrl = "${PHP_URI}/php-${Version}-${BuildType}-vc${VC}-${Platform}.zip"
	$Archive   = "C:\Downloads\php-${Version}-${BuildType}-VC${VC}-${Platform}.zip"

	if (-not (Test-Path $InstallPath)) {
		if (-not [System.IO.File]::Exists($Archive)) {
			DownloadFile $RemoteUrl $Archive
		}

		Expand-Item7zip $Archive $InstallPath
	}

	if (-not (Test-Path "${InstallPath}\php.ini")) {
		Copy-Item "${InstallPath}\php.ini-development" "${InstallPath}\php.ini"
	}
}

function SetupPhpVersionString {
	param (
		[Parameter(Mandatory=$true)] [String] $Pattern
	)

	$RemoteUrl   = "${PHP_URI}/sha256sum.txt"
	$Destination = "${Env:Temp}\sha256sum.txt"

	If (-not [System.IO.File]::Exists($Destination)) {
		DownloadFile $RemoteUrl $Destination
	}

	$VersionString = Get-Content $Destination | Where-Object {
		$_ -match "php-($Pattern\.\d+)-src"
	} | ForEach-Object { $matches[1] }

	if ($VersionString -NotMatch '\d+\.\d+\.\d+' -or $null -eq $VersionString) {
		throw "Unable to obtain PHP version string using pattern 'php-($Pattern\.\d+)-src'"
	}

	Write-Output $VersionString.Split(' ')[-1]
}

function InstallPhpDevPack {
	param (
		[Parameter(Mandatory=$true)]  [System.String] $PhpVersion,
		[Parameter(Mandatory=$true)]  [System.String] $BuildType,
		[Parameter(Mandatory=$true)]  [System.String] $VC,
		[Parameter(Mandatory=$true)]  [System.String] $Platform,
		[Parameter(Mandatory=$false)] [System.String] $InstallPath = "C:\Projects\php-devpack"
	)

	Write-Host "Install PHP Dev pack: ${PhpVersion}"

	$Version = SetupPhpVersionString -Pattern $PhpVersion
	$FileName = "php-devel-pack-${Version}-${BuildType}-vc${VC}-${Platform}.zip"

	$RemoteUrl = "${PHP_URI}/${FileName}"
	$Archive   = "C:\Downloads\${FileName}"

	if (-not (Test-Path $InstallPath)) {
		if (-not [System.IO.File]::Exists($Archive)) {
			DownloadFile $RemoteUrl $Archive
		}

		$UnzipPath = "${Env:Temp}\php-${Version}-devel-VC${VC}-${Platform}"
		If (-not (Test-Path "$UnzipPath")) {
			Expand-Item7zip $Archive $Env:Temp
		}

		Move-Item -Path $UnzipPath -Destination $InstallPath
	}
}

function InstallPeclPsr {
	param (
		[Parameter(Mandatory=$true)]  [System.String] $PhpVersion,
		[Parameter(Mandatory=$true)]  [System.String] $BuildType,
		[Parameter(Mandatory=$true)]  [System.String] $VC,
		[Parameter(Mandatory=$true)]  [System.String] $Platform,
		[Parameter(Mandatory=$false)] [System.String] $PhpInstallPath = "C:\Projects\php"
	)

	Write-Host "Install PSR extension: ${Env:PSR_PECL_VERSION}"

	If ($BuildType -eq 'nts-Win32') {
		$Type = 'nts'
	} Else {
		$Type = 'ts'
	}

	$FileName = "php_psr-${Env:PSR_PECL_VERSION}-${PhpVersion}-${Type}-vc${VC}-${Platform}.zip"

	$RemoteUrl = "${PECL_URI}/psr/${Env:PSR_PECL_VERSION}/${FileName}"
	$Archive = "C:\Downloads\${FileName}"

	If (-not (Test-Path "${PhpInstallPath}\ext\php_psr.dll")) {
		If (-not [System.IO.File]::Exists($DestinationPath)) {
			DownloadFile $RemoteUrl $Archive
		}

		Expand-Item7zip $Archive "${PhpInstallPath}\ext"
	}
}

# ================================================================================== #

Function PrepareReleaseNote {
	$ReleaseFile = "${Env:APPVEYOR_BUILD_FOLDER}\package\RELEASE.txt"
	$ReleaseDate = Get-Date -Format g

	Write-Output "Release date: ${ReleaseDate}"                           | Out-File -Encoding "ASCII" -Append "${ReleaseFile}"
	Write-Output "Release version: ${Env:APPVEYOR_BUILD_VERSION}"         | Out-File -Encoding "ASCII" -Append "${ReleaseFile}"
	Write-Output "Git commit: ${Env:APPVEYOR_REPO_COMMIT}"                | Out-File -Encoding "ASCII" -Append "${ReleaseFile}"
	Write-Output "Build type: ${Env:BUILD_TYPE}"                          | Out-File -Encoding "ASCII" -Append "${ReleaseFile}"
	Write-Output "Platform: ${Env:PLATFORM}"                              | Out-File -Encoding "ASCII" -Append "${ReleaseFile}"
	Write-Output "Target PHP version: ${Env:PHP_MINOR}"                   | Out-File -Encoding "ASCII" -Append "${ReleaseFile}"
	Write-Output "Build worker image: ${Env:APPVEYOR_BUILD_WORKER_IMAGE}" | Out-File -Encoding "ASCII" -Append "${ReleaseFile}"
}

Function PrepareReleasePackage {
	PrepareReleaseNote

	$CurrentPath = (Get-Item -Path ".\" -Verbose).FullName
	$PackagePath = "${Env:APPVEYOR_BUILD_FOLDER}\package"

	FormatReleaseFiles

	Copy-Item -Path (Join-Path -Path $Env:APPVEYOR_BUILD_FOLDER -ChildPath '\*') -Filter '*.txt' -Destination "${PackagePath}" -Force
	Copy-Item "${Env:RELEASE_DLL_PATH}" "${PackagePath}"

	Set-Location "${PackagePath}"
	$result = (& 7z a "${Env:RELEASE_ZIPBALL}.zip" "*.*")

	$7zipExitCode = $LASTEXITCODE
	If ($7zipExitCode -ne 0) {
		Set-Location "${CurrentPath}"
		Throw "An error occurred while creating release zippbal to [${Env:RELEASE_ZIPBALL}.zip]. 7Zip Exit Code was [${7zipExitCode}]"
	}

	Move-Item "${Env:RELEASE_ZIPBALL}.zip" -Destination "${Env:APPVEYOR_BUILD_FOLDER}"

	Set-Location "${CurrentPath}"
}

Function FormatReleaseFiles {
	EnsurePandocIsInstalled

	$CurrentPath = (Get-Item -Path ".\" -Verbose).FullName

	Set-Location "${Env:APPVEYOR_BUILD_FOLDER}"

	Get-ChildItem (Get-Item -Path ".\" -Verbose).FullName *.md |
	ForEach-Object {
		$BaseName = $_.BaseName
		pandoc -f markdown -t html5 "${BaseName}.md" > "package/${BaseName}.html"
	}

	If (Test-Path -Path "package/CHANGELOG.html") {
		(Get-Content "package/CHANGELOG.html") | ForEach-Object {
			$_ -replace ".md", ".html"
		} | Set-Content "package/CHANGELOG.html"
	}

	Set-Location "${CurrentPath}"
}

Function InstallBuildDependencies {
	EnsureChocolateyIsInstalled
	EnsureComposerIsInstalled

	$InstallProcess = Start-Process "choco" `
		-WindowStyle Hidden `
		-ArgumentList 'install', '-y --cache-location=C:\Downloads\Choco pandoc' `
		-WorkingDirectory "${Env:APPVEYOR_BUILD_FOLDER}"

	If (-not (Test-Path "${Env:APPVEYOR_BUILD_FOLDER}\package")) {
		New-Item -ItemType Directory -Force -Path "${Env:APPVEYOR_BUILD_FOLDER}\package" | Out-Null
	}

	$ComposerOptions = "-q -n --no-progress -o --prefer-dist --no-suggest --ignore-platform-reqs"

	If (-not (Test-Path "${Env:APPVEYOR_BUILD_FOLDER}\vendor")) {
		Set-Location "${Env:APPVEYOR_BUILD_FOLDER}"

		& cmd /c ".\composer.bat install ${ComposerOptions}"
	}
}

Function EnsurePandocIsInstalled {
	If (-not (Get-Command "pandoc" -ErrorAction SilentlyContinue)) {
		$PandocInstallationDirectory = "${Env:ProgramData}\chocolatey\bin"

		If (-not (Test-Path "$PandocInstallationDirectory")) {
			Throw "The pandoc is needed to use this module"
		}

		$Env:Path += ";$PandocInstallationDirectory"
	}

	& "pandoc" -v
}

Function EnableExtension {
	If (-not (Test-Path "${Env:RELEASE_DLL_PATH}")) {
		Throw "Unable to locate extension path: ${Env:RELEASE_DLL_PATH}"
	}

	Copy-Item "${Env:RELEASE_DLL_PATH}" "${Env:PHP_PATH}\ext\${Env:EXTENSION_FILE}"

	$IniFile = "${Env:PHP_PATH}\php.ini"
	$PhpExe  = "${Env:PHP_PATH}\php.exe"

	If (-not [System.IO.File]::Exists($IniFile)) {
		Throw "Unable to locate ${IniFile}"
	}

	If (Test-Path -Path "${PhpExe}") {
		& "${PhpExe}" -d "extension=${Env:EXTENSION_FILE}" --ri "${Env:EXTENSION_NAME}"

		$PhpExitCode = $LASTEXITCODE
		If ($PhpExitCode -ne 0) {
			PrintPhpInfo
			Throw "An error occurred while enabling [${Env:EXTENSION_NAME}] in [$IniFile]. PHP Exit Code was [$PhpExitCode]."
		}
	}
}

Function InitializeReleaseVars {
	If ($Env:BUILD_TYPE -Match "nts-Win32") {
		$Env:RELEASE_ZIPBALL = "${Env:PACKAGE_PREFIX}_${Env:PLATFORM}_vc${Env:VC_VERSION}_php${Env:PHP_MINOR}_${Env:APPVEYOR_BUILD_VERSION}_nts"

		If ($Env:PLATFORM -eq 'x86') {
			$Env:RELEASE_FOLDER = "Release"
		} Else {
			$Env:RELEASE_FOLDER = "x64\Release"
		}
	} Else {
		$Env:RELEASE_ZIPBALL = "${Env:PACKAGE_PREFIX}_${Env:PLATFORM}_vc${Env:VC_VERSION}_php${Env:PHP_MINOR}_${Env:APPVEYOR_BUILD_VERSION}"

		If ($Env:PLATFORM -eq 'x86') {
			$Env:RELEASE_FOLDER = "Release_TS"
		} Else {
			$Env:RELEASE_FOLDER = "x64\Release_TS"
		}
	}

	$Env:RELEASE_DLL_PATH = "${Env:APPVEYOR_BUILD_FOLDER}\build\php7\safe\${Env:RELEASE_FOLDER}\${Env:EXTENSION_FILE}"
}

Function PrintLogs {
	Param([Parameter(Mandatory=$true)][System.String] $BasePath)

	If (Test-Path -Path "${BasePath}\compile-errors.log") {
		Get-Content -Path "${BasePath}\compile-errors.log"
	}

	If (Test-Path -Path "${BasePath}\compile.log") {
		Get-Content -Path "${BasePath}\compile.log"
	}

	If (Test-Path -Path "${BasePath}\configure.js") {
		Get-Content -Path "${BasePath}\configure.js"
	}
}

Function PrintVars {
	Write-Host ($Env:Path).Replace(';', "`n")

	Get-ChildItem Env:
}

Function PrintDirectoriesContent {
	Get-ChildItem -Path "${Env:APPVEYOR_BUILD_FOLDER}"

	If (Test-Path -Path "C:\Downloads") {
		Get-ChildItem -Path "C:\Downloads"
	}

	If (Test-Path -Path "C:\Projects") {
		Get-ChildItem -Path "C:\Projects"
	}

	If (Test-Path -Path "${Env:PHP_PATH}\ext") {
		Get-ChildItem -Path "${Env:PHP_PATH}\ext"
	}

	$ReleasePath = Split-Path -Path "${Env:RELEASE_DLL_PATH}"
	If (Test-Path -Path "${ReleasePath}") {
		Get-ChildItem -Path "${ReleasePath}"
	}

	$BuildPath = Split-Path -Path "${ReleasePath}"
	If (Test-Path -Path "${BuildPath}") {
		Get-ChildItem -Path "${BuildPath}"
	}

	If (Test-Path -Path "${Env:PHP_DEVPACK}") {
		Get-ChildItem -Path "${Env:PHP_DEVPACK}"
	}
}

Function PrintPhpInfo {
	$IniFile = "${Env:PHP_PATH}\php.ini"
	$PhpExe = "${Env:PHP_PATH}\php.exe"

	If (Test-Path -Path "${PhpExe}") {
		Write-Host ""
		& "${PhpExe}" -v

		Write-Host ""
		& "${PhpExe}" -m

		Write-Host ""
		& "${PhpExe}" -i
	} ElseIf (Test-Path -Path "${IniFile}") {
		Get-Content -Path "${IniFile}"
	}
}

Function InitializeBuildVars {
	switch ($Env:VC_VERSION) {
		'14' {
			If (-not (Test-Path $Env:VS120COMNTOOLS)) {
				Throw'The VS120COMNTOOLS environment variable is not set. Check your MS VS installation'
			}
			$Env:VSCOMNTOOLS = $Env:VS120COMNTOOLS -replace '\\$', ''

			break
		}
		'15' {
			If (-not (Test-Path $Env:VS140COMNTOOLS)) {
				Throw'The VS140COMNTOOLS environment variable is not set. Check your MS VS installation'
			}
			$Env:VSCOMNTOOLS = $Env:VS140COMNTOOLS -replace '\\$', ''
			break
		}
		default {
			Throw'This script is designed to run with MS VS 14/15. Check your MS VS installation'
			break
		}
	}

	If ($Env:PLATFORM -eq 'x64') {
		$Env:ARCH = 'x86_amd64'
	} Else {
		$Env:ARCH = 'x86'
	}
}

Function TuneUpPhp {
	$IniFile = "${Env:PHP_PATH}\php.ini"
	$ExtPath = "${Env:PHP_PATH}\ext"

	If (-not [System.IO.File]::Exists($IniFile)) {
		Throw "Unable to locate $IniFile file"
	}

	Write-Output ""                                  | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output "extension_dir = ${ExtPath}"        | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output "memory_limit = 256M"               | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output ""                                  | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output "extension = php_curl.dll"          | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output "extension = php_openssl.dll"       | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output "extension = php_mbstring.dll"      | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output "extension = php_pdo_sqlite.dll"    | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output "extension = php_fileinfo.dll"      | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output "extension = php_gettext.dll"       | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output "extension = php_gd2.dll"           | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output "extension = php_zephir_parser.dll" | Out-File -Encoding "ASCII" -Append $IniFile
	Write-Output "extension = php_psr.dll"           | Out-File -Encoding "ASCII" -Append $IniFile
}



Function InstallStablePhalcon {
	$BaseUri = "https://github.com/phalcon/cphalcon/releases/download"
	$PatchSuffix = ".0"
	$LocalPart = "${Env:PACKAGE_PREFIX}_${Env:PLATFORM}_vc${Env:VC_VERSION}_php${Env:PHP_MINOR}${PatchSuffix}"


	If ($Env:BUILD_TYPE -Match "nts-Win32") {
		$VersionSuffix = "${Env:PHALCON_STABLE_VERSION}_nts"
	} Else {
		$VersionSuffix = "${Env:PHALCON_STABLE_VERSION}"
	}

	$RemoteUrl = "${BaseUri}/v${Env:PHALCON_STABLE_VERSION}/${LocalPart}_${VersionSuffix}.zip"
	$DestinationPath = "C:\Downloads\${LocalPart}_${VersionSuffix}.zip"

	If (-not (Test-Path "${Env:PHP_PATH}\ext\${Env:EXTENSION_FILE}")) {
		If (-not [System.IO.File]::Exists($DestinationPath)) {
			Write-Host "Downloading stable Phalcon: ${RemoteUrl} ..."
			DownloadFile $RemoteUrl $DestinationPath
		}

		Expand-Item7zip $DestinationPath "${Env:PHP_PATH}\ext"
	}
}

Function InstallParser {
	$BaseUri = "https://github.com/phalcon/php-zephir-parser/releases/download"
	$LocalPart = "zephir_parser_${Env:PLATFORM}_vc${Env:VC_VERSION}_php${Env:PHP_MINOR}"

	If ($Env:BUILD_TYPE -Match "nts-Win32") {
		$VersionPrefix = "-nts"
	} Else {
		$VersionPrefix = ""
	}

	$RemoteUrl = "${BaseUri}/v${Env:PARSER_VERSION}/${LocalPart}${VersionPrefix}_${Env:PARSER_VERSION}-${Env:PARSER_RELEASE}.zip"
	$DestinationPath = "C:\Downloads\${LocalPart}${VersionPrefix}_${Env:PARSER_VERSION}-${Env:PARSER_RELEASE}.zip"

	If (-not (Test-Path "${Env:PHP_PATH}\ext\php_zephir_parser.dll")) {
		If (-not [System.IO.File]::Exists($DestinationPath)) {
			Write-Host "Downloading Zephir Parser: ${RemoteUrl} ..."
			DownloadFile $RemoteUrl $DestinationPath
		}

		Expand-Item7zip $DestinationPath "${Env:PHP_PATH}\ext"
	}
}

Function InstallZephir {
	$ZephirBatch = "${Env:APPVEYOR_BUILD_FOLDER}\zephir.bat"

	If (-not (Test-Path -Path $ZephirBatch)) {
		$Php = "${Env:PHP_PATH}\php.exe"
		$ZephirPhar = "${Env:APPVEYOR_BUILD_FOLDER}\zephir.phar"

		$BaseUri = "https://github.com/phalcon/zephir/releases/download"
		$RemoteUrl = "${BaseUri}/${Env:ZEPHIR_VERSION}/zephir.phar"

		DownloadFile "${RemoteUrl}" "${ZephirPhar}"

		Write-Output "@echo off"                   | Out-File -Encoding "ASCII" -Append $ZephirBatch
		Write-Output "${Php} `"${ZephirPhar}`" %*" | Out-File -Encoding "ASCII" -Append $ZephirBatch
	}
}

Function EnsureChocolateyIsInstalled {
	If (-not (Get-Command "choco" -ErrorAction SilentlyContinue)) {
		$ChocolateyInstallationDirectory = "${Env:ProgramData}\chocolatey\bin"

		If (-not (Test-Path "$ChocolateyInstallationDirectory")) {
			Throw "The choco is needed to use this module"
		}

		$Env:Path += ";$ChocolateyInstallationDirectory"
	}
}

Function EnsureComposerIsInstalled {
	$ComposerBatch = "${Env:APPVEYOR_BUILD_FOLDER}\composer.bat"

	If (-not (Test-Path -Path $ComposerBatch)) {
		$Php = "${Env:PHP_PATH}\php.exe"
		$ComposerPhar = "${Env:APPVEYOR_BUILD_FOLDER}\composer.phar"

		DownloadFile "https://getcomposer.org/composer.phar" "${ComposerPhar}"

		Write-Output "@echo off"                     | Out-File -Encoding "ASCII" -Append $ComposerBatch
		Write-Output "${Php} `"${ComposerPhar}`" %*" | Out-File -Encoding "ASCII" -Append $ComposerBatch
	}
}

Function AppendSessionPath {
	$PathsCollection  = @("C:\Program Files (x86)\MSBuild\${Env:VC_VERSION}.0\Bin")
	$PathsCollection += "C:\Program Files (x86)\Microsoft Visual Studio ${Env:VC_VERSION}.0\VC"
	$PathsCollection += "C:\Program Files (x86)\Microsoft Visual Studio ${Env:VC_VERSION}.0\VC\bin"
	$PathsCollection += "${Env:PHP_SDK_PATH}\bin"
	$PathsCollection += "${Env:PHP_PATH}\bin"
	$PathsCollection += "${Env:PHP_PATH}"
	$PathsCollection += "${Env:APPVEYOR_BUILD_FOLDER}"

	$CurrentPath = (Get-Item -Path ".\" -Verbose).FullName

	ForEach ($PathItem In $PathsCollection) {
		Set-Location Env:
		$AllPaths = (Get-ChildItem Path).value.split(";")  | Sort-Object -Unique
		$AddToPath = $true

		ForEach ($AddedPath In $AllPaths) {
			If (-not "${AddedPath}") {
				continue
			}

			$AddedPath = $AddedPath -replace '\\$', ''

			If ($PathItem -eq $AddedPath) {
				$AddToPath = $false
			}
		}

		If ($AddToPath) {
			$Env:Path += ";$PathItem"
		}
	}

	Set-Location "${CurrentPath}"
}
