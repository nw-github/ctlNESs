use std::span::SpanMut;

pub use bindings::WindowEvent;

use bindings::*;

pub union Scancode: u32 {
    Unknown,
    _Pad0,
    _Pad1,
    _Pad2,
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    Num1,
    Num2,
    Num3,
    Num4,
    Num5,
    Num6,
    Num7,
    Num8,
    Num9,
    Num0,
    Return,
    Escape,
    Backspace,
    Tab,
    Space,

    impl std::hash::Hash {
        fn hash<H: std::hash::Hasher>(this, h: *mut H) {
            (*this as u32).hash(h);
        }
    }

    pub fn ==(this, rhs: *Scancode): bool {
        (*this as u32) == (*rhs as u32)
    }
}

pub struct KeyEvent {
    pub timestamp: u32,
    pub window_id: u32,
    pub state: u8,
    pub repeat: bool,
    pub scancode: Scancode,
    pub keycode: i32,
    pub modifiers: u16,

    fn from_raw(event: SDL_KeyboardEvent): This {
        KeyEvent(
            timestamp: event.timestamp,
            window_id: event.windowID,
            state: event.state,
            repeat: event.repeat != 0,
            scancode: event.keysym.scancode,
            keycode: event.keysym.sym,
            modifiers: event.keysym.modifiers,
        )
    }
}

pub union SdlEvent {
    Quit,
    KeyDown(KeyEvent),
    KeyUp(KeyEvent),
    Window(SDL_WindowEvent),
}

pub struct Color {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,

    pub fn rgb(r: u8, g: u8, b: u8): Color {
        Color(r:, g:, b:, a: 255)
    }

    pub fn rgb32(val: u32): Color {
        Color(
            r: ((val >> 16) & 0xff) as! u8,
            g: ((val >> 8) & 0xff) as! u8,
            b: (val & 0xff) as! u8,
            a: 0xff,
        )
    }

    pub fn to_abgr32(this): u32 {
        (this.r as u32) | (this.g as u32 << 8) | (this.b as u32 << 16) | (this.a as u32 << 24)
    }
}

pub struct Window {
    window:   *mut SDL_Window,
    renderer: Renderer,
    width:    c_int,
    height:   c_int,
    scale:    c_int,

    pub fn new(kw title: str, kw width: u32, kw height: u32, kw scale: u32, kw vsync: bool): ?This {
        guard unsafe SDL_Init(SDL_INIT_VIDEO) == 0 else {
            return null;
        }

        let width = width as! c_int;
        let height = height as! c_int;
        let scale = scale as! c_int;

        guard unsafe SDL_CreateWindow(
            title.as_raw().cast(), // zero terminate
            x: SDL_WINDOWPOS_CENTERED,
            y: SDL_WINDOWPOS_CENTERED,
            w: width * scale,
            h: height * scale,
            flags: 0,
        ) is ?window else {
            unsafe SDL_Quit();
            return null;
        }

        guard Window::create_renderer(window, width, height, scale, vsync) is ?mut renderer else {
            unsafe {
                SDL_DestroyWindow(window);
                SDL_Quit();
            }
            return null;
        }

        Window(window:, width:, height:, scale:, renderer:)
    }

    fn create_renderer(wnd: *mut SDL_Window, w: c_int, h: c_int, s: c_int, vsync: bool): ?Renderer {
        // accelerated | vsync (0x2 | 0x4)
        guard unsafe SDL_CreateRenderer(wnd, -1, 0x2 | (vsync as u32 << 2)) is ?renderer else {
            return null;
        }

        guard unsafe SDL_CreateTexture(
            renderer,
            SDL_PIXELFORMAT_ABGR8888,
            SDL_TEXTUREACCESS_STREAMING,
            w,
            h,
        ) is ?texture else {
            unsafe SDL_DestroyRenderer(renderer);
            return null;
        }

        unsafe SDL_RenderSetLogicalSize(renderer, w * s, h * s);
        Renderer(renderer:, texture:)
    }

    pub fn deinit(mut this) {
        this.renderer.deinit();

        unsafe SDL_DestroyWindow(this.window);
        unsafe SDL_Quit(); // TODO: this should be somewhere else
    }

    pub fn draw_scaled(mut this, src: [u32..]): bool {
        mut dst: ^mut void;
        mut pitch = 0ic;
        guard unsafe SDL_LockTexture(this.renderer.texture, null, &mut dst, &mut pitch) == 0 else {
            return false;
        }

        let dst = unsafe SpanMut::new(dst.cast::<u32>(), (pitch / 4 * this.height) as! uint);
        let min = dst.len().min(src.len());
        dst[..min] = src[..min];

        unsafe SDL_UnlockTexture(this.renderer.texture);
        true
    }

