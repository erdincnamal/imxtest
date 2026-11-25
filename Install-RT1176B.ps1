# Install the RT1176B / MX25UW51245G setup into a managed MCUXpresso IDE project.
[CmdletBinding()]
param(
    [string] $ProjectPath,
    [string] $Configuration,
    [string] $Artifact,
    [string] $Objcopy,
    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_]*$')] [string] $StopAt = 'main',
    [switch] $KeepFcb,
    [string] $DeviceRoot = (Join-Path $env:APPDATA 'SEGGER/JLinkDevices')
)

$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$utf8Bom = [Text.UTF8Encoding]::new($true)

function Read-XmlFile([string] $Path) {
    $xml = [xml]::new()
    $xml.PreserveWhitespace = $true
    $xml.Load($Path)
    return $xml
}

function Get-XmlText([xml] $Xml) {
    $settings = [Xml.XmlWriterSettings]::new()
    $settings.Encoding = $utf8
    $settings.NewLineHandling = [Xml.NewLineHandling]::Replace
    $buffer = [IO.MemoryStream]::new()
    $writer = [Xml.XmlWriter]::Create($buffer, $settings)
    try {
        $Xml.Save($writer)
        $writer.Flush()
        return $utf8.GetString($buffer.ToArray())
    } finally {
        $writer.Dispose()
        $buffer.Dispose()
    }
}

function Save-File([string] $Root, [string] $RelativePath, [byte[]] $Data) {
    $dest = Join-Path $Root $RelativePath
    $exists = Test-Path -LiteralPath $dest -PathType Leaf
    if ($exists) {
        $old = [IO.File]::ReadAllBytes($dest)
        if ([Convert]::ToBase64String($old) -ceq [Convert]::ToBase64String($Data)) { return }
        $backup = Join-Path $Root ('.rt1176b-backup/' + $RelativePath + '.bak')
        if (-not (Test-Path -LiteralPath $backup)) {
            [IO.Directory]::CreateDirectory((Split-Path -Parent $backup)) | Out-Null
            [IO.File]::WriteAllBytes($backup, $old)
        }
    }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $dest)) | Out-Null
    $pending = $dest + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllBytes($pending, $Data)
        if ($exists) {
            [IO.File]::Replace($pending, $dest, [NullString]::Value)
        } else {
            [IO.File]::Move($pending, $dest)
        }
    } finally {
        if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force }
    }
    Write-Host "Updated $dest"
}

function Expand-BuildPath([string] $Value) {
    $expanded = $Value.Replace('${ProjName}', $projectName).Replace('${project_name}', $projectName)
    $expanded = $expanded.Replace('${ConfigName}', $configName).Replace('${configuration_name}', $configName)
    $expanded = $expanded.Replace('${ProjDirPath}', $project).Replace('${project_loc}', $project)
    $expanded = $expanded.Replace($workspaceReference, $project)
    $workspacePrefix = '${workspace_loc:/' + $projectName + '/'
    if ($expanded.StartsWith($workspacePrefix) -and $expanded.EndsWith('}')) {
        $expanded = Join-Path $project $expanded.Substring($workspacePrefix.Length, $expanded.Length - $workspacePrefix.Length - 1)
    }
    if ($expanded.Contains('${')) { throw "Unrecognized build path '$Value'. Supply -Artifact with the project-relative AXF path." }
    return $expanded
}

function Set-Option($Tool, [string] $Class, [string] $Label, [string] $Type, [string] $Value) {
    $option = $Tool.SelectSingleNode("./option[@superClass='$Class']")
    if (-not $option) {
        $option = $cproject.CreateElement('option')
        $option.SetAttribute('id', "$Class.rt1176b")
        $option.SetAttribute('superClass', $Class)
        $option.SetAttribute('name', $Label)
        $Tool.AppendChild($option) | Out-Null
    }
    $option.SetAttribute('valueType', $Type)
    if ($Value) { $option.SetAttribute('value', $Value) }
    return $option
}

function Set-XipDefines($Tool, [string] $Class) {
    $option = Set-Option $Tool $Class 'Defined symbols (-D)' 'definedSymbols' ''
    $option.SetAttribute('IS_VALUE_EMPTY', 'false')
    foreach ($symbol in 'XIP_EXTERNAL_FLASH', 'XIP_BOOT_HEADER_ENABLE') {
        $values = @($option.SelectNodes('./listOptionValue') |
            Where-Object { $_.GetAttribute('value').Split('=')[0] -ceq $symbol })
        if ($values.Count -gt 0) {
            $values[0].SetAttribute('value', "$symbol=1")
            foreach ($duplicate in ($values | Select-Object -Skip 1)) {
                $option.RemoveChild($duplicate) | Out-Null
            }
        } else {
            $value = $cproject.CreateElement('listOptionValue')
            $value.SetAttribute('builtIn', 'false')
            $value.SetAttribute('value', "$symbol=1")
            $option.AppendChild($value) | Out-Null
        }
    }
}

