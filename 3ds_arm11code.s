.section .init
.global _start
.arm

_start:
push {r0-r12,lr}
sub sp, sp, #32

add r1, pc, #1
bx r1
.thumb

mov r7, r0

ldr r0, [r7, #0x5c]
cmp r0, #0
bne _start_initgsp

ldr r1, =0x300
str r1, [r7, #0x5c]

_start_initgsp:
bl gsp_initialize

ldr r0, =0x1ED02A04
ldr r1, =0x010000FF
bl gsp_writereg @ Set sub-screen colorfill to red.

ldr r0, [r7, #0x48]
mov r1, #0x10
tst r0, r1
bne kernelhax_end

bl kernelhax

kernelhax_end:
ldr r0, [r7, #0x4c]
cmp r0, #0
beq start_loadcode
blx r0

start_loadcode:
ldr r0, =0x1ED02A04
ldr r1, =0x01FFFF00
bl gsp_writereg @ Set sub-screen colorfill.

bl loadsd_arm9code

ldr r0, =0x1ED02A04
ldr r1, =0x01FFFFFF
bl gsp_writereg @ Set sub-screen colorfill.

ldr r0, =0x1ED02204
ldr r1, =0x01FFFFFF
bl gsp_writereg @ Set main-screen colorfill.

blx kernelmode_code_getadr
blx svc7b

#ifdef DUMPMEMGPU_AFTERPATCHES
#ifdef DUMPMEMGPU_ADR
#ifdef DUMPMEMGPU_SIZE
add r0, sp, #12
bl srv_init
bl throw_fatalerr_errcheck

bl get_fsuser_servname
mov r2, r0
add r0, sp, #12 @ srv handle
add r1, sp, #16 @ Out handle
bl srv_GetServiceHandle
bl throw_fatalerr_errcheck

add r0, sp, #16
bl fsuser_initialize
bl throw_fatalerr_errcheck

add r0, sp, #16
ldr r1, =DUMPMEMGPU_ADR
ldr r2, =DUMPMEMGPU_SIZE
bl dumpmemgpu_writesd

ldr r0, [sp, #16]
blx svcCloseHandle

add r0, sp, #12
bl srv_shutdown
#endif
#endif
#endif

bl exit_launchtitle

/*mov r0, #0
mov r1, #3
svc 0x33 @ svcOpenProcess(<sm module PID>)
cmp r0, #0
bne code_endcrash

mov r4, r1
mov r3, r4
mov r1, #1
adr r0, kernelmode_code_stage2
orr r0, r0, r1
blx svc7b

cmp r3, #0
bne code_endcrash

mov r0, r4
blx svcCloseHandle

bl arm11code_startfirmlaunch*/

adr r1, doReturn
bx r1

.arm
doReturn:
add sp, sp, #32
pop {r0-r12,pc}
.pool
.thumb

kernelhax:
push {r4, r5, r6, lr}
ldr r0, [r7, #0x48]
mov r1, #1
tst r0, r1
beq kernelhax_start_freememend

mov r0, #1 @ operation
mov r4, #0 @ permissions

ldr r1, =0x08000000 @ addr0
mov r2, #0 @ addr1
ldr r3, =0x10000 @ size
blx svcControlMemory @ Free the 0x10000-bytes @ 0x08000000.
//ldr r1, =0x71717171 @ Ignore any errors from this, for when code which called this arm11code binary already freed this memory.
//bl checkfail_thumb

blx svcSleepThread_delay1second

kernelhax_start_freememend:

blx get_kernelcode_overwriteaddr
cmp r0, #0
bne kernelhax_begin
ldr r0, =0x80808080
bl throw_fatalerr

kernelhax_begin:
mov r5, r0

ldr r4, =0x1FF80002
ldrb r4, [r4]

cmp r4, #48 @ v9.3
bge kernelhax_v93

mov r0, r5
bl kernel_memchunkhax
b kernelhax_finish

kernelhax_v93: @ FIRM >=v9.3
ldr r0, =0x58484b4e @ "NKHX", that is: "No Kernel HaX"
bl throw_fatalerr

kernelhax_finish:
bl trigger_icache_invalidation

pop {r4, r5, r6, pc}
.pool

kernel_memchunkhax:
push {r4, r5, r6, lr}
sub sp, sp, #32

str r0, [sp, #24]

ldr r0, [r7, #0]
cmp r0, #0
bne start_memchunkhax

ldr r0, =0x10003 @ operation
mov r4, #3 @ permissions

mov r1, #0 @ addr0
mov r2, #0 @ addr1
ldr r3, =0x1000 @ size
blx svcControlMemory @ Allocate 0x1000-bytes of linearmem, which should be located at the physaddr used below in the memchunkhax.
str r1, [sp, #28]
ldr r1, =0x71717171
bl checkfail_thumb

blx svcSleepThread_delay1second

mov r0, #1 @ operation
mov r4, #0 @ permissions

ldr r1, [sp, #28] @ addr0
mov r2, #0 @ addr1
ldr r3, =0x1000 @ size
blx svcControlMemory @ Free the linearmem which was mapped above.
ldr r1, =0x72727272
bl checkfail_thumb

ldr r1, [sp, #28] @ Above linearmem vaddr, when it was mapped.
str r1, [r7]

blx svcSleepThread_delay1second

start_memchunkhax:
ldr r5, =0x1000
add r5, r5, r7 @ Setup the fake heap memchunk structure.
ldr r6, =0x1000
add r6, r6, r5

ldr r0, [sp, #24]
//ldr r0, =0x40404040
sub r2, r0, #4 @ This causes the kernelpanic-branch which is executed in the SVC-handler when the process doesn't have access to the SVC, to be patched out via overwriting it with value 0.

mov r0, #0
mov r1, #1
str r1, [r5, #0]
str r0, [r5, #4]
str r2, [r5, #8]
str r0, [r5, #12]

mov r0, r5
mov r1, #0x10
bl gsp_flushdcache

mov r0, r6
mov r1, #0x10
bl gsp_flushdcache

kernel_memchunkhax_copyoriginalchunk:
@ Copy the original memchunk structure to tmpbuf+0x2000.
ldr r0, [r7] @ src-addr
mov r1, r6 @ dst-addr
mov r2, #0x10 @ size

mov r3, #8
str r3, [sp, #12] @ flags
mov r3, #0 @ width0
str r3, [sp, #0] @ height0
str r3, [sp, #4] @ width1
str r3, [sp, #8] @ height1

blx gxlow_cmd4

blx svcSleepThread_delay1second

ldr r0, [r6, #4]
cmp r0, #0
beq kernel_memchunkhax_writenewhdr @ Branch when the memchunkhdr next-ptr is NULL.

mov r1, #4 @ Clear the high 4-bits in the kernel FCRAM vaddr, resulting in a FCRAM offset.
lsl r0, r0, r1
lsr r0, r0, r1

mov r2, #0x14
mov r3, #24
ldr r1, [r7]
lsr r1, r1, r3
ldr r3, =0x14000000
cmp r1, r2
beq kernel_memchunkhax_oldlinearmem

ldr r3, =0x30000000

kernel_memchunkhax_oldlinearmem:
add r0, r0, r3 @ r0 = userland vaddr for the above next-ptr.
str r0, [r7] @ Update the current memchunk ptr.
b kernel_memchunkhax_copyoriginalchunk

kernel_memchunkhax_writenewhdr:
@ Overwrite the current memchunk structure for the current memregion with the above fake structure.
mov r0, r5 @ src-addr
ldr r1, [r7] @ dst-addr
mov r2, #0x10 @ size

mov r3, #8
str r3, [sp, #12] @ flags
mov r3, #0 @ width0
str r3, [sp, #0] @ height0
str r3, [sp, #4] @ width1
str r3, [sp, #8] @ height1

blx gxlow_cmd4

blx svcSleepThread_delay1second

@ This triggers the SVC-handler memwrite mentioned above.
mov r0, #3 @ operation
mov r4, #3 @ permissions

ldr r1, =0x0FF00000 @ addr0
mov r2, #0 @ addr1
ldr r3, =0x1000 @ size
blx svcControlMemory
ldr r1, =0x70707070
bl checkfail_thumb

blx svcSleepThread_delay1second

@ Free the memory that was allocated.
mov r0, #1 @ operation
mov r4, #0 @ permissions

ldr r1, =0x0FF00000 @ addr0
mov r2, #0 @ addr1
ldr r3, =0x1000 @ size
blx svcControlMemory
ldr r1, =0x90909090
bl checkfail_thumb

blx svcSleepThread_delay1second

@ Restore the memchunk structure.
mov r0, r6 @ src-addr
ldr r1, [r7] @ dst-addr
mov r2, #0x10 @ size

mov r3, #8
str r3, [sp, #12] @ flags
mov r3, #0 @ width0
str r3, [sp, #0] @ height0
str r3, [sp, #4] @ width1
str r3, [sp, #8] @ height1

blx gxlow_cmd4

blx svcSleepThread_delay1second

add sp, sp, #32
pop {r4, r5, r6, pc}
.pool

getsrvhandle_allservices: @ Get a srv handle which has access to all services. r0 = out srv handle*
push {r0, r4, r5, r6, lr}
sub sp, sp, #0x20

mov r0, sp
ldr r1, =0xffff8001
blx svcGetProcessId

bl throw_fatalerr_errcheck

mov r4, #0
ldr r5, [sp, #0]
mov r6, #0

adr r0, kernelmode_searchval_overwrite @ r4=address(0=cur kprocess), r5=searchval, r6=val to write
blx svc7b @ Overwrite kprocess PID with 0.

mov r4, r3
ldr r5, [sp, #0]

ldr r0, [sp, #0x20]
bl srv_init
bl throw_fatalerr_errcheck

adr r0, kernelmode_writeval @ r4=addr, r5=u32val
blx svc7b @ Restore the original PID.

add sp, sp, #0x24
pop {r4, r5, r6, pc}
.pool

code_endcrash:
bl fail_thumb

.arm

kernelmode_code_getadr:
adr r0, kernelmode_code
bx lr

kernelmode_getlcdregbase:
ldr r1, =0x1FF80002
ldrb r1, [r1]
ldr r0, =0xFFFD6000

cmp r1, #44
blt kernelmode_getlcdregbase_end

ldr r0, =0xFFFC4000

cmp r1, #46
blt kernelmode_getlcdregbase_end @ <v9.0

ldr r2, =0xff8
ldr r2, [r7, r2]
cmp r2, #0
bne kernelmode_getlcdregbase_end @ branch for new3ds

ldr r0, =0xfffc8000

kernelmode_getlcdregbase_end:
bx lr
.pool

kernelmode_searchval_overwrite: @ r4=kprocess, r5=searchval, r6=val to write. out r3 = overwritten addr.
cpsid i @ disable IRQs
push {r4, r5, r6}

cmp r4, #0
bne kernelmode_searchval_overwrite_lp
ldr r4, =0xffff9004
ldr r4, [r4]

kernelmode_searchval_overwrite_lp:
ldr r0, [r4]
cmp r0, r5
addne r4, r4, #4
bne kernelmode_searchval_overwrite_lp

str r6, [r4]
mov r3, r4
pop {r4, r5, r6}
bx lr
.pool

kernelmode_writeval: @ r4=addr, r5=u32val
cpsid i @ disable IRQs
str r5, [r4]
bx lr

kernelmode_code:
cpsid i @ disable IRQs
push {r4, r5, r6, lr}
mov r4, lr

bl kernelmode_getlcdregbase
mov r6, r0
ldr r1, =0x204
add r0, r6, r1

ldr r1, =0x1000000
str r1, [r0] @ Set main-screen colorfill reg so that black is displayed.

mov r0, r4
blx write_kernel_patches

ldr r0, =0x204 @ Set main/sub screen colorfill regs so that blue is displayed.
ldr r1, =0xA04
ldr r2, =0x01FF0000
add r0, r0, r6
add r1, r1, r6
str r2, [r0]
str r2, [r1]

pop {r4, r5, r6}
pop {r0}
mov lr, r0
//cpsie i @ enable IRQs (don't re-enable IRQs since the svc-handler will just disable IRQs after the SVC returns)
bx lr
.pool

parse_branch: @ r0 = addr of branch instruction, r1 = branch instruction u32 value
cmp r1, #0
ldreq r1, [r0]
lsl r1, r1, #8
lsr r1, r1, #8
tst r1, #0x800000
moveq r2, #0
ldrne r2, =0xff000000
orr r2, r2, r1
lsl r2, r2, #2
add r0, r0, #8
add r0, r0, r2
bx lr
.pool

generate_branch: @ r0 = addr of branch instruction, r1 = addr to branch to, r2 = 0 for regular branch, non-zero for bl. (ARM-mode)
add r0, r0, #8
sub r1, r1, r0
asr r1, r1, #2
tst r1, #0x20000000
lsl r1, r1, #9
lsr r1, r1, #9
orrne r1, #0x800000
cmp r2, #0
orreq r1, #0xea000000
orrne r1, #0xeb000000
mov r0, r1
bx lr
.pool

.thumb

write_kernel_patches:
push {r4, r5, r6, r7, lr}
sub sp, sp, #0x20

mov r6, r0

ldr r4, =0xEFF80000 @ Kernel vaddr for the RW- AXI-WRAM memory.

ldr r3, =0x1000
mov r1, r7
add r1, r1, r3
sub r1, r1, #4
ldrb r0, [r1]

ldr r1, =0xF0000000
cmp r0, #44
blt write_kernel_patches_L1
ldr r4, =0xDFF80000 @ Use these addrs when running on a sysver >=v8.0 FIRM.
ldr r1, =0xE0000000

write_kernel_patches_L1:
str r1, [sp, #4]

lsr r6, r6, #12
lsl r6, r6, #12
mov r0, r6
blx kernel_vaddr2physaddr @ Convert LR of kernelmode_code with low 12-bits of the vaddr, to physaddr.

ldr r3, =0x1FF80000
sub r0, r0, r3 @ r0 = offset of the above physaddr relative to axiwram.
sub r6, r6, r0
mov r5, r6 @ r5/r6 = vaddr of kernel .text.

blx arm11kernel_stubcode_end_getadr
mov r1, r0
adr r0, arm11kernel_stubcode @ Copy the code at arm11kernel_stubcode - arm11kernel_stubcode_end to AXIWRAM+0x1000.
ldr r2, =0xffff0d00
str r2, [sp, #0x1c]
ldr r2, =0x74d00
add r2, r2, r4
str r2, [sp, #0x18]

ldr r3, [r2]
ldr r6, [r0]
cmp r3, r6
bne write_kernel_patches_stubcpylp
bl write_kernel_patches_end @ Return from this code when this haxx already wrote to AXIWRAM, when this haxx was used on the running system more than once.

write_kernel_patches_stubcpylp:
ldr r3, [r0]
str r3, [r2]
add r0, r0, #4
add r2, r2, #4
cmp r0, r1
blt write_kernel_patches_stubcpylp

ldr r0, [r7, #0x5c]
ldr r1, =0x300
cmp r0, #0
beq write_kernel_patches_locatecode_memalloc0_start
cmp r0, r1
beq write_kernel_patches_locatecode_memalloc0_start

ldr r0, =0xE85F6000 @ When running under a system-applet, store the arm9bin buffer under VRAM instead of kernel FCRAM heap.

ldr r1, =0x1FF80002
ldrb r1, [r1]
cmp r1, #44
blt write_kernel_patches_memallocdone
ldr r0, =0xD85F6000
b write_kernel_patches_memallocdone

write_kernel_patches_locatecode_memalloc0_start:
mov r0, #0
ldr r1, =0x80000
ldr r2, =0xe3a01030
mov r6, #0xf

write_kernel_patches_locatecode_memalloc0:
ldr r3, [r5, r0]
bic r3, r3, r6
cmp r2, r3
bne write_kernel_patches_locatecode_memalloc0_lpnext

ldr r6, =0xe3a02000 @ Check that the above located instruction has the following instruction right before it: "mov r2, #0".
sub r0, r0, #4
ldr r3, [r5, r0]
add r0, r0, #4
cmp r3, r6
beq write_kernel_patches_locatecode_memalloc0_end

mov r6, #0xf

write_kernel_patches_locatecode_memalloc0_lpnext:
add r0, r0, #4
cmp r0, r1
blt write_kernel_patches_locatecode_memalloc0

ldr r1, =0x4040FF00
bl fail_thumb

write_kernel_patches_locatecode_memalloc0_end:
ldr r6, [sp, #4]
add r0, r0, r5
add r0, r0, #4
mov r1, #0
blx parse_branch
str r0, [sp]

/*ldr r0, =0x04000000
ldr r1, =0x02C00000
ldr r2, =0x01400000*/

blx appmemregion_sizetable_getadr
ldr r1, =0x1FF80030 @ APPMEMTYPE
ldr r1, [r1]
lsl r1, r1, #2
ldr r0, [r0, r1]

ldr r3, =0x1ff80040
ldr r1, [r3, #4]
ldr r2, [r3, #8]

str r0, [sp, #8]
str r1, [sp, #12]
str r2, [sp, #16]
add r0, r0, r1
str r0, [sp, #20]

mov r0, #0
ldr r1, =0x80000

write_kernel_patches_locatecode_memalloc1:
ldr r3, [r4, r0]
ldr r2, [sp, #4]
cmp r2, r3
bne write_kernel_patches_locatecode_memalloc1_cont

mov r3, #0x04
add r3, r3, r4
add r3, r3, r0
ldr r3, [r3]
ldr r2, [sp, #8]
cmp r2, r3
bne write_kernel_patches_locatecode_memalloc1_cont

mov r3, #0x10
add r3, r3, r4
add r3, r3, r0
ldr r3, [r3]
ldr r2, [sp, #8]
add r2, r2, r6
cmp r2, r3
bne write_kernel_patches_locatecode_memalloc1_cont

mov r3, #0x14
add r3, r3, r4
add r3, r3, r0
ldr r3, [r3]
ldr r2, [sp, #12]
cmp r2, r3
bne write_kernel_patches_locatecode_memalloc1_cont

ldr r2, [sp, #8]
ldr r3, [sp, #12]
add r2, r2, r3
mov r3, #0x20
add r3, r3, r4
add r3, r3, r0
ldr r3, [r3]
add r2, r2, r6
cmp r2, r3
bne write_kernel_patches_locatecode_memalloc1_cont

mov r3, #0x24
add r3, r3, r4
add r3, r3, r0
ldr r3, [r3]
ldr r2, [sp, #16]
cmp r2, r3
beq write_kernel_patches_locatecode_memalloc1_end

write_kernel_patches_locatecode_memalloc1_cont:
add r0, r0, #4
cmp r0, r1
blt write_kernel_patches_locatecode_memalloc1

ldr r1, =0x4040FF01
bl fail_thumb

write_kernel_patches_locatecode_memalloc1_end:
sub r0, r0, #8
add r0, r0, r4

@ldr r0, =0xfff7f894
mov r1, #0xa
mov r2, #0
ldr r3, =0x80000300
ldr r6, [sp]
@ldr r6, =0xfff68298 @=0xfff68148
blx r6 @ Allocate 0xa-pages in the APPLICATION memregion.

cmp r0, #0
bne write_kernel_patches_memallocdone

ldr r1, =0x4040FF02
bl fail_thumb

write_kernel_patches_memallocdone:
mov r6, r0
blx arm9code_codeblkptr_getadr
mov r2, r0
mov r0, r6

adr r1, arm11kernel_stubcode
sub r2, r2, r1
ldr r3, =0x1000
add r0, r0, r3
ldr r3, [sp, #0x18]
add r2, r2, r3
str r0, [r2]

ldr r1, [sp, #4]
str r1, [r2, #4]

ldr r3, =0x1000
mov r1, r7
add r1, r1, r3
ldr r2, =0x8000

write_kernel_patches_codecpylp: @ Copy the arm9code loaded from SD to the above allocbuf+0x1000.
ldr r3, [r1]
str r3, [r0]
add r1, r1, #4
add r0, r0, #4
sub r2, r2, #4
cmp r2, #0
bge write_kernel_patches_codecpylp

@ Patch the code eventually executed via svc7c type0 which copies the firmlaunch-params kernel buffer to FCRAM+0, so that it clears the 0x1000-bytes @ FCRAM+0 instead.
/*ldr r2, =0xFFF70000
ldr r3, =0xEFFDF000
ldr r0, =0xfff76b04
mov r1, r0
sub r1, r1, r2
add r1, r1, r3*/

mov r0, #0
ldr r1, =0x80000
ldr r2, =0x00044836

write_kernel_patches_locatecode0:
ldr r3, [r4, r0]
cmp r2, r3
beq write_kernel_patches_locatecode0_end

add r0, r0, #4
cmp r0, r1
blt write_kernel_patches_locatecode0

ldr r1, =0x4040FF03
bl fail_thumb

write_kernel_patches_locatecode0_end:
ldr r2, =0xe3a0020f @ "mov r0, #0xf0000000"
ldr r3, =0x1000
mov r1, r7
add r1, r1, r3
sub r1, r1, #4
ldrb r1, [r1]
cmp r1, #44
blt write_kernel_patches_locatecode1

ldr r2, =0xe3a0020e @ "mov r0, #0xe0000000"

write_kernel_patches_locatecode1:
ldr r3, [r4, r0]
cmp r2, r3
beq write_kernel_patches_locatecode1_end

sub r0, r0, #4
cmp r0, #0
bge write_kernel_patches_locatecode1

ldr r1, =0x4040FF04
bl fail_thumb

write_kernel_patches_locatecode1_end:
mov r1, r4
add r1, r1, r0
sub r1, r1, #4

/*mov r2, #0
str r2, [r1, #0] @ Overwrite the following instruction with val0: "ldr r1, [r4, #0x28]".

ldr r2, [r1, #8] @ Change the register used for "mov r2, #0x1000" to r1.
ldr r3, =0xf000
bic r2, r2, r3
ldr r3, =0x1000
orr r2, r2, r3
str r2, [r1, #8]

mov r6, r1
add r6, r6, #0xc

adr r1, arm11kernel_stubcode_memclear
adr r3, arm11kernel_stubcode
sub r1, r1, r3
ldr r3, =0x1000
add r3, r3, r5
add r1, r1, r3

add r0, r0, #0xc
mov r2, #1
blx generate_branch
str r0, [r6] @ Patch the "bl memcpy32" instruction so that it calls arm11kernel_stubcode_memclear instead.*/

mov r6, r1

adr r1, arm11kernel_stubcode_memclear
adr r3, arm11kernel_stubcode
sub r1, r1, r3
ldr r3, [sp, #0x1c]
add r1, r1, r3

ldr r2, =0xe51f3000 @ "ldr r3, [pc, #-0]"
str r2, [r6, #0]
ldr r2, =0xe12fff33 @ "blx r3"
str r2, [r6, #4]
str r1, [r6, #8]

/*ldr r0, =0xfff64b04
mov r1, r0
sub r1, r1, r5
add r1, r1, r4
ldr r2, =0x1000
add r2, r2, r5*/

mov r0, #0
ldr r1, =0x80000
ldr r2, =0x00040138

write_kernel_patches_locatecode2: @ Locate the FIRM tidhigh 0x00040138 word in the svc7c handler .pool.
ldr r3, [r4, r0]
cmp r2, r3
beq write_kernel_patches_locatecode2_end

add r0, r0, #4
cmp r0, r1
blt write_kernel_patches_locatecode2

ldr r1, =0x4040FF05
bl fail_thumb

write_kernel_patches_locatecode2_end: @ Locate the ldrcc instruction used for the svc7c switch statement, used for the input type paramater.
ldr r2, =0x379ff107 @ "ldrcc pc, [pc, *]"
ldr r6, =0xFC5FF000
and r2, r2, r6

write_kernel_patches_locatecode3:
ldr r3, [r4, r0]
and r3, r3, r6
cmp r2, r3
beq write_kernel_patches_locatecode3_end

sub r0, r0, #4
cmp r0, #0
bge write_kernel_patches_locatecode3

ldr r1, =0x4040FF06
bl fail_thumb

write_kernel_patches_locatecode3_end:
mov r1, r4
add r1, r1, r0
add r1, r1, #8

adr r0, arm11kernel_stubcode_svc7ctype0_originaladdr
adr r3, arm11kernel_stubcode
sub r0, r0, r3
ldr r3, [sp, #0x18]
add r0, r0, r3
mov r6, r0

ldr r2, [sp, #0x1c]

ldr r0, [r1]
str r0, [r6] @ Write the jump-addr which will be overwritten by the following instruction, to arm11kernel_stubcode_svc7ctype0_originaladdr.
str r2, [r1] @ Patch the jump-addr for svc7c type0 in the switch-statement jump-table, so that it jumps to arm11kernel_stubcode+0 instead.

@ The following patches the code which copies the firm-stub for core0, so that it copies the below stub there instead.
arm11kernel_firmstubinit_start:
/*ldr r0, =0xFFFF0000
ldr r1, =0xEFFF4000
ldr r2, =0xffff0978
sub r2, r2, r0
add r2, r2, r1*/

mov r0, #0
ldr r1, =0x80000
ldr r2, =0x1ffffc00

write_kernel_patches_locatecode4:
ldr r3, [r4, r0]
cmp r2, r3
beq write_kernel_patches_locatecode4_end

add r0, r0, #4
cmp r0, r1
blt write_kernel_patches_locatecode4

ldr r1, =0x4040FF07
bl fail_thumb

write_kernel_patches_locatecode4_end:
mov r2, r4
add r2, r2, r0
sub r2, r2, #0x40

ldr r3, =0xe59f0010 @ Patch the "add rX, pc, #<offset>" instructions with the below instructions.
str r3, [r2, #0] @ "ldr r0, [pc, #0x10]"
ldr r3, =0xe59f1010
str r3, [r2, #4] @ "ldr r1, [pc, #0x10]"
add r2, r2, #0x18

adr r6, firmstub_core0
adr r3, arm11kernel_stubcode
sub r6, r6, r3

ldr r3, [sp, #0x18] @ Set the source-stub start/end addresses used by the above instructions.
lsl r3, r3, #4
lsr r3, r3, #4
mov r1, #1
lsl r1, r1, #28
orr r3, r3, r1
add r3, r3, r6
mov r1, r3
str r3, [r2, #0]

adr r0, firmstub_core0_end
adr r3, firmstub_core0
sub r0, r0, r3

mov r3, r1
add r3, r3, r0
str r3, [r2, #4]

ldr r3, [sp, #0x18] @ Write the physical addresses of the below arm9code start/end in the arm11kernel_stubcode region, to AXIWRAM+0x1004.
lsl r3, r3, #4
lsr r3, r3, #4
mov r1, #1
lsl r1, r1, #28
orr r3, r3, r1
mov r6, r3

ldr r0, [sp, #0x18]
add r0, r0, #4
adr r2, arm9code_start
adr r3, arm11kernel_stubcode
sub r2, r2, r3
add r2, r2, r6
str r2, [r0]

adr r2, arm9code_end
adr r3, arm11kernel_stubcode
sub r2, r2, r3
add r2, r2, r6
str r2, [r0, #4]

ldr r0, [sp, #0x18]
adr r2, arm11kernel_stubcode
adr r3, arm11kernel_stubcode_new3dsflag
sub r3, r3, r2
add r3, r3, r0
mov r1, r7
ldr r2, =0x1000
add r1, r1, r2
sub r1, r1, #8
ldr r1, [r1]
str r1, [r3]

#ifdef DUMP_AXIWRAM_AFTERPATCHES
ldr r0, =0xDFF80000
ldr r1, =DUMPMEMGPU_ADR
ldr r2, =0x80000

kernelmode_patchfs_L0_cpy:
ldr r3, [r0]
str r3, [r1]
add r0, r0, #4
add r1, r1, #4
sub r2, r2, #4
cmp r2, #0
bgt kernelmode_patchfs_L0_cpy
#endif

write_kernel_patches_end:
blx kernelpatchesfinish_cachestuff

add sp, sp, #0x20
pop {r4, r5, r6, r7, pc}
.pool

/*kernelmode_code_stage2:
cpsid i @ disable IRQs
mov r0, sp
ldr r1, =0x18B42000
mov sp, r1
push {r0}
push {lr}

mov r1, r3 @ sm module process-handle
ldr r2, =0xfff67d9c
ldr r0, =0xffff9004
ldr r3, =0xcc
ldr r0, [r0]
add r0, r0, r3
blx r2 @ gethandle_objptr @ Get the sm module KProcess ptr.
mov r3, #1
cmp r0, #0
beq kernelmode_code_stage2_end

add r0, r0, #0x54 @ Get the physical address of the below vaddr in sm module, then patch the code there so that the service-access-control check function always returns success.
ldr r1, =0x10182c
ldr r2, =0xfff6b810
blx r2 @ KProcessmem_getphysicaladdr
mov r3, #2
cmp r0, #0
beq kernelmode_code_stage2_end

ldr r1, =0xD0000000 @ Convert the physical addr to kernel FCRAM vaddr.
add r0, r0, r1

mov r2, #1 @ Write the patch mentioned above.
ldr r1, [r0]
orr r1, r1, r2
str r1, [r0]

blx kernelpatchesfinish_cachestuff

mov r3, #0

kernelmode_code_stage2_end:
pop {r0}
mov lr, r0
pop {r0}
mov sp, r0
cpsie i @ enable IRQs
bx lr
.pool*/

.arm

.type arm9code_codeblkptr_getadr, %function
arm9code_codeblkptr_getadr:
adr r0, arm9code_codeblkptr
bx lr

arm11kernel_stubcode:
b arm11kernel_svc7c_type0hook

.word 0 @ arm9code start addr, used by firmstub_core0
.word 0 @ arm9code end addr, used by firmstub_core0

arm11kernel_stubcode_svc7ctype0_originaladdr:
.word 0

arm11kernel_stubcode_new3dsflag:
.word 0

arm11kernel_svc7c_type0hook: @ Hook for svc7c type0, via patching the jump-table used by the switch-statement. r5 is the FIRM programID-low.
lsr r5, r5, #16
lsl r5, r5, #16
orr r5, r5, #2 @ Overwrite the low 16-bits of the FIRM programID-low with 0x2, for NATIVE_FIRM.
ldr pc, arm11kernel_stubcode_svc7ctype0_originaladdr
.pool

arm11kernel_stubcode_memclear: @ This is called by the patched kernel code which writes to the FCRAM+0 FIRM paramaters buffer.
ldr r0, arm9code_kernelfcramvaddr_base
mov r1, #0x1000
mov r2, #0

arm11kernel_stubcode_memclearlp:
str r2, [r0], #4
subs r1, r1, #4
bgt arm11kernel_stubcode_memclearlp

add lr, lr, #4
bx lr

firmstub_core0: @ This is the final block of code executed on ARM11 core0 before jumping to the kernel entrypoint. This code is used to exploit an arm9 vuln during FIRM launch: the only FIRM header block the arm9 uses is the one stored in FCRAM @ 0x24000000(also used for the RSA signature-check). This is exploited with this ARM11 stub.
@ Note that the MMU is disabled at this point.
blx firmstub_core0_thumbstart
.thumb
firmstub_core0_thumbstart:
ldr r1, =0x1FFF4D04 @ Copy the arm9code to FCRAM+0x1000.
ldr r2, [r1, #0] @ arm9code start
ldr r3, [r1, #4] @ arm9code end
ldr r1, =0x20001000

firmstub_core0_cpycode:
ldr r0, [r2]
str r0, [r1]
add r2, r2, #4
add r1, r1, #4
cmp r2, r3
blt firmstub_core0_cpycode

#ifdef DUMP_ARM11BOOTROM
mov r2, #0
ldr r1, =0x18600000
ldr r3, =0x10000
sub r1, r1, r3
firmstub_core0_dumplp:
ldr r0, [r2], #4
str r0, [r1], #4
cmp r2, r3
blt firmstub_core0_dumplp
#endif

firmstub_core0_begin:
ldr r3, =0x1ffffffc
mov r0, #0
str r0, [r3]

ldr r3, =0x1FF80000

mov r2, #0
str r2, [r3]

ldr r1, =0x10163008
ldr r2, =0x00044846
str r2, [r1] @ Send the last PXI word to the arm9.

mov r2, #0
firmstub_core0_loadwait: @ Wait for the first word of the arm11kernel section to get loaded, which is after the FIRM RSA signature check.
ldr r1, [r3]
cmp r1, r2
beq firmstub_core0_loadwait

ldr r1, =(0x4d524946+0x10)
sub r1, r1, #0x10
ldr r0, =0x24000000 @ Check that the plaintext FIRM header is really stored at 0x24000000. When it isn't, skip the FIRM header code below.
ldr r3, [r0]

cmp r3, r1
bne firmstub_core0_entrypointwaitbegin

ldr r1, =0x20001000
ldr r3, [r0, #0xc]
str r3, [r1, #4] @ Write the original arm9 FIRM entrypoint to arm9code+4.
str r1, [r0, #0xc] @ Overwrite the arm9 FIRM entrypoint(in the FIRM header) with the arm9code address.

firmstub_core0_entrypointwaitbegin:
ldr r3, =0x1ffffffc
firmstub_core0_entrypointwaitlp: @ Wait for the arm9 to set the arm11 FIRM entrypoint ptr, the arm9 sets this right before executing a "pop" instruction followed by jumping to the arm9 FIRM entrypoint.
ldr r0, [r3]
cmp r0, #0
beq firmstub_core0_entrypointwaitlp
bx r0
.pool

.arm

firmstub_core0_end:
.word 0

@ This arm9 code is executed by hooking the FIRM arm9 entrypoint ptr: the FIRM arm9 entrypoint is set to the address of arm9code_start, and the original entrypoint is written to arm9code_firmentrypoint.
@ This code is located at FCRAM+0x1000, therefore this code will be cleared by the arm11-kernel when it clears the entire FCRAM, when this jumps to the original arm9 entrypoint.
@ Registers don't have to be saved here since the kernel will clear them once this jumps to the entrypoint anyway.
arm9code_start:
b arm9code_codestart

arm9code_firmentrypoint:
.word 0

arm9code_codeblkptr:
.word 0 @ ARM11-kernel vaddr ptr to the memory block for the arm9code.

arm9code_kernelfcramvaddr_base:
.word 0

arm9code_codestart:
ldr r0, arm9code_codeblkptr @ Validate the arm9code_codeblkptr address + convert it to physmem.
cmp r0, #0
beq arm9code_code_end

ldr r2, arm9code_kernelfcramvaddr_base
lsr r1, r0, #28
lsr r2, r2, #28
cmp r1, r2
beq arm9code_code_convframeaddr

lsl r1, r0, #4 @ VRAM
lsr r1, r1, #4
mov r2, #1
lsl r2, r2, #28
orr r1, r1, r2
mov r0, r1
b arm9code_code_loadstart

arm9code_code_convframeaddr:
ldr r1, arm9code_kernelfcramvaddr_base
ldr r2, =0x20000000
sub r1, r1, r2
sub r0, r0, r1 @ Convert kernel FCRAM vaddr ptr to physical.

arm9code_code_loadstart:
ldr r3, [r0]
ldr r1, =0x39444f43
cmp r1, r3
bne arm9code_code_end
ldr r2, [r0, #4] @ Size
ldr r1, [r0, #8] @ loadaddr
add r0, r0, #12 @ src
add r2, r2, r0
mov r4, r1

arm9code_cpylp:
ldr r3, [r0], #4
str r3, [r1], #4
cmp r0, r2
blt arm9code_cpylp

ldr lr, arm9code_firmentrypoint
bx r4

arm9code_code_end:
ldr pc, arm9code_firmentrypoint

.pool

.thumb

arm9fail:
ldr r0, =0x58584148
blx r0
.pool

arm9code_end:
.word 0

.arm
arm11kernel_stubcode_end:
.word 0

arm11kernel_stubcode_end_getadr:
sub r0, pc, #12
bx lr

.thumb

aptipc_reboot:
push {r0, r4, r5, r6, lr}
sub sp, sp, #12
str r2, [sp, #0]
str r3, [sp, #4]
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x00490180
str r1, [r4]
ldr r2, [sp, #0]
ldr r3, [sp, #4]
str r2, [r4, #4]
str r3, [r4, #8] @ Application titleID/programID.
mov r2, #0
ldr r3, [sp, #32]
str r2, [r4, #12] @ u8 mediatype
str r2, [r4, #16] @ reserved u32 in titleinfo structure
str r2, [r4, #20] @ u8 value
str r3, [r4, #24] @ FIRM titleID/programID-low

ldr r0, [sp, #12]
ldr r0, [r0]
blx svcSendSyncRequest

mov r5, r0
cmp r5, #0
bne aptipc_reboot_end
ldr r5, [r4, #4]

aptipc_reboot_end:
mov r0, r5
add sp, sp, #12
add sp, sp, #4
pop {r4, r5, r6, pc}
.pool

nss_LaunchFIRM: @ r0=handle*, r1/r2=app programID
push {r0, r1, r2, r4, lr}
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x000100C0
ldr r2, [sp, #4]
ldr r3, [sp, #8]
str r1, [r4, #0]
str r2, [r4, #4]
str r3, [r4, #8]
mov r1, #0
str r1, [r4, #12]

ldr r0, [sp, #0]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne nss_LaunchFIRM_end
ldr r0, [r4, #4]

nss_LaunchFIRM_end:
add sp, sp, #12
pop {r4, pc}
.pool

nss_LaunchApplicationFIRM: @ r0=handle*, r1/r2=app programID
push {r0, r1, r2, r4, lr}
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x000500C0
ldr r2, [sp, #4]
ldr r3, [sp, #8]
str r1, [r4, #0]
str r2, [r4, #4]
str r3, [r4, #8]
mov r1, #2
str r1, [r4, #12]

ldr r0, [sp, #0]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne nss_LaunchApplicationFIRM_end
ldr r0, [r4, #4]

nss_LaunchApplicationFIRM_end:
add sp, sp, #12
pop {r4, pc}
.pool

APT_OpenSession: @ r0=srv handle*, r1=out apt handle*
push {r0, r1, lr}
blx get_aptu_servname
mov r2, r0
ldr r0, [sp, #0]
ldr r1, [sp, #4]
bl srv_GetServiceHandle
ldr r1, =0xd8e06406
cmp r0, r1
beq APT_OpenSession_apta
bl throw_fatalerr_errcheck
b APT_OpenSession_end

APT_OpenSession_apta:
blx get_apta_servname
mov r2, r0
ldr r0, [sp, #0]
ldr r1, [sp, #4]
bl srv_GetServiceHandle
bl throw_fatalerr_errcheck

APT_OpenSession_end:
add sp, sp, #8
pop {pc}

APT_CloseSession: @ r0=apt handle*
push {lr}
ldr r0, [r0]
blx svcCloseHandle
pop {pc}

APT_IsRegistered: @ inr0=handle*, inr1=NS_APPID appID, inr2=u8* out
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x00090040
str r5, [r4, #0]
ldr r1, [sp, #4]
str r1, [r4, #4]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APT_IsRegistered_end
ldr r0, [r4, #4]
cmp r0, #0
bne APT_IsRegistered_end

ldrb r1, [r4, #8]
ldr r2, [sp, #8]
strb r1, [r2]

APT_IsRegistered_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

APT_ReceiveParameter: @ r0=apt handle*, r1=appID, r2=parambuf*, r3=maxparambufsize, insp0=handle*
push {r0, r1, r2, r3, r4, r5, lr}
sub sp, sp, #8
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #8]

ldr r3, =0x100
add r3, r3, r4
ldr r2, [r3, #0]
str r2, [sp, #0]
ldr r2, [r3, #4]
str r2, [sp, #4]

ldr r5, =0x000D0080
str r5, [r4, #0]
ldr r1, [sp, #12]
str r1, [r4, #4]
ldr r1, [sp, #20]
str r1, [r4, #8]
mov r2, #2
lsl r1, r1, #14
orr r1, r1, r2
str r1, [r3, #0]
ldr r1, [sp, #16]
str r1, [r3, #4]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APT_ReceiveParameter_end
ldr r0, [r4, #4]
ldr r1, [sp, #36]
cmp r1, #0
beq APT_ReceiveParameter_end
ldr r2, [r4, #24]
str r2, [r1]

APT_ReceiveParameter_end:
ldr r3, =0x100
add r3, r3, r4
ldr r2, [sp, #0]
str r2, [r3, #0]
ldr r2, [sp, #4]
str r2, [r3, #4]

add sp, sp, #24
pop {r4, r5, pc}
.pool

APT_PreloadLibraryApplet: @ inr0=handle*, inr1=NS_APPID appID
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x00160040
str r5, [r4, #0]
ldr r1, [sp, #4]
str r1, [r4, #4]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APT_PreloadLibraryApplet_end
ldr r0, [r4, #4]

APT_PreloadLibraryApplet_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

APT_FinishPreloadingLibraryApplet: @ inr0=handle*, inr1=NS_APPID appID
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x00170040
str r5, [r4, #0]
ldr r1, [sp, #4]
str r1, [r4, #4]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APT_FinishPreloadingLibraryApplet_end
ldr r0, [r4, #4]

APT_FinishPreloadingLibraryApplet_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

#ifndef DISABLE_EXITLAUNCHTITLE_TYPE1
APT_PrepareToStartSystemApplet: @ inr0=handle*, inr1=NS_APPID appID
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x00190040
str r5, [r4, #0]
ldr r1, [sp, #4]
str r1, [r4, #4]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APT_PrepareToStartSystemApplet_end
ldr r0, [r4, #4]

APT_PrepareToStartSystemApplet_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

APT_StartSystemApplet: @ inr0=handle*, inr1=appid, inr2=inhandle, inr3=u32 bufsize, insp0=u32* buf
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x001F0084
str r5, [r4, #0]
ldr r1, [sp, #4] @ appid
str r1, [r4, #4]
mov r1, #0
str r1, [r4, #12]
ldr r1, [sp, #8] @ inhandle
str r1, [r4, #16]
ldr r1, [sp, #12] @ bufsize
str r1, [r4, #8]
mov r3, #2
lsl r1, r1, #14
orr r1, r1, r3
str r1, [r4, #20]
ldr r1, [sp, #28] @ buf0
str r1, [r4, #24]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APT_StartSystemApplet_end
ldr r0, [r4, #4]

APT_StartSystemApplet_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool
#endif

APT_PrepareToDoApplicationJump: @ inr0=handle*, inr1=u32 tidLow, inr2=u32 tidHigh, inr3=u8 mediatype, insp0=u8 flags
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x00310100
str r5, [r4, #0]
ldr r1, [sp, #28] @ flags
str r1, [r4, #4]
ldr r1, [sp, #4] @ TID
str r1, [r4, #8]
ldr r1, [sp, #8]
str r1, [r4, #12]
ldr r1, [sp, #12] @ mediatype
str r1, [r4, #16]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APT_PrepareToDoApplicationJump_end
ldr r0, [r4, #4]

APT_PrepareToDoApplicationJump_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

APT_DoApplicationJump: @ inr0=handle*, inr1=u32 size0, inr2=u32 size1, inr3=u32* buf0, insp0=u32* buf1
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x00320084
str r5, [r4, #0]
ldr r1, [sp, #4] @ size0
str r1, [r4, #4]
ldr r2, [sp, #8] @ size1
str r2, [r4, #8]
mov r3, #2
lsl r1, r1, #14
orr r1, r1, r3
str r1, [r4, #12]
ldr r3, =0x802
lsl r2, r2, #14
orr r2, r2, r3
str r2, [r4, #20]
ldr r1, [sp, #12] @ buf0
str r1, [r4, #16]
ldr r1, [sp, #28] @ buf1
str r1, [r4, #24]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APT_DoApplicationJump_end
ldr r0, [r4, #4]

APT_DoApplicationJump_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

#ifndef DISABLE_EXITLAUNCHTITLE_TYPE1
APT_StoreSysMenuArg: @ r0=apt handle*, r1=buf*, r2=bufsize
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x00370042
str r5, [r4, #0]
ldr r1, [sp, #8]
str r1, [r4, #4]
mov r2, #2
lsl r1, r1, #14
orr r1, r1, r2
str r1, [r4, #8]
ldr r1, [sp, #4]
str r1, [r4, #12]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APT_StoreSysMenuArg_end
ldr r0, [r4, #4]

APT_StoreSysMenuArg_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool
#endif

APT_ReplySleepQuery: @ inr0=handle*, inr1=NS_APPID appID, inr2=u32 a
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x3E0080
str r5, [r4, #0]
ldr r1, [sp, #4]
str r1, [r4, #4]
ldr r1, [sp, #8]
str r1, [r4, #8]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APT_ReplySleepQuery_end
ldr r0, [r4, #4]

APT_ReplySleepQuery_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

APT_AppletUtility: @ inr0=handle*, inr1=u32* out, inr2=u32 a, inr3=u32 size1, insp0=u8* buf1, insp4=u32 size2, insp8=u8* buf2
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x004B00C2
str r5, [r4, #0]
ldr r1, [sp, #8] @ a
str r1, [r4, #4]
ldr r1, [sp, #12] @ size1
str r1, [r4, #8]
ldr r1, [sp, #32] @ size2
str r1, [r4, #12]
mov r2, #2
lsl r1, r1, #14
orr r1, r1, r2
mov r3, r4
ldr r3, =0x100
add r3, r3, r4
str r1, [r3, #0]
ldr r1, [sp, #36]
str r1, [r3, #4] @ buf2

ldr r1, [sp, #12] @ size1
ldr r2, =0x402
lsl r1, r1, #14
orr r1, r1, r2
str r1, [r4, #16]
ldr r1, [sp, #28] @ buf1
str r1, [r4, #20]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APT_AppletUtility_end
ldr r0, [r4, #4]
cmp r0, #0
beq APT_AppletUtility_end

ldr r1, [sp, #4]
cmp r1, #0
beq APT_AppletUtility_end
ldr r2, [r4, #8]
str r2, [r1]

APT_AppletUtility_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

APTipc_CheckNew3DS: @ inr0=handle*, inr1=u8* out
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x01020000
str r5, [r4, #0]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne APTipc_CheckNew3DS_end
ldr r0, [r4, #4]
cmp r0, #0
bne APTipc_CheckNew3DS_end

ldrb r1, [r4, #8]
ldr r2, [sp, #4]
strb r1, [r2]

APTipc_CheckNew3DS_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

APT_CheckNew3DS:
push {r4, lr}
sub sp, sp, #12

mov r4, #0

add r0, sp, #0
bl srv_init
bl throw_fatalerr_errcheck

add r0, sp, #0
add r1, sp, #4
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #4
add r1, sp, #8
bl APTipc_CheckNew3DS
cmp r0, #0
bne APT_CheckNew3DS_closesession

mov r4, sp
ldrb r4, [r4, #8]

APT_CheckNew3DS_closesession:
add r0, sp, #4
bl APT_CloseSession

add r0, sp, #0
bl srv_shutdown

mov r0, r4
add sp, sp, #12
pop {r4, pc}
.pool

trigger_icache_invalidation: @ Trigger invalidating the entire icache via starting a new process(swkbd). This is based on smea's code for that.
push {r4, lr}
sub sp, sp, #0x28
ldr r0, [r7, #0x48]
mov r1, #0x8
tst r0, r1
bne trigger_icache_invalidation_begin
bl trigger_icache_invalidation_end

trigger_icache_invalidation_begin:
ldr r0, [r7, #0x68]
cmp r0, #0
beq trigger_icache_invalidation_start
blx r0
bl trigger_icache_invalidation_end

trigger_icache_invalidation_start:
add r0, sp, #0x20
bl srv_init
bl throw_fatalerr_errcheck

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x24
ldr r1, [r7, #0x5c]
mov r2, #0
bl APT_ReplySleepQuery
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x24
ldr r1, =0x401
bl APT_PreloadLibraryApplet
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

mov r0, #0
str r0, [sp, #12] @ buf1/buf2
str r0, [sp, #16]

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #12
str r0, [sp, #0] @ buf1*
mov r0, #1
str r0, [sp, #4] @ size2
add r0, sp, #16
str r0, [sp, #8] @ buf2*
add r0, sp, #0x24 @ handle*
mov r1, #0 @ out*
mov r2, #0x4 @ a
mov r3, #1 @ size1
bl APT_AppletUtility
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

ldr r0, [r7, #0x48]
mov r1, #0x80
tst r0, r1
bne trigger_icache_invalidation_lpend

trigger_icache_invalidation_lp:
add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x24
ldr r1, =0x401
add r2, sp, #0
bl APT_IsRegistered
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

mov r0, sp
ldrb r0, [r0, #0]
cmp r0, #0
bne trigger_icache_invalidation_lpend
ldr r0, =1000000
mov r1, #0
blx svcSleepThread
b trigger_icache_invalidation_lp

trigger_icache_invalidation_lpend:
mov r0, #0
str r0, [sp, #12] @ buf1/buf2
str r0, [sp, #16]

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #12
str r0, [sp, #0] @ buf1*
mov r0, #1
str r0, [sp, #4] @ size2
add r0, sp, #16
str r0, [sp, #8] @ buf2*
add r0, sp, #0x24 @ handle*
mov r1, #0 @ out*
mov r2, #0x4 @ a
mov r3, #1 @ size1
bl APT_AppletUtility
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x24
ldr r1, =0x401
bl APT_FinishPreloadingLibraryApplet
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

add r0, sp, #0x20
bl srv_shutdown

trigger_icache_invalidation_end:
add sp, sp, #0x28
pop {r4, pc}
.pool

getregion: @ inr0 = srv handle*. Returns region u8.
push {r0, lr}
sub sp, sp, #8
blx get_cfgu_servname
mov r2, r0
ldr r0, [sp, #8] @ srv handle
add r1, sp, #0 @ Out handle
bl srv_GetServiceHandle
bl throw_fatalerr_errcheck

add r0, sp, #0 @ cfg handle
add r1, sp, #4 @ u8* out
mov r2, #0
str r2, [r1]
bl cfg_getregion
bl throw_fatalerr_errcheck

ldr r0, [sp, #0]
blx svcCloseHandle

mov r3, sp
ldrb r3, [r3, #4]
cmp r3, #8
blt getregion_end
bl fail_thumb

getregion_end:
mov r0, r3
add sp, sp, #8
add sp, sp, #4
pop {pc}
.pool

exit_launchtitle:
push {r4, lr}
sub sp, sp, #0x34

mov r1, #3
ldr r0, [r7, #0x48]
mov r3, #0x40
and r3, r3, r0
lsr r3, r3, #4
lsr r0, r0, #1
and r0, r0, r1
orr r0, r0, r3
mov r4, r0
cmp r4, #0
bne exit_launchtitle_start
bl exit_launchtitle_end

exit_launchtitle_start:
add r0, sp, #0x20
bl srv_init
bl throw_fatalerr_errcheck

ldr r0, =0x42383841 @ DS INTERNET title
ldr r1, =0x00048005
str r0, [sp, #0x28]
str r1, [sp, #0x2c]
ldr r3, =0x00000102
str r3, [sp, #0x30]

exit_launchtitle_begin:
cmp r4, #1 @ Titlelaunch with the current process being an applet.
bne exit_launchtitle_type2

ldr r4, [r7, #0x5c] @ appID
cmp r4, #0
bne exit_launchtitle_type1
bl exit_launchtitle_endsrv

exit_launchtitle_type1:
#ifndef DISABLE_EXITLAUNCHTITLE_TYPE1
bl GSPGPU_UnregisterInterruptRelayQueue
bl throw_fatalerr_errcheck
bl GSPGPU_ReleaseRight
bl throw_fatalerr_errcheck

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x24
mov r1, r4
mov r2, #0
bl APT_ReplySleepQuery
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

blx getadr_camappletuniqueids
mov r4, r0
add r0, sp, #0x20
bl getregion
ldrb r3, [r4, r0]

add r1, sp, #8
mov r0, #2
str r0, [r1, #0]
str r3, [r1, #4] @ UniqueID(from the titleID) of the title "requesting" the title-launch.
ldr r2, [sp, #0x28]
ldr r3, [sp, #0x2c]
str r2, [r1, #8] @ programID low
str r3, [r1, #12] @ programID high
mov r0, #0
str r0, [r1, #16]
mov r0, #1
str r0, [r1, #20] 

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x24 @ apt handle*
add r1, sp, #8 @ buf*
mov r2, #0x18 @ size
bl APT_StoreSysMenuArg
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

ldr r0, [r7, #0x48]
mov r1, #0x20
tst r0, r1
bne exit_launchtitle_type1_finish

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x24
ldr r1, =0x101
bl APT_PrepareToStartSystemApplet
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x24 @ handle*
ldr r1, =0x101 @ appid
mov r2, #0 @ inhandle
mov r3, #0
str r3, [sp, #0] @ bufsize/buf*
bl APT_StartSystemApplet
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession
exit_launchtitle_type1_finish:
#endif
b exit_launchtitle_endsrv_procexit

exit_launchtitle_type2: @ This section(and the APT code called here) is based on code by smea. (Titlelaunch with the current process being a regular application)
cmp r4, #2
bne exit_launchtitle_type3

bl GSPGPU_UnregisterInterruptRelayQueue
bl throw_fatalerr_errcheck
bl GSPGPU_ReleaseRight
bl throw_fatalerr_errcheck

/*mov r0, #0
str r0, [sp, #12] @ buf1/buf2
str r0, [sp, #16]

mov r0, #0x10
str r0, [sp, #12] @ buf1

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #12
str r0, [sp, #0] @ buf1*
mov r0, #1
str r0, [sp, #4] @ size2
add r0, sp, #16
str r0, [sp, #8] @ buf2*
add r0, sp, #0x24 @ handle*
mov r1, #0 @ out*
mov r2, #0x7 @ a
mov r3, #0x4 @ size1
bl APT_AppletUtility
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

mov r0, #0
str r0, [sp, #12] @ buf1

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #12
str r0, [sp, #0] @ buf1*
mov r0, #1
str r0, [sp, #4] @ size2
add r0, sp, #16
str r0, [sp, #8] @ buf2*
add r0, sp, #0x24 @ handle*
mov r1, #0 @ out*
mov r2, #0x4 @ a
mov r3, #0x1 @ size1
bl APT_AppletUtility
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession*/

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x24
ldr r1, [sp, #0x28] @ programID
ldr r2, [sp, #0x2c]
mov r3, #0
str r3, [sp, #0]
bl APT_PrepareToDoApplicationJump
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

ldr r0, [r7, #0x5c]
ldr r1, =0x300
cmp r0, r1
bne exit_launchtitle_type2_doappjump

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x24
ldr r1, =0x300
mov r2, #0
bl APT_ReplySleepQuery
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

exit_launchtitle_type2_doappjump:
add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x24
mov r1, #0
mov r2, r1
add r3, sp, #4
str r3, [sp, #0]
bl APT_DoApplicationJump
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession
b exit_launchtitle_endsrv_procexit

exit_launchtitle_type3: @ Title-launch with using a "ns:s" service cmd received via APT.
cmp r4, #3
bne exit_launchtitle_type4

bl GSPGPU_UnregisterInterruptRelayQueue
bl throw_fatalerr_errcheck
bl GSPGPU_ReleaseRight
bl throw_fatalerr_errcheck

add r0, sp, #0x20
add r1, sp, #0x24
bl APT_OpenSession
bl throw_fatalerr_errcheck

add r0, sp, #0x1c
str r0, [sp, #0] @ out handle*
add r0, sp, #0x24 @ apt handle*
ldr r1, [r7, #0x5c] @ appID
mov r2, #0 @ parambuf*
mov r3, #0 @ maxparambufsize
bl APT_ReceiveParameter
bl throw_fatalerr_errcheck

add r0, sp, #0x24
bl APT_CloseSession

add r0, sp, #0x1c
ldr r1, [sp, #0x28] @ programID
ldr r2, [sp, #0x2c]
bl nss_LaunchFIRM
bl throw_fatalerr_errcheck

b exit_launchtitle_endsrv_procexit

exit_launchtitle_type4: @ FIRM launch via APT:S Reboot cmd.
cmp r4, #4
bne exit_launchtitle_endsrv

add r0, sp, #0x20
bl srv_shutdown

add r0, sp, #0x20
bl getsrvhandle_allservices

add r2, sp, #0x18
ldr r0, =(~0x3a545041)
ldr r1, =(~0x53)
mvn r0, r0
mvn r1, r1
str r0, [r2, #0]
str r1, [r2, #4]

add r0, sp, #0x20 @ srv handle
add r1, sp, #4 @ Out handle
bl srv_GetServiceHandle @ Get APT:S service handle.
bl throw_fatalerr_errcheck

add r0, sp, #4
ldr r3, [sp, #0x30]
str r3, [sp, #0]
ldr r2, [sp, #0x28] @ programID
ldr r3, [sp, #0x2c]
bl aptipc_reboot
bl throw_fatalerr_errcheck

ldr r0, [sp, #4]
blx svcCloseHandle

exit_launchtitle_endsrv_procexit:
add r0, sp, #0x20
bl srv_shutdown

blx svcExitProcess

exit_launchtitle_endsrv:
add r0, sp, #0x20
bl srv_shutdown

exit_launchtitle_end:
add sp, sp, #0x34
pop {r4, pc}
.pool

fsuser_initialize:
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x08010002
str r5, [r4, #0]
mov r1, #0x20
str r1, [r4, #4]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne fsuser_initialize_end
ldr r0, [r4, #4]

fsuser_initialize_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

fsuser_openfiledirectly: @ r0=fsuser* handle, r1=archiveid, r2=lowpath bufptr*(utf16), r3=lowpath bufsize, sp0=openflags, sp4=file out handle*
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]
ldr r1, [sp, #4]
ldr r2, [sp, #8]
ldr r3, [sp, #12]

ldr r5, =0x08030204
str r5, [r4, #0]
mov r5, #0
str r5, [r4, #4] @ transaction
str r1, [r4, #8] @ archiveid
mov r5, #1
str r5, [r4, #12] @ Archive LowPath.Type
str r5, [r4, #16] @ Archive LowPath.Size
mov r5, #4
str r5, [r4, #20] @ Archive LowPath.Type
str r3, [r4, #24] @ Archive LowPath.Size
ldr r5, [sp, #28]
str r5, [r4, #28] @ Openflags
mov r5, #0
str r5, [r4, #32] @ Attributes
ldr r5, =0x4802
str r5, [r4, #36] @ archive lowpath translate hdr/ptr
mov r5, sp
str r5, [r4, #40]
mov r5, #2
lsl r3, r3, #14
orr r3, r3, r5
str r3, [r4, #44] @ file lowpath translate hdr/ptr
str r2, [r4, #48]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne fsuser_openfiledirectly_end

ldr r0, [r4, #4]
ldr r2, [sp, #32]
ldr r1, [r4, #12]
cmp r0, #0
bne fsuser_openfiledirectly_end
str r1, [r2]

fsuser_openfiledirectly_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

fsfile_read: @ r0=filehandle*, r1=u32 filepos, r2=buf*, r3=size, sp0=u32* total transfersize
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]
ldr r1, [sp, #4]
ldr r2, [sp, #8]
ldr r3, [sp, #12]

ldr r5, =0x080200C2
str r5, [r4, #0]
str r1, [r4, #4] @ filepos
mov r1, #0
str r1, [r4, #8]
str r3, [r4, #12] @ Size
mov r5, #12
lsl r3, r3, #4
orr r3, r3, r5
str r3, [r4, #16] @ buf lowpath translate hdr/ptr
str r2, [r4, #20]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne fsfile_read_end
ldr r0, [r4, #4]
ldr r2, [sp, #28]
ldr r1, [r4, #8]
cmp r0, #0
bne fsfile_read_end
str r1, [r2]

fsfile_read_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

fsfile_write: @ r0=filehandle*, r1=u32 filepos, r2=buf*, r3=size, sp0=u32* total transfersize
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]
ldr r1, [sp, #4]
ldr r2, [sp, #8]
ldr r3, [sp, #12]

ldr r5, =0x08030102
str r5, [r4, #0]
str r1, [r4, #4] @ filepos
mov r1, #0
str r1, [r4, #8]
str r3, [r4, #12] @ Size
ldr r1, =0x10001
str r1, [r4, #16]
mov r5, #10
lsl r3, r3, #4
orr r3, r3, r5
str r3, [r4, #20] @ buf lowpath translate hdr/ptr
str r2, [r4, #24]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne fsfile_write_end
ldr r0, [r4, #4]
ldr r2, [sp, #28]
ldr r1, [r4, #8]
cmp r0, #0
bne fsfile_write_end
str r1, [r2]

fsfile_write_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

fsfile_close: @ r0=filehandle*
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x08080000
str r5, [r4, #0]

ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne fsfile_close_end
ldr r0, [r4, #4]

fsfile_close_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool

srv_init: @ r0 = srv handle*
push {r4, r5, lr}
mov r4, r0
blx get_srv_portname
mov r1, r0
mov r0, r4
blx svcConnectToPort
cmp r0, #0
bne srv_init_end

blx get_cmdbufptr
mov r5, r0

ldr r1, =0x00010002
str r1, [r5, #0]
mov r1, #0x20
str r1, [r5, #4]

ldr r0, [r4]
blx svcSendSyncRequest
cmp r0, #0
bne srv_init_end
ldr r0, [r5, #4]

srv_init_end:
pop {r4, r5, pc}
.pool

srv_shutdown: @ r0 = srv handle*
push {lr}
ldr r0, [r0]
blx svcCloseHandle
pop {pc}

srv_GetServiceHandle: @ r0 = srv handle*, r1 = out handle*, r2 = servicename
push {r4, r5, r6, r7, lr}
mov r5, r0
mov r6, r1
mov r7, r2

blx get_cmdbufptr
mov r4, r0

ldr r1, =0x00050100
str r1, [r4, #0]
add r1, r4, #4
mov r2, #0
str r2, [r1, #0]
str r2, [r1, #4]

srv_GetServiceHandle_servcpy:
ldrb r3, [r7, r2]
strb r3, [r1, r2]
cmp r3, #0
beq srv_GetServiceHandle_servcpy_end
add r2, r2, #1
cmp r2, #8
beq srv_GetServiceHandle_servcpy_end
b srv_GetServiceHandle_servcpy

srv_GetServiceHandle_servcpy_end:
str r2, [r4, #12]
mov r2, #0
str r2, [r4, #16]

ldr r0, [r5]
blx svcSendSyncRequest
cmp r0, #0
bne srv_GetServiceHandle_end

ldr r0, [r4, #4]
cmp r0, #0
bne srv_GetServiceHandle_end

ldr r1, [r4, #12]
str r1, [r6]

srv_GetServiceHandle_end:
pop {r4, r5, r6, r7, pc}
.pool

gsp_writereg: @ Write an u32 to a GPU reg. r0 = regaddr, r1 = u32 val. regaddr can be IO vaddr, or relative to 0x1EB00000.
push {lr}
sub sp, sp, #4

ldr r3, =0x1EB00000
cmp r0, r3
blt gsp_writereg_start
sub r0, r0, r3

gsp_writereg_start:
str r1, [sp, #0]

mov r1, sp
mov r2, #4
bl GSPGPU_WriteHWRegs

add sp, sp, #4
pop {pc}
.pool

GSPGPU_WriteHWRegs: @ r0=gpuregadr, r1=buf*, r2=size
push {r0, r1, r2, r4, lr}
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x00010082
str r1, [r4, #0]
ldr r1, [sp, #0]
str r1, [r4, #4]
ldr r1, [sp, #8]
str r1, [r4, #8]
lsl r1, r1, #14
mov r2, #2
orr r1, r1, r2
str r1, [r4, #12]
ldr r1, [sp, #4]
str r1, [r4, #16]

ldr r0, [r7, #0x58]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne GSPGPU_WriteHWRegs_end
ldr r0, [r4, #4]

GSPGPU_WriteHWRegs_end:
add sp, sp, #12
pop {r4, pc}
.pool

GSPGPU_TriggerCmdReqQueue:
push {r4, lr}
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x000C0000
str r1, [r4, #0]

ldr r0, [r7, #0x58]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne GSPGPU_TriggerCmdReqQueue_end
ldr r0, [r4, #4]

GSPGPU_TriggerCmdReqQueue_end:
pop {r4, pc}
.pool

GSPGPU_RegisterInterruptRelayQueue: @ r0=Handle eventHandle, r1=u32 flags, r2=Handle* outMemHandle, r3=u32* threadID
push {r0, r1, r2, r3, r4, lr}
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x00130042
str r1, [r4, #0]
ldr r1, [sp, #4]
str r1, [r4, #4]
mov r1, #0
str r1, [r4, #8]
ldr r1, [sp, #0]
str r1, [r4, #12]

ldr r0, [r7, #0x58]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne GSPGPU_RegisterInterruptRelayQueue_end

ldr r0, [r4, #4]
ldr r2, [sp, #12]
ldr r1, [r4, #8]
str r1, [r2]
ldr r2, [sp, #8]
ldr r1, [r4, #16]
str r1, [r2]

GSPGPU_RegisterInterruptRelayQueue_end:
add sp, sp, #16
pop {r4, pc}
.pool

GSPGPU_UnregisterInterruptRelayQueue:
push {r4, lr}
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x00140000
str r1, [r4, #0]

ldr r0, [r7, #0x58]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne GSPGPU_UnregisterInterruptRelayQueue_end
ldr r0, [r4, #4]

GSPGPU_UnregisterInterruptRelayQueue_end:
pop {r4, pc}
.pool

GSPGPU_AcquireRight: @ r0=flag
push {r0, r4, lr}
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x00160042
str r1, [r4, #0]
ldr r1, [sp, #0]
str r1, [r4, #4]
mov r1, #0
str r1, [r4, #8]
ldr r1, =0xffff8001
str r1, [r4, #12]

ldr r0, [r7, #0x58]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne GSPGPU_AcquireRight_end
ldr r0, [r4, #4]

GSPGPU_AcquireRight_end:
add sp, sp, #4
pop {r4, pc}
.pool

GSPGPU_ReleaseRight:
push {r4, lr}
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x00170000
str r1, [r4, #0]

ldr r0, [r7, #0x58]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne GSPGPU_ReleaseRight_end
ldr r0, [r4, #4]

GSPGPU_ReleaseRight_end:
pop {r4, pc}
.pool

GSPGPU_SetLcdForceBlack:
push {r0, r4, lr}
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x000B0040
str r1, [r4, #0]
mov r1, sp
ldrb r1, [r1, #0]
strb r1, [r4, #4]

ldr r0, [r7, #0x58]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne GSPGPU_SetLcdForceBlack_end
ldr r0, [r4, #4]

GSPGPU_SetLcdForceBlack_end:
add sp, sp, #4
pop {r4, pc}
.pool

GSPGPU_InvalidateDataCache:
push {r0, r1, r4, lr}
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x00090082
str r1, [r4, #0]
ldr r1, [sp, #0]
str r1, [r4, #4]
ldr r1, [sp, #4]
str r1, [r4, #8]
mov r1, #0
str r1, [r4, #12]
ldr r1, =0xffff8001
str r1, [r4, #16]

ldr r0, [r7, #0x58]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne GSPGPU_InvalidateDataCache_end
ldr r0, [r4, #4]

GSPGPU_InvalidateDataCache_end:
add sp, sp, #8
pop {r4, pc}
.pool

#ifndef DISABLE_EXITLAUNCHTITLE_TYPE1
cfg_getregion: @ inr0=cfg handle*, inr1=u8* out
push {r0, r1, r2, r3, r4, r5, lr}
blx get_cmdbufptr
mov r4, r0

ldr r0, [sp, #0]

ldr r5, =0x00020000
str r5, [r4, #0]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne cfg_getregion_end
ldr r0, [r4, #4]
cmp r0, #0
bne cfg_getregion_end

ldr r2, [sp, #4]
ldrb r1, [r4, #8]
strb r1, [r2]

cfg_getregion_end:
add sp, sp, #16
pop {r4, r5, pc}
.pool
#endif

loadsd_arm9code:
push {r4, r5, r6, lr}
sub sp, sp, #32

ldr r5, =0x1000
add r5, r5, r7

mov r0, #0
str r0, [sp, #4]
str r0, [sp, #8]
str r0, [sp, #12]
str r0, [sp, #16]
str r0, [sp, #20]

bl APT_CheckNew3DS
mov r1, r5
sub r1, r1, #8
str r0, [r1]
lsl r0, r0, #30
mov r2, r0

ldr r0, =0x1FF80002
ldr r0, [r0] @ +0 = KERNEL_VERSIONMINOR, +1 = KERNEL_VERSIONMAJOR, +2 = KERNEL_SYSCOREVER
mov r1, #1
lsl r1, #31
orr r0, r0, r1
orr r0, r0, r2
mov r6, r0 @ RUNNINGFWVER

mov r1, r5
sub r1, r1, #4
str r0, [r1]

/*blx getaddr_arm9codebin_filepath

mov r1, r0
add r0, sp, #4
mov r2, #1 @ openflags=R
bl IFile_Open
bl throw_fatalerr_errcheck

add r0, sp, #4 @ ctx
add r1, sp, #24 @ transfercount
mov r2, r5
add r2, r2, #8
ldr r3, =0x8000
sub r3, r3, #0x10
bl IFile_Read
bl throw_fatalerr_errcheck

mov r1, #1
ldr r0, [sp, #4]
bic r0, r0, r1
bl IFile_Close*/

add r0, sp, #12
bl srv_init
bl throw_fatalerr_errcheck

ldr r0, [r7, #0x50] @ fsuser handle
ldr r1, [r7, #0x54] @ filehandle
str r0, [sp, #16]
str r1, [sp, #20]
cmp r0, #0
bne loadsd_arm9code_openfile

bl get_fsuser_servname
mov r2, r0
add r0, sp, #12 @ srv handle
add r1, sp, #16 @ Out handle
bl srv_GetServiceHandle
bl throw_fatalerr_errcheck

add r0, sp, #16
bl fsuser_initialize
bl throw_fatalerr_errcheck

loadsd_arm9code_openfile:
mov r0, #0
ldr r1, [sp, #20]
cmp r1, #0
bne loadsd_arm9code_readfile

mov r0, #1
str r0, [sp, #0] @ openflags
add r0, sp, #20
str r0, [sp, #4] @ fileout handle*
blx getaddr_arm9codebin_filepath
mov r2, r0 @ lowpath buf
mov r3, r1 @ lowpath size
add r0, sp, #16 @ fsuser handle
mov r1, #9 @ archiveid
bl fsuser_openfiledirectly
cmp r0, #0
beq loadsd_arm9code_readfile

bl kernelmode_patchfs_getadr
blx svc7b

ldr r0, [sp, #16]
blx svcCloseHandle

bl get_fsuser_servname
mov r2, r0
add r0, sp, #12 @ srv handle
add r1, sp, #16 @ Out handle
bl srv_GetServiceHandle
bl throw_fatalerr_errcheck

add r0, sp, #16
bl fsuser_initialize
bl throw_fatalerr_errcheck

mov r0, #1
str r0, [sp, #0] @ openflags
add r0, sp, #20
str r0, [sp, #4] @ fileout handle*
blx getaddr_arm9codebin_filepath
mov r2, r0
mov r3, r1
add r0, sp, #16 @ fsuser handle
mov r1, #9 @ archiveid
bl fsuser_openfiledirectly

loadsd_arm9code_readfile:
mov r4, r0

#ifdef DUMPMEMGPU
#ifdef DUMPMEMGPU_ADR
#ifdef DUMPMEMGPU_SIZE
add r0, sp, #16
ldr r1, =DUMPMEMGPU_ADR
ldr r2, =DUMPMEMGPU_SIZE
bl dumpmemgpu_writesd
#endif
#endif
#endif

add r0, sp, #16
add r1, sp, #20
add r2, sp, #12
bl load_arm11code

mov r0, r4
bl throw_fatalerr_errcheck

add r0, sp, #24
str r0, [sp, #0] @ u32* total transfersize
add r0, sp, #20 @ filehandle*
mov r1, #0 @ u32 filepos
mov r2, r5
add r2, r2, #8 @ buf
ldr r3, =0x8000
sub r3, r3, #0x10 @ size
bl fsfile_read
bl throw_fatalerr_errcheck

add r0, sp, #20 @ filehandle*
bl fsfile_close

ldr r0, [sp, #20]
blx svcCloseHandle

ldr r0, [sp, #16]
blx svcCloseHandle

add r0, sp, #12
bl srv_shutdown

ldr r1, =0x39444f43
ldr r0, [sp, #24]
str r1, [r5, #0]
str r0, [r5, #4]

cmp r0, #0
bne loadsd_arm9code_sdloadend
mov r0, #5
mvn r0, r0
bl throw_fatalerr

loadsd_arm9code_sdloadend:
mov r0, r5
add r0, r0, #16
ldr r1, =0x4d415250
ldr r2, [r0]
cmp r2, r1
bne loadsd_arm9code_end @ Only set the below paramaters when the word at loadaddr+4 matches the above word.

add r0, r0, #4
mov r1, #3
str r1, [r0, #0] @ FIRMLAUNCH_RUNNINGTYPE
str r6, [r0, #4] @ RUNNINGFWVER

loadsd_arm9code_end:
add sp, sp, #32
pop {r4, r5, r6, pc}
.pool

load_arm11code: @ r0=fsuser handle*, inr1=arm9 fsfile handle*, inr2=srv handle
push {r4, r5, r6, lr}
sub sp, sp, #40

ldr r5, =0x1000
add r5, r5, r7

ldr r0, [r0]
str r0, [sp, #16]
ldr r0, [r1]
str r0, [sp, #32]
ldr r0, [r2]
str r0, [sp, #36]

ldr r0, [r7, #0x60] @ LINEAR-mem address for the code
ldr r1, [r7, #0x64] @ jump vaddr for the code
cmp r1, #0
beq load_arm11code_end
cmp r0, #0
bne load_arm11code_readbegin

mov r5, r1
mov r0, r5
ldr r1, =0x8000
blx memprot_code

load_arm11code_readbegin:
mov r0, #1
str r0, [sp, #0] @ openflags
add r0, sp, #20
str r0, [sp, #4] @ fileout handle*
blx getaddr_arm11codebin_filepath
mov r2, r0
mov r3, r1
add r0, sp, #16 @ fsuser handle
mov r1, #9 @ archiveid
bl fsuser_openfiledirectly
cmp r0, #0
bne load_arm11code_end

add r0, sp, #24
str r0, [sp, #0] @ u32* total transfersize
add r0, sp, #20 @ filehandle*
mov r1, #0 @ u32 filepos
mov r2, r5 @ buf
ldr r3, =0x8000 @ size
bl fsfile_read
bl throw_fatalerr_errcheck

add r0, sp, #20 @ filehandle*
bl fsfile_close

ldr r0, [sp, #20]
blx svcCloseHandle

ldr r4, [sp, #24]
cmp r4, #0
beq load_arm11code_end

mov r0, #0
bl GSPGPU_SetLcdForceBlack

ldr r0, [r7, #0x60]
cmp r0, #0
beq load_arm11code_jumpend

mov r0, #7
add r4, r4, r0
bic r4, r4, r0

mov r0, r5
mov r1, r4
bl gsp_flushdcache

mov r0, r5 @ src-addr
ldr r1, [r7, #0x60] @ dst-addr
mov r2, r4 @ size

mov r3, #8
str r3, [sp, #12] @ flags
mov r3, #0 @ width0
str r3, [sp, #0] @ height0
str r3, [sp, #4] @ width1
str r3, [sp, #8] @ height1
blx gxlow_cmd4

blx svcSleepThread_delay1second

load_arm11code_jumpend:
mov r5, #0
str r5, [r7, #0x60]
ldr r6, [r7, #0x64]
str r5, [r7, #0x64]
ldr r5, [r7, #0x48]
mov r4, #0x10
orr r5, r5, r4
mov r4, #1
bic r5, r5, r4
str r5, [r7, #0x48]

add r0, sp, #32 @ arm9 filehandle*
bl fsfile_close

ldr r0, [sp, #32]
blx svcCloseHandle

ldr r0, [sp, #16] @ fsuser handle
blx svcCloseHandle

add r0, sp, #36
bl srv_shutdown

adr r0, kernelpatchesfinish_cachestuff
blx svc7b

mov r0, r7
blx r6

load_arm11code_jumpendlp:
b load_arm11code_jumpendlp

load_arm11code_end:
add sp, sp, #40
pop {r4, r5, r6, pc}
.pool

#ifdef DUMPMEMGPU_ADR
#ifdef DUMPMEMGPU_SIZE
dumpmemgpu_writesd:
push {r4, r5, r6, lr}
sub sp, sp, #32

mov r4, r1
mov r5, r2

ldr r0, [r0]
str r0, [sp, #16]

ldr r6, =0x1000
add r6, r6, r7

mov r0, r4 @ src-addr
mov r1, r6 @ dst-addr
mov r2, r5 @ size

mov r3, #8
str r3, [sp, #12] @ flags
mov r3, #0 @ width0
str r3, [sp, #0] @ height0
str r3, [sp, #4] @ width1
str r3, [sp, #8] @ height1
blx gxlow_cmd4

blx svcSleepThread_delay1second

mov r0, r6
mov r1, r5
bl GSPGPU_InvalidateDataCache

mov r0, #6
str r0, [sp, #0] @ openflags
add r0, sp, #20
str r0, [sp, #4] @ fileout handle*
blx getaddr_arm11memdump_filepath
mov r2, r0
mov r3, r1
add r0, sp, #16 @ fsuser handle
mov r1, #9 @ archiveid
bl fsuser_openfiledirectly
cmp r0, #0
bne dumpmemgpu_writesd_end

add r0, sp, #24
str r0, [sp, #0] @ u32* total transfersize
add r0, sp, #20 @ filehandle*
mov r1, #0 @ u32 filepos
mov r2, r6 @ buf
mov r3, r5 @ size
bl fsfile_write
bl throw_fatalerr_errcheck

add r0, sp, #20 @ filehandle*
bl fsfile_close

ldr r0, [sp, #20]
blx svcCloseHandle

dumpmemgpu_writesd_end:
add sp, sp, #32
pop {r4, r5, r6, pc}
.pool
#endif
#endif

throw_fatalerr_errcheck:
cmp r0, #0
blt throw_fatalerr
bx lr

throw_fatalerr:
ldr r3, [r7, #4]
bx r3
.pool

.arm

.type gxlow_cmd4, %function
gxlow_cmd4:
push {r0, r1, r2, r3, r4, r5, r6, lr}
sub sp, sp, #32

ldr r4, [sp, #0x40]
str r4, [sp, #0x0]
ldr r4, [sp, #0x44]
str r4, [sp, #0x4]
ldr r4, [sp, #0x48]
str r4, [sp, #0x8]
ldr r4, [sp, #0x4c]
str r4, [sp, #0xc]

ldr r4, [r7, #0x1c]
cmp r4, #0
beq gxlow_cmd4_begin
blx r4
b gxlow_cmd4_end

gxlow_cmd4_begin:

mov r0, #0
mvn r0, r0
ldr r4, =0xfd0
ldr r4, [r7, r4] @ gxCmdBuf
cmp r4, #0
beq gxlow_cmd4_end

mov r0, #4 @ Write the cmd-data to stack.
str r0, [sp, #0x0] @ cmdid
ldr r0, [sp, #0x20] @ input adr
str r0, [sp, #0x4]
ldr r0, [sp, #0x24] @ output adr
str r0, [sp, #0x8]
ldr r0, [sp, #0x28] @ size
str r0, [sp, #0xc]

ldrh r0, [sp, #0x2c]
ldrh r1, [sp, #0x40]
lsl r1, r1, #16
str r1, [sp, #0x10] @ dimensions0

ldrh r0, [sp, #0x44]
ldrh r1, [sp, #0x48]
lsl r1, r1, #16
str r1, [sp, #0x14] @ dimensions1

ldr r1, [sp, #0x4c]
str r1, [sp, #0x18] @ flags
mov r1, #0
str r1, [sp, #0x1c] @ unused

gxlow_cmd4_readhdr:
ldrex r5, [r4]
strex r0, r5, [r4]
cmp r0, #0
bne gxlow_cmd4_readhdr

lsr r6, r5, #8
uxtb r6, r6 @ totalCommands
uxtb r5, r5 @ commandIndex

mov r0, #0
mvn r0, r0
cmp r6, #15
bge gxlow_cmd4_end @ Return -2 when totalCommands is >=15.

add r5, r5, r6
mov r0, #0xf
and r5, r5, r0 @ nextCmd

mov r1, #0x20
mov r0, r4
add r0, r0, r1
mul r2, r5, r1
mov r5, r2
add r0, r0, r5 @ dst
mov r1, sp
mov r2, #0x20

gxlow_cmd4_cpycmd:
ldr r3, [r1]
str r3, [r0]
add r0, r0, #4
add r1, r1, #4
sub r2, r2, #4
cmp r2, #0
bgt gxlow_cmd4_cpycmd

gxlow_cmd4_updatehdr:
ldrex r5, [r4]
strex r0, r5, [r4]
cmp r0, #0
bne gxlow_cmd4_updatehdr

lsr r6, r5, #8
uxtb r6, r6 @ totalCommands
add r6, r6, #1
ldr r1, =0xffff00ff
and r5, r5, r1
lsl r6, r6, #8
orr r5, r5, r6

ldrex r1, [r4]
strex r0, r5, [r4]
cmp r0, #0
bne gxlow_cmd4_updatehdr

mov r0, #0
lsr r6, r6, #8
cmp r6, #1
bgt gxlow_cmd4_end

blx GSPGPU_TriggerCmdReqQueue

gxlow_cmd4_end:
add sp, sp, #0x30
pop {r4, r5, r6, pc}
.pool

.thumb

gsp_flushdcache:
ldr r2, [r7, #0x58]
cmp r2, #0
bne gsp_flushdcache_cmd
ldr r2, [r7, #0x20]
bx r2

gsp_flushdcache_cmd:
push {r0, r1, r4, lr}
blx get_cmdbufptr
mov r4, r0

ldr r1, =0x00080082
str r1, [r4, #0]
ldr r1, [sp, #0]
ldr r2, [sp, #4]
str r1, [r4, #4]
str r2, [r4, #8]
mov r3, #0
str r3, [r4, #12]
ldr r3, =0xffff8001
str r3, [r4, #16]

ldr r0, [r7, #0x58]
ldr r0, [r0]
blx svcSendSyncRequest
cmp r0, #0
bne gsp_flushdcache_end
ldr r0, [r4, #4]

gsp_flushdcache_end:
add sp, sp, #8
pop {r4, pc}
.pool

gsp_initialize:
push {r4, r5, r6, lr}
sub sp, sp, #32
ldr r0, [r7, #0x58]
cmp r0, #0
bne gsp_initialize_end

ldr r1, =0xfc0
add r1, r1, r7
str r1, [r7, #0x58]

ldr r0, =0xfc4
add r0, r0, r7
blx svcCreateEvent
bl throw_fatalerr_errcheck

add r0, sp, #12
bl srv_init
bl throw_fatalerr_errcheck

blx get_gspgpu_servname
mov r2, r0
add r0, sp, #12 @ srv handle
ldr r1, [r7, #0x58] @ Out handle
bl srv_GetServiceHandle
bl throw_fatalerr_errcheck

add r0, sp, #12
bl srv_shutdown

mov r0, #0 @ flag
bl GSPGPU_AcquireRight
bl throw_fatalerr_errcheck

ldr r3, =0xfc4
add r3, r3, r7
ldr r0, [r3] @ eventHandle
mov r1, #1 @ flags
add r3, r3, #4
mov r2, r3 @ outMemHandle* (r7+0xfc8)
add r3, r3, #4 @ u32* threadID (r7+0xfcc)
bl GSPGPU_RegisterInterruptRelayQueue
bl throw_fatalerr_errcheck

ldr r0, =0xfc8 
ldr r0, [r7, r0] @ Handle memblock
ldr r1, =0x10002000 @ u32 addr
mov r2, #0x3 @ MemPerm my_perm
ldr r3, =0x10000000 @ MemPerm other_perm
bl svcMapMemoryBlock
bl throw_fatalerr_errcheck

ldr r0, =0x10002800
ldr r1, =0xfcc
ldr r1, [r7, r1] @ r1=threadID
ldr r2, =0x200
mul r1, r1, r2
add r0, r0, r1
ldr r1, =0xfd0
str r0, [r7, r1] @ gxCmdBuf

gsp_initialize_end:
add sp, sp, #32
pop {r4, r5, r6, pc}
.pool

/*IFile_Open: @ r0 = ctx, r1 = utf16 path*, r2 = openflags
ldr r4, [r7, #0x24]
bx r4
.pool

IFile_Close: @ r0 = u32 loaded from ctx+0 with bit0 cleared
ldr r4, [r7, #0x28]
bx r4
.pool

IFile_GetSize:
ldr r4, [r7, #0x2c]
bx r4
.pool

IFile_Seek:
ldr r4, [r7, #0x30]
bx r4
.pool

IFile_Read: @ r0 = ctx, r1 = u32* transfercount, r2 = buf*, r3 = bufsize
ldr r4, [r7, #0x34]
bx r4
.pool

IFile_Write:
ldr r4, [r7, #0x38]
bx r4
.pool*/

/*APT_PrepareToDoApplicationJump:
ldr r4, [r7, #0x40]
bx r4
.pool

APT_DoApplicationJump:
ldr r4, [r7, #0x44]
bx r4
.pool*/

checkfail_thumb:
cmp r0, #0
bne fail_thumb
bx lr

.align 2
fail_thumb:
blx fail

.arm

.type fail, %function
fail:
.word 0xffffffff

.type svcControlMemory, %function
svcControlMemory:
svc 0x01
bx lr

.type svcExitProcess, %function
svcExitProcess:
svc 0x03
bx lr

.type svcSleepThread_delay1second_getadr, %function
svcSleepThread_delay1second_getadr:
adr r0, svcSleepThread_delay1second
bx lr

.type svcSleepThread_delay1second, %function
.type svcSleepThread, %function
svcSleepThread_delay1second:
ldr r0, =1000000000
mov r1, #0

svcSleepThread:
svc 0x0a
bx lr
.pool

.type svcCreateEvent, %function
svcCreateEvent:
	str r0, [sp, #-4]!
	svc 0x17
	ldr r2, [sp], #4
	str r1, [r2]
	bx  lr

.global svcMapMemoryBlock
.type svcMapMemoryBlock, %function
svcMapMemoryBlock:
	svc 0x1F
	bx  lr

.global svcUnmapMemoryBlock
.type svcUnmapMemoryBlock, %function
svcUnmapMemoryBlock:
	svc 0x20
	bx  lr

.type svcConnectToPort, %function
svcConnectToPort:
	str r0, [sp,#-0x4]!
	svc 0x2D
	ldr r3, [sp], #4
	str r1, [r3]
	bx lr

.type svcCloseHandle, %function
svcCloseHandle:
svc 0x23
bx lr

.type svcSendSyncRequest, %function
svcSendSyncRequest:
svc 0x32
bx lr

.type svcGetProcessId, %function
svcGetProcessId:
	str r0, [sp, #-4]!
	svc 0x35
	ldr r2, [sp], #4
	str r1, [r2]
	bx  lr

.type svc7b, %function
svc7b:
svc 0x7b
bx lr

.type memprot_code, %function
memprot_code:
push {r4, r5, r6, r7, r8, lr}
mov r7, r0
mov r8, r1
add r8, r8, r7

ldr r1, =0xFFFF8001
svc 0x27
mov r6, r1
cmp r0, #0
bne memprot_code_end

memprot_code_lp:
mov r0, r6
mov r1, r7
mov r2, #0
ldr r3, =0x1000
mov r4, #6
mov r5, #7
svc 0x70
cmp r0, #0
bne memprot_code_end
ldr r1, =0x1000
add r7, r7, r1
cmp r7, r8
blt memprot_code_lp

memprot_code_end:
pop {r4, r5, r6, r7, r8, pc}
.pool

.type get_cmdbufptr, %function
get_cmdbufptr:
mrc 15, 0, r0, cr13, cr0, 3
add r0, r0, #0x80
bx lr

.type kernelpatchesfinish_cachestuff, %function
kernelpatchesfinish_cachestuff:
cpsid i @ disable IRQs
mov r0, #0
mcr p15, 0, r0, c7, c14, 0 @ "Clean and Invalidate Entire Data Cache"
mcr p15, 0, r0, c7, c10, 5 @ "Data Memory Barrier"
mcr p15, 0, r0, c7, c5, 0 @ "Invalidate Entire Instruction Cache. Also flushes the branch target cache"
mcr p15, 0, r0, c7, c10, 4 @ "Data Synchronization Barrier"
bx lr

.type kernel_vaddr2physaddr, %function
kernel_vaddr2physaddr:
push {r4, lr}
mov r4, r0
mcr p15, 0, r0, c7, c8, 0 @ Convert LR of kernelmode_code with low 12-bits of the vaddr, to physaddr.

mrc p15, 0, r0, c7, c4, 0
mov r3, #1
tst r0, r3
beq kernel_vaddr2physaddr_end

ldr r1, =0x4040FE02 @ vaddr->physaddr conversion failure.
bl fail_thumb

kernel_vaddr2physaddr_end:
lsr r0, r0, #12
lsl r0, r0, #12
pop {r4, pc}
.pool

.type kernelmode_patchfs_getadr, %function
kernelmode_patchfs_getadr:
adr r0, kernelmode_patchfs
bx lr

.type kernelmode_patchfs, %function
kernelmode_patchfs: @ Based on code by smea.
cpsid i @ disable IRQs
push {r4, r5, r6, lr}

bl kernelmode_getlcdregbase
mov r6, r0
ldr r1, =0x204
add r0, r6, r1

ldr r1, =0x10000FF
str r1, [r0] @ Set main-screen colorfill reg so that red is displayed.

ldr r3, =0x1FF80002
ldrb r3, [r3]
ldr r5, =0xE0000000

cmp r3, #44
bge kernelmode_patchfs_L0

ldr r5, =0xF0000000

kernelmode_patchfs_L0:
#ifdef DUMP_AXIWRAM
ldr r0, =0xDFF80000
ldr r1, =DUMPMEMGPU_ADR
ldr r2, =0x80000

kernelmode_patchfs_L0_cpy:
ldr r3, [r0]
str r3, [r1]
add r0, r0, #4
add r1, r1, #4
sub r2, r2, #4
cmp r2, #0
bgt kernelmode_patchfs_L0_cpy
#endif

ldr r1, =0x1FF80030 @ APPMEMTYPE
ldr r1, [r1]
adr r2, appmemregion_sizetable
ldr r1, [r2, r1, lsl #2] @ Load the actual APPLICATION memregion size using a table + APPMEMTYPE, since APPMEMALLOC isn't always the actual memregion size.

ldr r3, =0x1FF80040
ldr r2, [r3, #4] @ SYSMEMALLOC
ldr r3, [r3, #8] @ BASEMEMALLOC

add r1, r1, r2 @ r1 = offset of BASE mem-region in FCRAM.
add r3, r3, r1 @ r3 = size of FCRAM(end-offset of BASE mem-region).

add r1, r1, r5
add r3, r3, r5
sub r3, r3, #0x10
mov r0, r1
mov r1, r3
adr r2, fsSequence

kernelmode_patchfs_lp:
ldrh r3, [r0, #0]
ldrh r4, [r2, #0]
cmp r3, r4
bne kernelmode_patchfs_lpnext
ldrh r3, [r0, #2]
ldrh r4, [r2, #2]
cmp r3, r4
bne kernelmode_patchfs_lpnext
ldrh r3, [r0, #4]
ldrh r4, [r2, #4]
cmp r3, r4
bne kernelmode_patchfs_lpnext
ldrh r3, [r0, #6]
ldrh r4, [r2, #6]
cmp r3, r4
bne kernelmode_patchfs_lpnext

b kernelmode_patchfs_lpend

kernelmode_patchfs_lpnext:
add r0, r0, #2
cmp r0, r1
blt kernelmode_patchfs_lp

b kernelmode_patchfs_end

kernelmode_patchfs_lpend:
adr r1, fspatch
mov r2, #0x16

kernelmode_patchfs_cpylp:
ldrh r3, [r1]
strh r3, [r0]
add r0, r0, #2
add r1, r1, #2
subs r2, r2, #2
bgt kernelmode_patchfs_cpylp

bl kernelpatchesfinish_cachestuff

ldr r1, =0x204
add r0, r6, r1

ldr r1, =0x100FF00
str r1, [r0] @ Set main-screen colorfill reg so that green is displayed.

kernelmode_patchfs_end:
pop {r4, r5, r6}
pop {r0}
mov lr, r0
//cpsie i @ enable IRQs (don't re-enable IRQs since the svc-handler will just disable IRQs after the SVC returns)
bx lr
.pool

.type get_kernelcode_overwriteaddr, %function
get_kernelcode_overwriteaddr:
push {r4, lr}
ldr r4, =0x1FF80002
ldrb r4, [r4]

ldr r2, =0x1FF80003
ldrb r2, [r2]
cmp r2, #2
blne fail

blx APT_CheckNew3DS

mov r2, #0
mov r3, r4

ldr r4, =0x1FF80001
ldrb r4, [r4]

cmp r0, #0
beq get_kernelcode_overwriteaddr_old3ds

@ New3DS:
cmp r3, #45
ldreq r2, =0xDFF82264 @ v8.1
cmp r3, #46
ldreq r2, =0xDFF82260 @ v9.0

b get_kernelcode_overwriteaddr_end

get_kernelcode_overwriteaddr_old3ds:
cmp r3, #35 @ FW25
cmpne r3, #39 @ FW2E
ldreq r2, =0xEFF822A8 @ FW25/FW2E
cmp r3, #36 @ FW26
cmpne r3, #37 @ FW29
cmpne r3, #38 @ FW2A
cmpne r3, #40 @ FW30
ldreq r2, =0xEFF822A4 @ FW26/FW29/FW2A/FW30

cmp r3, #46
ldreq r2, =0xDFF82290 @ FW38
cmp r3, #44
ldreq r2, =0xDFF82294 @ FW37
cmp r3, #34
ldreq r2, =0xEFF827cc @ FW1F
cmp r3, #33
ldreq r2, =0xEFF827d0 @ FW1D
cmp r3, #32
ldreq r2, =0xEFF8256c @ FW18
cmp r3, #31
ldreq r2, =0xEFF88928 @ FW0F
cmp r3, #30
ldreq r2, =0xEFF882c8 @ FW0B
cmp r3, #29
ldreq r2, =0xEFF882d4 @ FW09
cmp r3, #28
ldreq r2, =0xEFF88534 @ FW02
cmp r3, #27
ldreq r2, =0xEFF884b8 @ FW00

get_kernelcode_overwriteaddr_end:
mov r0, r2
pop {r4, pc}
.pool

.type get_srv_portname, %function
get_srv_portname:
adr r0, srv_portname
bx lr

.type get_aptu_servname, %function
get_aptu_servname:
adr r0, aptu_servname
bx lr

.type get_apta_servname, %function
get_apta_servname:
adr r0, apta_servname
bx lr

.type get_fsuser_servname, %function
get_fsuser_servname:
adr r0, fsuser_servname
bx lr

.type get_gspgpu_servname, %function
get_gspgpu_servname:
adr r0, gspgpu_servname
bx lr

#ifndef DISABLE_EXITLAUNCHTITLE_TYPE1
.type get_cfgu_servname, %function
get_cfgu_servname:
adr r0, cfgu_servname
bx lr

.type getadr_camappletuniqueids, %function
getadr_camappletuniqueids:
adr r0, camapplet_uniqueids
bx lr
#endif

appmemregion_sizetable_getadr:
adr r0, appmemregion_sizetable
bx lr

getaddr_arm9codebin_filepath:
adr r0, arm9_codebin_filepath
adr r1, arm9_codebin_filepath_end
sub r1, r1, r0
bx lr

getaddr_arm11codebin_filepath:
adr r0, arm11_codebin_filepath
adr r1, arm11_codebin_filepath_end
sub r1, r1, r0
bx lr

getaddr_arm11memdump_filepath:
adr r0, arm11_memdump_filepath
adr r1, arm11_memdump_filepath_end
sub r1, r1, r0
bx lr

/*nss_servname:
.ascii "ns:s"
.align 2*/

srv_portname:
.string "srv:"
.align 2

fsuser_servname:
.string "fs:USER"
.align 2

aptu_servname:
.string "APT:U"
.align 2

apta_servname:
.string "APT:A"
.align 2

#ifndef DISABLE_EXITLAUNCHTITLE_TYPE1
cfgu_servname:
.string "cfg:u"
.align 2
#endif

gspgpu_servname:
.string "gsp::Gpu"
.align 2

arm9_codebin_filepath:
.string16 "/3dshax_arm9.bin"
.align 2
arm9_codebin_filepath_end:

arm11_codebin_filepath:
.string16 "/3dshax_payload_arm11.bin"
.align 2
arm11_codebin_filepath_end:

arm11_memdump_filepath:
.string16 "/3dshax_memdump.bin"
.align 2
arm11_memdump_filepath_end:

fsSequence: @ This and fspatch is based on code from smea.
.hword 0x9909, 0x2220, 0x4668, 0x3118

.thumb
fspatch:
	mov r0, #0xFF
	str r0, [r5, #0x1C]
	str r0, [r5, #0x18]
	mov r0, #0
	mov r1, #0
	stmia r5!, {r0, r1}
	stmia r5!, {r0, r1}
	stmia r5!, {r0, r1}
	nop
	nop
	nop

.align 2

#ifndef DISABLE_EXITLAUNCHTITLE_TYPE1
camapplet_uniqueids: @ uniqueID portion of the titleID for the camera applet, for each region.
.byte 0x84, 0x90, 0x99, 0x84, 0xa2, 0xaa, 0xb2
.align 2
#endif

appmemregion_sizetable:
.word 0x04000000, 0, 0x06000000, 0x05000000, 0x04800000, 0x02000000, 0x07C00000, 0x0B200000
