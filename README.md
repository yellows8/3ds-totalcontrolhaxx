This is Nintendo 3DS totalcontrolhaxx for system-version <=v9.2, only using [vulns](https://www.3dbrew.org/wiki/3DS_System_Flaws) which have been already public+fixed(and also publicly exploited elsewhere). This is based on another repo originally from March 2014.

This loads "/3dshax_arm9.bin" from SD(FS-module is patched when SD isn't accessible), this is the same binary loaded by [3dsbootldr_firm](https://github.com/yellows8/3dsbootldr_firm)/etc. This also includes other optional functionality, see source+Makefile.

To build, run "make", then if you want the 3dsx build run "make" under the "3ds-totalcontrolhaxx" sub-directory.

The built 3ds_arm11code.bin is PIC(hence the asm-only) and can be used instead of the otherapp payload in various exploits(hence the above, this existed before even ninjhax). Like payload.bin with oot3dhax and 3ds_arm11code.bin for browserhax. However, you can just use it from the \*hax payload via the .3dsx version too.

From the start this used a paramblk structure in linearmem which is passed as r0 when jumping to the binary entry, see oot3dhax/browserhax etc. The otherapp payload paramblk passed as r0 is based on the paramblk from here.

# Credits
* smea, as mentioned in the source.

