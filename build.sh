#!/bin/bash
set -e  # 任何命令失败则立即退出

echo "==> 清理旧的构建文件..."
rm -f kernel_main.o kernel_main.ali kernel.bin

echo "==> 编译汇编引导..."
nasm -f elf32 stub.asm -o stub.o

echo "==> 编译 Ada 内核..."
gnatmake -c -gnatp -nostdlib -Os -m32 -march=i386 kernel_main.adb

echo "==> 链接生成 kernel.bin..."
ld -m elf_i386 -T linker.ld -o kernel.bin stub.o kernel_main.o

echo "==> 构建完成! 使用以下命令运行:"
echo "    qemu-system-i386 -kernel kernel.bin"