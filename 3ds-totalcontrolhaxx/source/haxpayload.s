.text
.arm

.global haxpayload
.type haxpayload, %function
haxpayload:
mov sp, #0x10000000
.incbin "../../3ds_arm11code.bin"

