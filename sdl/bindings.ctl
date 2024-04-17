use super::Scancode;

pub union SDL_Window {}
pub union SDL_Renderer {}
pub union SDL_Texture {}
pub union SDL_Surface {}
pub union SDL_sem {}

pub struct SDL_AudioSpec {
    pub freq: c_int,
    pub format: u16,
    pub channels: u8,
    pub silence: u8,
    pub samples: u16,
    pub size: u32,
    pub callback: ?fn(?*raw c_void, *raw u8, c_int),
    pub user_data: ?*raw c_void,
}

pub struct SDL_Keysym {
    pub scancode: Scancode,
    pub sym: i32,
    pub modifiers: u16,
    pub unused: u32,
}

pub struct SDL_KeyboardEvent {
    pub typ: u32,
    pub timestamp: u32,
    pub windowID: u32,
    pub state: u8,
    pub repeat: u8,
    pub pad2: u8,
    pub pad3: u8,
    pub keysym: SDL_Keysym,
}

pub unsafe union SDL_Event {
    typ: u32,
    key: SDL_KeyboardEvent,
    _pad: [u8; 52],
}

pub struct SDL_Rect {
    pub x: c_int,
    pub y: c_int,
    pub w: c_int,
    pub h: c_int,
}

pub const SDL_INIT_VIDEO: u32 = 0x20;
pub const SDL_INIT_AUDIO: u32 = 0x10;

pub const SDL_QUIT: u32 = 0x100;
pub const SDL_KEYDOWN: u32 = 0x300;
pub const SDL_KEYUP: u32   = 0x301;

// pub const AUDIO_S16SYS: u16 = 0x8010;
pub const AUDIO_F32SYS: u16 = 0x8120;

// pub const SDL_PIXELFORMAT_ABGR8888: u32 = 376840196;
// 
// pub const SDL_TEXTUREACCESS_STREAMING: c_int = 1;

pub const SDL_WINDOWPOS_CENTERED: c_int = 0x2fff0000;
// pub const SDL_WINDOWPOS_UNDEFINED: c_int = 0x1fff0000;

pub import fn SDL_Init(flags: u32): c_int;
pub import fn SDL_CreateWindow(
    title: *raw c_char,
    kw x: c_int,
    kw y: c_int,
    kw w: c_int,
    kw h: c_int,
    flags: u32,
): ?*mut SDL_Window;
pub import fn SDL_CreateWindowAndRenderer(
    width:    c_int,
    height:   c_int,
    flags:    u32,
    window:   *mut ?*mut SDL_Window,
    renderer: *mut ?*mut SDL_Renderer,
): c_int;
pub import fn SDL_DestroyWindow(window: *mut SDL_Window);
pub import fn SDL_UpdateWindowSurface(window: *mut SDL_Window): c_int;

pub import fn SDL_SetRenderDrawColor(renderer: *mut SDL_Renderer, r: u8, g: u8, b: u8, a: u8): c_int;
pub import fn SDL_RenderClear(renderer: *mut SDL_Renderer): c_int;
pub import fn SDL_RenderDrawPoint(renderer: *mut SDL_Renderer, x: c_int, y: c_int): c_int;
pub import fn SDL_RenderPresent(renderer: *mut SDL_Renderer);
pub import fn SDL_DestroyRenderer(renderer: *mut SDL_Renderer);
pub import fn SDL_RenderSetScale(renderer: *mut SDL_Renderer, x: f32, y: f32): c_int;
pub import fn SDL_RenderCopy(
    renderer: *mut SDL_Renderer,
    texture:  *mut SDL_Texture,
    src:      ?*SDL_Rect,
    dst:      ?*SDL_Rect,
): c_int;
pub import fn SDL_CreateTexture(
    renderer: *mut SDL_Renderer,
    format:   u32,
    access:   c_int,
    w:        c_int,
    h:        c_int,
): ?*mut SDL_Texture;

pub import fn SDL_LockTexture(
    texture: *mut SDL_Texture,
    rect:    ?*SDL_Rect,
    pixels:  *raw *raw c_void,
    pitch:   *mut c_int,
): c_int;
pub import fn SDL_UnlockTexture(texture: *mut SDL_Texture);
pub import fn SDL_DestroyTexture(texture: *mut SDL_Texture);

pub import fn SDL_PollEvent(event: *mut SDL_Event): c_int;
pub import fn SDL_GetTicks64(): u64;
pub import fn SDL_Quit();
pub import fn SDL_GetError(): *c_char;
pub import fn SDL_Delay(ms: u32);

pub import fn SDL_SetWindowTitle(window: *mut SDL_Window, title: *raw c_char);
pub import fn SDL_GetWindowSurface(window: *mut SDL_Window): ?*mut SDL_Surface;
pub import fn SDL_CreateRGBSurfaceFrom(
    pixels: *raw c_void,
    kw width:  c_int,
    kw height: c_int,
    kw depth:  c_int,
    kw pitch:  c_int,
    kw rmask:  u32,
    kw gmask:  u32,
    kw bmask:  u32,
    kw amask:  u32,
): ?*mut SDL_Surface;
#(c_name(SDL_UpperBlitScaled))
pub import fn SDL_BlitScaled(
    src:     *mut SDL_Surface,
    srcrect: ?*SDL_Rect,
    dst:     *mut SDL_Surface,
    dstrect: ?*mut SDL_Rect,
): c_int;
pub import fn SDL_FreeSurface(surface: *mut SDL_Surface);

pub import fn SDL_OpenAudioDevice(
    device:          ?*c_char,
    is_capture:      c_int,
    desired:         *SDL_AudioSpec,
    obtained:        ?*mut SDL_AudioSpec,
    allowed_changes: c_int,
): u32;
pub import fn SDL_PauseAudioDevice(dev: u32, pause_on: c_int);
pub import fn SDL_QueueAudio(dev: u32, data: *c_void, len: u32): c_int;
pub import fn SDL_ClearQueuedAudio(dev: u32);
pub import fn SDL_CloseAudioDevice(dev: u32);

pub import fn SDL_CreateSemaphore(val: u32): ?*mut SDL_sem;
pub import fn SDL_DestroySemaphore(sem: *mut SDL_sem);
pub import fn SDL_SemWait(sem: *mut SDL_sem): c_int;
pub import fn SDL_SemValue(sem: *mut SDL_sem): u32;
pub import fn SDL_SemPost(sem: *mut SDL_sem): c_int;