function Find-FcbInitializer([string] $Source, [string] $Name) {
    $definitions = [regex]::Matches($Source, '\bflexspi_nor_config_t\s+[A-Za-z_]\w*\s*=\s*(?=\{)')
    if ($definitions.Count -ne 1) {
        throw "Cannot identify a single flexspi_nor_config_t initializer in '$Name'. Use -KeepFcb to preserve its custom FCB."
    }
    $start = $definitions[0].Index + $definitions[0].Length
    # Ignore braces in C comments, character literals and strings while locating the initializer boundary.
    $tokens = [regex]::new('/\*[\s\S]*?\*/|//[^\r\n]*|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|[{}]')
    $depth = 0
    foreach ($token in $tokens.Matches($Source, $start)) {
        if ($token.Value -eq '{') { $depth++ }
        if ($token.Value -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return [pscustomobject]@{ Start = $start; Length = $token.Index - $start + 1 }
            }
        }
    }
    throw "The FCB initializer in '$Name' has no closing brace."
}

$payload = Join-Path $PSScriptRoot 'payload'
if (-not (Test-Path -LiteralPath $payload -PathType Container)) { throw 'Extract the complete integration ZIP before running the installer.' }

if (-not $ProjectPath) {
    $folder = Get-Item -LiteralPath $PSScriptRoot
    while ($folder -and -not (Test-Path -LiteralPath (Join-Path $folder.FullName '.cproject'))) {
        $folder = $folder.Parent
    }
    $ProjectPath = if ($folder) { $folder.FullName } else { (Get-Location).Path }
}
$project = (Resolve-Path -LiteralPath $ProjectPath).Path
$description = Read-XmlFile (Join-Path $project '.project')
$projectName = $description.projectDescription.name
if (-not $projectName) { throw 'Cannot read the Eclipse project name from .project.' }
$cproject = Read-XmlFile (Join-Path $project '.cproject')
$before = $cproject.OuterXml
$sdk = $cproject.SelectSingleNode('/cproject/storageModule[@moduleId="com.nxp.mcuxpresso.core.datamodels"]')
$configs = @($cproject.SelectNodes('/cproject/storageModule/cconfiguration/storageModule/configuration') |
    Where-Object { $_.GetAttribute('parent').StartsWith('com.crt.advproject.config.exe') -or
        $_.GetAttribute('buildArtefactType').EndsWith('.exe') })
if ($Configuration) {
    $selected = @($configs | Where-Object { $_.GetAttribute('name') -eq $Configuration -or $_.GetAttribute('id') -eq $Configuration })
} else {
    $selected = @($configs | Where-Object { $_.GetAttribute('name') -eq 'Debug' })
    if (-not $selected.Count) {
        $selected = @($configs | Where-Object { $_.GetAttribute('name') -match 'debug' })
    }
    if (-not $selected.Count -and $configs.Count -eq 1) { $selected = $configs }
}
if ($selected.Count -ne 1) {
    throw ('Select an executable build configuration with -Configuration. Available: ' +
        (($configs | ForEach-Object { $_.GetAttribute('name') }) -join ', '))
}
$config = $selected[0]
$configName = $config.GetAttribute('name')
$configId = $config.ParentNode.ParentNode.GetAttribute('id')
$core = if ($sdk) { $sdk.SelectSingleNode('./core') }
if ($cproject.OuterXml -notmatch 'MIMXRT1176' -or
    ($core -and $core.InnerText -ne 'cm7') -or
    (-not $core -and $config.OuterXml -notmatch '(?:target\.cm7|cortex-m7|CPU_MIMXRT1176\w+_cm7)')) {
    throw 'Expected an MCUXpresso project targeting MIMXRT1176 Cortex-M7.'
}