    pub fn set_title<T: std::fmt::Format>(mut this, title: T) {
        mut builder = std::fmt::StringBuilder::new();
        write(&mut builder, title);
        write(&mut builder, "\0");
        unsafe SDL_SetWindowTitle(this.window, builder.into_str().as_raw().cast());
    }

    pub fn poll_event(mut this): ?SdlEvent {
        mut event = unsafe std::mem::zeroed::<SDL_Event>();
        if unsafe SDL_PollEvent(&mut event) == 0 {
            return null;
        }
        unsafe {
            if event.typ == SDL_QUIT {
                SdlEvent::Quit
            } else if event.typ == SDL_KEYDOWN {
                SdlEvent::KeyDown(KeyEvent::from_raw(event.key))
            } else if event.typ == SDL_KEYUP {
                SdlEvent::KeyUp(KeyEvent::from_raw(event.key))
            } else if event.typ == SDL_WINDOWEVENT {
                SdlEvent::Window(event.window)
            }
        }
    }

    pub fn clear(mut this, color: Color) {
        this.renderer.clear(color);
    }

    pub fn present(mut this) {
        this.renderer.present(this);
    }
}

pub struct Audio {
    device: u32,
    buf: rb::RingBuffer<f32>,

    pub fn new(kw sample_rate: uint, kw buf_size: uint = 1024 * 4): ?*mut This {
        guard unsafe SDL_Init(SDL_INIT_AUDIO) == 0 else {
            return null;
        }

        let self = std::alloc::new(Audio(device: 0, buf: rb::RingBuffer::new(buf_size)));
        let spec = SDL_AudioSpec(
            freq: sample_rate as! c_int,
            format: AUDIO_F32SYS,
            channels: 1,
            samples: (buf_size / 2) as! u16,
            silence: 0,
            size: 0,
            callback: sdl_audio_callback,
            user_data: self as ^mut void, // this might be a problem for the GC
        );
        self.device = unsafe SDL_OpenAudioDevice(null, 0, &spec, null, 0);
        guard self.device != 0 else {
            return null;
        }

        self
    }

    pub fn deinit(mut this) {
        unsafe SDL_CloseAudioDevice(this.device);
    }

    pub fn unpause(mut this) {
        unsafe SDL_PauseAudioDevice(this.device, 0);
    }

    pub fn pause(mut this) {
        unsafe SDL_PauseAudioDevice(this.device, 1);
    }

    pub fn buffer(mut this): *mut rb::RingBuffer<f32> {
        &mut this.buf
    }
}

extern fn sdl_audio_callback(user_data: ?^mut void, samples: ^mut u8, len: c_int) {
    let self = unsafe user_data! as *mut Audio;
    let samples = unsafe SpanMut::new(samples.cast::<f32>(), len as! uint / 4);
    for sample in samples.iter_mut() {
        *sample = self.buf.pop() ?? 0.0;
    }
}

struct Renderer {
    renderer: *mut SDL_Renderer,
    texture: *mut SDL_Texture,

    fn set_scale(mut this, scale: f32): bool {
        unsafe SDL_RenderSetScale(this.renderer, scale, scale) == 0
    }

    fn set_logical_size(mut this, w: c_int, h: c_int): bool {
        unsafe SDL_RenderSetLogicalSize(this.renderer, w, h) == 0
    }

    pub fn set_vsync(mut this, enabled: bool): bool {
        // SDL_GL_SetSwapInterval(enabled as c_int) == 0
        unsafe SDL_RenderSetVSync(this.renderer, enabled as c_int) == 0
    }

    pub fn set_draw_color(mut this, {r, g, b, a}: Color) {
        unsafe SDL_SetRenderDrawColor(this.renderer, r, g, b, a);
    }

    pub fn draw_point(mut this, x: i32, y: i32) {
        unsafe SDL_RenderDrawPoint(this.renderer, x as! c_int, y as! c_int);
    }

    pub fn clear(mut this, color: Color) {
        this.set_draw_color(color);
        unsafe SDL_RenderClear(this.renderer);
    }

    pub fn present(mut this, window: *Window) {
        unsafe SDL_RenderCopy(this.renderer, this.texture, null, &SDL_Rect(
            x: 0,
            y: 0,
            w: window.width * window.scale,
            h: window.height * window.scale,
        ));
        unsafe SDL_RenderPresent(this.renderer);
    }

    pub fn deinit(mut this) {
        unsafe SDL_DestroyTexture(this.texture);
        unsafe SDL_DestroyRenderer(this.renderer);
    }
}

pub fn get_last_error(): str {
    unsafe str::from_cstr_unchecked(SDL_GetError())
}
