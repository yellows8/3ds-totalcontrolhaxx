#include <string.h>
#include <malloc.h>

#include <3ds.h>

void haxpayload(u32*);

//extern Handle gspGpuHandle;

/*void gxlowcmd_4(u32* inadr, u32* outadr, u32 size, u32 width0, u32 height0, u32 width1, u32 height1, u32 flags)
{
	GX_TextureCopy(inadr, width0 | (height0<<16), outadr, width1 | (height1<<16), size, flags);
}

Result gsp_flushdcache(u8* adr, u32 size)
{
	return GSPGPU_FlushDataCache(adr, size);
}*/

int main()
{
	u32 *paramblk;
	u32 *tmpbuf;
	u32 tmp=0;
	Result ret=0;
	Handle *fsuserHandle;

	gfxInitDefault();//Reset gfx/whatever, so that screens are black etc.
	gfxExit();

	paramblk = linearMemAlign(0xc000, 0x1000);
	if(paramblk==NULL)return 1;

	tmpbuf = memalign(0x1000, 0x10000);
	if(tmpbuf==NULL)return 2;

	if((ret = svcControlMemory(&tmp, (u32)tmpbuf, 0x0, 0x10000, MEMOP_FREE, 0x0))!=0)return 3;

	fsuserHandle = fsGetSessionHandle();
	paramblk[0x50>>2] = *fsuserHandle;

	//paramblk[0x1c>>2] = (u32)gxlowcmd_4;
	//paramblk[0x20>>2] = (u32)gsp_flushdcache;
	paramblk[0x48>>2] = 0x48;//0xc9;//flags
	//paramblk[0x58>>2] = (u32)&gspGpuHandle;

	svcSleepThread(3000000000);

	haxpayload(paramblk);

	return 0;
}

