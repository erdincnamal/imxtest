param(
    [string] $Image = 'Debug/evkbmimxrt1170_iled_blinky_cm7.axf',
    [ValidateSet('image', 'fcb', 'reflash')] [string] $Mode = 'reflash'
)

$ErrorActionPreference = 'Stop'
$gdbCommands = 'Debug/RT1176B-bootstrap.gdb'
$binary = 'Debug/RT1176B-bootstrap.bin'
$operation = 0
$verifiedLength = 0
$status = '0x600'

if ($Mode -eq 'fcb') {
    # Use ELF physical load addresses so even an FCB-only AXF has a stable offset.
    $fcbAddress = 0x30000400
    $length = 0x200
    $elf = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Image).Path)
    if ($elf.Length -lt 52 -or [BitConverter]::ToUInt32($elf, 0) -ne 0x464c457f -or
        $elf[4] -ne 1 -or $elf[5] -ne 1 -or [BitConverter]::ToUInt16($elf, 18) -ne 40) {
        throw 'Expected a 32-bit little-endian Arm ELF/AXF'
    }

    $table = [BitConverter]::ToUInt32($elf, 28)
    $stride = [BitConverter]::ToUInt16($elf, 42)
    $segments = [BitConverter]::ToUInt16($elf, 44)
    if ($segments -gt 0 -and ($stride -lt 32 -or
        [long]$table + [long]$stride * $segments -gt $elf.Length)) {
        throw 'Invalid ELF program header table'
    }

    $fcb = $null
    for ($index = 0; $index -lt $segments; $index++) {
        $header = $table + $stride * $index
        if ([BitConverter]::ToUInt32($elf, $header) -ne 1) { continue }
        $address = [BitConverter]::ToUInt32($elf, $header + 12)
        $fileSize = [BitConverter]::ToUInt32($elf, $header + 16)
        $offset = [long]$fcbAddress - $address
        if ($offset -lt 0 -or $offset + $length -gt $fileSize) { continue }

        $start = [long][BitConverter]::ToUInt32($elf, $header + 4) + $offset
        if ($start + $length -gt $elf.Length) { throw 'FCB range exceeds AXF length' }
        if ([BitConverter]::ToUInt32($elf, $start) -eq 0x42464346) {
            if ($null -ne $fcb) { throw 'Multiple FCB records at the same load address' }
            $fcb = [byte[]]::new($length)
            [Array]::Copy($elf, $start, $fcb, 0, $length)
        }
    }

    if ($null -eq $fcb) {
        'set $rt1176b_length = 0' | Set-Content -Encoding ascii -LiteralPath $gdbCommands
        return
    }
    [IO.File]::WriteAllBytes((Join-Path (Get-Location).Path $binary), $fcb)
    $operation = 1
    $verifiedLength = 0x1000
    $status = '0x610'
} else {
    $reflash = $Mode -eq 'reflash'
    $length = & "$PSScriptRoot/Prepare-Image.ps1" -Image $Image -Binary $binary -Unpadded:$reflash
    $verifiedLength = $length
    if ($reflash) {
        $operation = 2
        $status = '0x620'
    }
}

$runner = Join-Path $PSScriptRoot 'recover.elf'
$entry = [BitConverter]::ToUInt32([IO.File]::ReadAllBytes($runner), 24)
if ($entry -lt 0x20281001 -or $entry -ge 0x20284000 -or ($entry -band 1) -ne 1) {
    throw 'The RAM loader has an unexpected entry address'
}

@(
    'restore rt1176b-bootstrap/recover.elf'
    "restore $binary binary 0x202c0000"
    "set *(unsigned int *)0x20280000 = $length"
    'set *(unsigned int *)0x20280004 = 0'
    'set *(unsigned int *)0x20280008 = 0'
    "set *(unsigned int *)0x2028000c = $operation"
    ('set $rt1176b_length = {0}' -f $length)
    ('set $rt1176b_verified_end = 0x{0:x8}' -f (0x30000000 + $verifiedLength))
    ('set $rt1176b_success = {0}' -f $status)
    ('set $rt1176b_entry = 0x{0:x8}' -f $entry)
) | Set-Content -Encoding ascii -LiteralPath $gdbCommands
