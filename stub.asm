; stub.asm - 为 SNADOS 准备的 32 位引导程序
global start                  ; 内核入口点，必须导出
extern kernel_main            ; Pascal 写的主函数

; Multiboot 标准头
section .multiboot
align 4
    dd 0x1BADB002             ; 魔数
    dd 0x03                   ; 标志位
    dd -(0x1BADB002 + 0x03)   ; 校验和

section .text
start:
    mov esp, stack_top        ; 设置自己的栈
    call kernel_main          ; 移交控制权给 Pascal
    cli
    hlt                       ; 如果返回则停机

section .bss
stack_bottom:
    resb 16384                ; 保留 16KB 栈空间
stack_top: