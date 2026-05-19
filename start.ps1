#qemu-system-i386 -kernel kernel.bin
# run.ps1
$img = "disk.img"
if (-not (Test-Path $img)) {
    Write-Host "Creating disk image (128M)..."
    qemu-img create -f raw $img 128M
}
Write-Host "Starting SiNetDOS..."
qemu-system-i386 -kernel kernel.bin -hda $img