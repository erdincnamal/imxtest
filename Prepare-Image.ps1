param(
    [Parameter(Mandatory = $true)] [string] $Image,
    [Parameter(Mandatory = $true)] [string] $Binary,
    [string] $Objcopy,
    [switch] $Unpadded
)

$ErrorActionPreference = 'Stop'
if (-not $Objcopy) {
    $Objcopy = (Get-Command arm-none-eabi-objcopy.exe -ErrorAction SilentlyContinue).Source
}
if (-not $Objcopy) {
    $Objcopy = 'C:/nxp/MCUXpressoIDE_25.6.136/ide/plugins/com.nxp.mcuxpresso.tools.win32_25.6.0.202501151204/tools/bin/arm-none-eabi-objcopy.exe'
}

$imagePath = (Resolve-Path -LiteralPath $Image).Path
$binaryPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Binary)
$objcopyPath = (Resolve-Path -LiteralPath $Objcopy).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('rt1176b-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
try {
    # Windows binutils may narrow Unicode CLI arguments. Use fixed relative ASCII names.
    Copy-Item -LiteralPath $imagePath -Destination (Join-Path $scratch 'input.elf')
    Push-Location -LiteralPath $scratch
    try {
        & $objcopyPath -O binary --gap-fill 0xff input.elf image.bin
        if ($LASTEXITCODE -ne 0) { throw 'Could not convert the application AXF' }

        $data = [IO.File]::ReadAllBytes((Join-Path $scratch 'image.bin'))
        if ($data.Length -lt 0x2008 -or $data.Length -gt 0x40000 -or
            [BitConverter]::ToUInt32($data, 0x400) -ne 0x42464346 -or $data[0x1000] -ne 0xD1 -or
            [BitConverter]::ToUInt32($data, 0x1014) -ne 0x30001000) {
            throw 'Expected a FlexSPI1 XIP AXF with FCB at 0x30000400, IVT at 0x30001000 and vectors at +0x2000'
        }

        $size = [int](($data.Length + 255) -band -256)
        $endAddress = '0x{0:X8}' -f (0x30000000 + $size)
        & $objcopyPath -O binary --gap-fill 0xff --pad-to $endAddress input.elf image.bin
        if ($LASTEXITCODE -ne 0 -or (Get-Item -LiteralPath 'image.bin').Length -ne $size) {
            throw 'Could not pad the AXF to a full flash page at the expected XIP address'
        }
        if ($Unpadded) {
            # Keep the raw extent so the RAM loader can preserve the final sector's tail.
            [IO.File]::WriteAllBytes($binaryPath, $data)
            Write-Output $data.Length
        } else {
            Copy-Item -LiteralPath 'image.bin' -Destination $binaryPath -Force
            Write-Output $size
        }
    } finally {
        Pop-Location
    }
} finally {
    foreach ($name in 'input.elf', 'image.bin') {
        $temporary = Join-Path $scratch $name
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
    Remove-Item -LiteralPath $scratch
}
