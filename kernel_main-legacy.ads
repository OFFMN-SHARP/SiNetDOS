-- kernel_main.ads
type Unsigned_32 is mod 2**32;

procedure Kernel_Main (Magic : Unsigned_32; Multiboot_Info : Unsigned_32)
  with Export, Convention => C, External_Name => "kernel_main";