$workspaceReference = '${workspace_loc:/' + $projectName + '}'
if (-not $Artifact) {
    $builder = $config.SelectSingleNode('./folderInfo/toolChain/builder')
    $buildPath = if ($builder -and $builder.GetAttribute('buildPath')) {
        Expand-BuildPath ($builder.GetAttribute('buildPath'))
    } else { $configName }
    $artifactName = $config.GetAttribute('artifactName')
    if (-not $artifactName) { $artifactName = $projectName }
    $artifactName = Expand-BuildPath $artifactName
    $extension = $config.GetAttribute('artifactExtension').TrimStart('.')
    if ($extension) {
        $artifactName += '.' + $extension
    } elseif ([IO.Path]::GetExtension($artifactName) -notin '.axf', '.elf') {
        $artifactName += '.axf'
    }
    $Artifact = Join-Path $buildPath $artifactName
}
$artifactPath = if ([IO.Path]::IsPathRooted($Artifact)) { [IO.Path]::GetFullPath($Artifact) } else {
    [IO.Path]::GetFullPath((Join-Path $project $Artifact))
}
$projectPrefix = $project.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $artifactPath.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetExtension($artifactPath) -notin '.axf', '.elf') {
    throw 'Use an .axf or .elf artifact inside the project directory.'
}
$artifactRelative = $artifactPath.Substring($projectPrefix.Length).Replace('\', '/')

$files = [ordered]@{}
foreach ($name in @('RT1176B-debug.gdb', 'Stage-Debug-Image.ps1', 'Prepare-Image.ps1', 'recover.elf',
    'launch.xml', 'JLinkDevices.xml', 'RT1176_MX25UW51245G.FLM',
    'fcb.c.in', 'fcb.h.in', 'boot.c.in', 'boot.h.in')) {
    $files[$name] = [IO.File]::ReadAllBytes((Join-Path $payload $name))
}

$linkers = @($config.SelectNodes('./folderInfo/toolChain/tool[starts-with(@superClass,"com.crt.advproject.link.")]'))
$compilers = @($config.SelectNodes('./folderInfo/toolChain/tool[starts-with(@superClass,"com.crt.advproject.gcc.") or starts-with(@superClass,"com.crt.advproject.cpp.")]'))
if (-not $linkers.Count -or -not $compilers.Count) { throw 'Expected the MCUXpresso managed GCC compiler and linker.' }

$memory = $cproject.SelectSingleNode('/cproject/storageModule[@moduleId="com.crt.config"]/projectStorage')
$flash = $null
if ($memory) {
    $target = [xml] $memory.InnerText
    $flash = $target.SelectSingleNode('//chip/memoryInstance[@location="0x30000000" and @derived_from="Flash"]')
}
$managed = @($linkers | Where-Object {
    $option = $_.SelectSingleNode('./option[@superClass="com.crt.advproject.link.manage" or @superClass="com.crt.advproject.link.cpp.manage"]')
    -not $option -or $option.GetAttribute('value') -ne 'false'
})
if ($managed.Count) {
    if (-not $flash) {
        $chip = if ($memory) { $target.SelectSingleNode('//chip[memory[@id="Flash"]]') }
        if (-not $chip -or $chip.SelectSingleNode('./memoryInstance[@id="BOARD_FLASH" or @location="0x30000000"]')) {
            throw 'Cannot add the FlexSPI1 XIP bank to this project memory map. Start from the MIMXRT1176 CM7 SDK project or select its FlexSPI NOR configuration.'
        }
        $flash = $target.CreateElement('memoryInstance')
        $flash.SetAttribute('derived_from', 'Flash')
        $flash.SetAttribute('edited', 'true')
        $flash.SetAttribute('id', 'BOARD_FLASH')
        $flash.SetAttribute('location', '0x30000000')
        $chip.InsertBefore($flash, $chip.SelectSingleNode('./memoryInstance')) | Out-Null
    }
    $firstBank = $flash.ParentNode.SelectSingleNode('./memoryInstance[@derived_from="Flash"]')
    $memoryChanged = $false
    if ($firstBank -ne $flash) {
        $flash.ParentNode.InsertBefore($flash, $firstBank) | Out-Null
        $memoryChanged = $true
    }
    if ($flash.GetAttribute('size') -notin '0x4000000', '0x04000000') {
        $flash.SetAttribute('size', '0x4000000')
        $memoryChanged = $true
    }
    if ($memoryChanged) { $memory.InnerText = $target.OuterXml }
    foreach ($linker in $managed) {
        $class = if ($linker.GetAttribute('superClass').StartsWith('com.crt.advproject.link.cpp.')) { 'com.crt.advproject.link.cpp' } else { 'com.crt.advproject.link' }
        Set-Option $linker "$class.toram" 'Link application to RAM' 'boolean' 'false' | Out-Null
        Set-Option $linker "$class.flashconfigenable" 'Enable automatic placement of Flash Configuration field in image' 'boolean' 'true' | Out-Null
    }
}
foreach ($compiler in $compilers) {
    $class = if ($compiler.GetAttribute('superClass').StartsWith('com.crt.advproject.cpp.')) {
        'gnu.cpp.compiler.option.preprocessor.def'
    } else { 'gnu.c.compiler.option.preprocessor.def.symbols' }
    Set-XipDefines $compiler $class
}

$sourceEntries = $config.SelectSingleNode('./sourceEntries')
$sourceDefinitions = if ($sourceEntries) { $sourceEntries.SelectNodes('./entry[@kind="sourcePath"]') }
$sourceRoots = @($sourceDefinitions | ForEach-Object { $_.GetAttribute('name').TrimEnd('/') })
if (-not $sourceRoots.Count) { $sourceRoots = @('') }
$fcbSources = @()
$hasIvt = $false
foreach ($file in (Get-ChildItem -LiteralPath $project -Recurse -File |
    Where-Object { $_.Extension -in '.c', '.cc', '.cpp', '.cxx' })) {
    $relative = $file.FullName.Substring($projectPrefix.Length).Replace('\', '/')
    if ($relative.StartsWith('.rt1176b-backup/')) { continue }
    if ($sourceDefinitions) {
        $included = $false
        foreach ($source in $sourceDefinitions) {
            $root = $source.GetAttribute('name').TrimEnd('/')
            if ($root -and -not $relative.StartsWith("$root/", [StringComparison]::OrdinalIgnoreCase)) { continue }
            $child = if ($root) { $relative.Substring($root.Length + 1) } else { $relative }
            $excluded = @($source.GetAttribute('excluding').Split('|') | Where-Object {
                $_ -and ($child -like $_ -or $child -like ($_.TrimEnd('/') + '/*'))
            })
            if (-not $excluded.Count) { $included = $true; break }
        }
        if (-not $included) { continue }
    }
    $code = [IO.File]::ReadAllText($file.FullName)
    if ($code.Contains('".boot_hdr.conf"')) { $fcbSources += $relative }
    if ($code.Contains('".boot_hdr.ivt"')) { $hasIvt = $true }
}
if ($fcbSources.Count -gt 1 -and -not $KeepFcb) { throw "Multiple FCB source files were found: $($fcbSources -join ', '). Use -KeepFcb to preserve an existing custom configuration." }

$install = [ordered]@{}
if (-not $KeepFcb) {
    $template = $utf8.GetString($files['fcb.c.in'])
    if ($fcbSources.Count) {
        $fcbPath = $fcbSources[0]
        $current = [IO.File]::ReadAllText((Join-Path $project $fcbPath))
        if ($current -notmatch '\.FlashStateCtx\s*=\s*0[xX]0?7008200[uU]?' -or
            $current -notmatch '\.isDataOrderSwapped\s*=\s*true') {
            $oldFcb = Find-FcbInitializer $current $fcbPath
            $newFcb = Find-FcbInitializer $template 'bundle FCB'
            $initializer = $template.Substring($newFcb.Start, $newFcb.Length)
            $updated = $current.Remove($oldFcb.Start, $oldFcb.Length).Insert($oldFcb.Start, $initializer)
            $install[$fcbPath] = $utf8.GetBytes($updated)
        }
    } else {
        $fcbSource = $template.Replace('evkbmimxrt1170_flexspi_nor_config.h', 'rt1176b_fcb.h')
        $install['rt1176b-bootstrap/rt1176b_fcb.c'] = $utf8.GetBytes($fcbSource)
        $install['rt1176b-bootstrap/rt1176b_fcb.h'] = $files['fcb.h.in']
    }
}
if (-not $hasIvt) {
    $install['rt1176b-bootstrap/fsl_flexspi_nor_boot.c'] = $files['boot.c.in']
    $install['rt1176b-bootstrap/fsl_flexspi_nor_boot.h'] = $files['boot.h.in']
}
if ($sourceEntries -and '' -notin $sourceRoots -and 'rt1176b-bootstrap' -notin $sourceRoots -and
    ($install.Keys -match '^rt1176b-bootstrap/.*\.c$' -or
     @(Get-ChildItem -LiteralPath (Join-Path $project 'rt1176b-bootstrap') -Filter '*.c' -File -ErrorAction SilentlyContinue).Count)) {
    $entry = $cproject.CreateElement('entry')
    $entry.SetAttribute('flags', 'LOCAL|VALUE_WORKSPACE_PATH|RESOLVED')
    $entry.SetAttribute('kind', 'sourcePath')
    $entry.SetAttribute('name', 'rt1176b-bootstrap')
    $sourceEntries.AppendChild($entry) | Out-Null
}

$launch = [xml] $utf8.GetString($files['launch.xml'])
$attributes = @{
    'org.eclipse.cdt.launch.PROJECT_ATTR' = $projectName
    'org.eclipse.cdt.launch.PROJECT_BUILD_CONFIG_ID_ATTR' = $configId
    'org.eclipse.cdt.launch.PROGRAM_NAME' = $artifactRelative
    'org.eclipse.cdt.debug.gdbjtag.core.stopAt' = $StopAt
    'org.eclipse.cdt.debug.gdbjtag.core.imageFileName' = '${workspace_loc:/' + $projectName + '/RT1176B-debug.gdb}'
    'org.eclipse.cdt.dsf.gdb.GDB_INIT' = '${workspace_loc:/' + $projectName + '/RT1176B-debug.gdb}'
    'org.eclipse.cdt.debug.gdbjtag.core.initCommands' = "cd $workspaceReference`nmon exec SetRestartOnClose=0`nmon reset"
}
foreach ($key in $attributes.Keys) {
    $launch.SelectSingleNode("/launchConfiguration/*[@key='$key']").SetAttribute('value', $attributes[$key])
}
$launch.SelectSingleNode('/launchConfiguration/listAttribute[@key="org.eclipse.debug.core.MAPPED_RESOURCE_PATHS"]/listEntry').SetAttribute('value', "/$projectName")

if (-not $Objcopy) {
    $Objcopy = (Get-Command arm-none-eabi-objcopy.exe -ErrorAction SilentlyContinue).Source
}
if (-not $Objcopy) {
    $roots = @('C:/nxp', (Join-Path $env:ProgramFiles 'NXP')) | Where-Object { Test-Path -LiteralPath $_ }
    $Objcopy = $roots | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter 'MCUXpressoIDE*' -Directory } |
        Sort-Object LastWriteTime -Descending | ForEach-Object {
            Get-ChildItem -Path "$($_.FullName)/ide/plugins/com.nxp.mcuxpresso.tools.win32_*/tools/bin/arm-none-eabi-objcopy.exe" -File
        } | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Objcopy -or -not (Test-Path -LiteralPath $Objcopy -PathType Leaf)) {
    throw 'GNU arm-none-eabi-objcopy.exe not found. Set its directory in PATH or supply -Objcopy.'
}
$Objcopy = (Resolve-Path -LiteralPath $Objcopy).Path

$stage = $utf8.GetString($files['Stage-Debug-Image.ps1'])
$stage = [regex]::new('(?m)^(    \[string\] \$Image = )''[^'']+''').Replace($stage, {
    param($m)
    $m.Groups[1].Value + "'" + $artifactRelative.Replace("'", "''") + "'"
}, 1)
$stage = $stage.Replace('Debug/RT1176B-bootstrap.', 'rt1176b-bootstrap/RT1176B-bootstrap.')
$prepare = $utf8.GetString($files['Prepare-Image.ps1'])
$prepare = [regex]::new('(?m)^(    \[string\] \$Objcopy)(,?)(?=\r?$)').Replace($prepare, {
    param($m)
    $m.Groups[1].Value + " = '" + $Objcopy.Replace("'", "''") + "'" + $m.Groups[2].Value
}, 1)

# Windows PowerShell needs the UTF-8 BOM to read non-ASCII paths in scripts.
$install['rt1176b-bootstrap/Stage-Debug-Image.ps1'] = $utf8Bom.GetPreamble() + $utf8Bom.GetBytes($stage)
$install['rt1176b-bootstrap/Prepare-Image.ps1'] = $utf8Bom.GetPreamble() + $utf8Bom.GetBytes($prepare)
$install['rt1176b-bootstrap/recover.elf'] = $files['recover.elf']
$install['RT1176B-debug.gdb'] = $utf8.GetBytes($utf8.GetString($files['RT1176B-debug.gdb']).Replace(
    'Debug/RT1176B-bootstrap.', 'rt1176b-bootstrap/RT1176B-bootstrap.'))
$launchName = "$projectName RT1176B J-Link"
$install["$launchName.launch"] = $utf8.GetBytes((Get-XmlText $launch))
if ($before -cne $cproject.OuterXml) { $install['.cproject'] = $utf8.GetBytes((Get-XmlText $cproject)) }

$devicePath = Join-Path $DeviceRoot 'RT1176B_MX25UW51245G'
Save-File $devicePath 'JLinkDevices.xml' $files['JLinkDevices.xml']
Save-File $devicePath 'RT1176_MX25UW51245G.FLM' $files['RT1176_MX25UW51245G.FLM']
foreach ($file in $install.GetEnumerator()) { Save-File $project $file.Key $file.Value }

Write-Host "Project: $projectName | Build: $configName | AXF: $artifactRelative"
Write-Host "Refresh or reopen the project in MCUXpresso, then select '$launchName' under Debug Configurations."
