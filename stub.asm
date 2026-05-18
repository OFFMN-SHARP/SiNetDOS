; stub.asm
global start
extern _ada_kernel_main

section .multiboot
align 4
    dd 0x1BADB002
    dd 0x03
    dd -(0x1BADB002 + 0x03)

section .text
start:
    mov esp, stack_top
    push eax            ; multiboot magic
    push ebx            ; multiboot_info 指针
    call _ada_kernel_main
    cli
    hlt

section .bss
stack_bottom:
    resb 16384
stack_top: