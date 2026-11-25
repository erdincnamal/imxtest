# MCUXpresso calls this CLI command at launch. Keeping loadImage enabled
# also enables the SEGGER plugin's hardware reset on IDE Restart.
define load
    rt1176b-program reflash
end

define rt1176b-program
    shell powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File rt1176b-bootstrap/Stage-Debug-Image.ps1 -Mode $arg0
    if $_shell_exitcode != 0
        echo RT1176B: could not prepare the application AXF.\n
        with confirm off -- quit 1
    end
    source Debug/RT1176B-bootstrap.gdb
    if $rt1176b_length != 0
        set $sp = 0x202bfff0
        set $pc = $rt1176b_entry & ~1
        continue
        if *(unsigned int *)0x20280004 != $rt1176b_success || *(unsigned int *)0x20280008 != $rt1176b_verified_end
            printf "RT1176B: RAM loader mailbox status 0x%x, detail 0x%x.\n", *(unsigned int *)0x20280004, *(unsigned int *)0x20280008
            echo RT1176B: Flash programming did not verify.\n
            with confirm off -- quit 1
        end
        if $rt1176b_success == 0x610
            echo RT1176B: rewrote the AXF FCB and verified the complete 4 KiB sector.\n
        else
            printf "RT1176B: programmed and verified %u bytes, including the FCB and IVT.\n", $rt1176b_length
        end
        monitor reset
    end
end

document load
Program and verify the complete XIP image from the AXF.
end
