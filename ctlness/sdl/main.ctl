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
    window:  *mut SDL_Window,
    surface: *mut SDL_Surface,
    width:   c_int,
    height:  c_int,
    scale:   c_int,

    pub fn new(title: str, width: i32, height: i32, scale: i32): ?This {
        guard SDL_Init(SDL_INIT_VIDEO) == 0 else {
            return null;
        }

        let width = width as! c_int;
        let height = height as! c_int;
        let scale = scale as! c_int;

        let window = if SDL_CreateWindow(
            title.as_raw() as *raw c_char,
            x: SDL_WINDOWPOS_CENTERED,
            y: SDL_WINDOWPOS_CENTERED,
            w: width * scale,
            h: height * scale,
            flags: 0,
        ) is ?window { window } else {
            SDL_Quit();
            return null;
        };

        if SDL_GetWindowSurface(window) is ?surface {
            return Window(window:, surface:, width:, height:, scale:);
        }

        SDL_DestroyWindow(window);
        SDL_Quit();
        null
    }

    pub fn deinit(mut this) {
        SDL_DestroyWindow(this.window);
        SDL_Quit(); // TODO: this should be somewhere else
    }

    pub fn draw_scaled(mut this, pixels: [u32..]): bool {
        let surface = if SDL_CreateRGBSurfaceFrom(
            pixels: pixels.as_raw() as *raw c_void,
            width: this.width,
            height: (pixels.len() / this.width as uint) as! c_int,
            depth: 32,
            pitch: this.width * 4,
            rmask: 0x000000ff,
            gmask: 0x0000ff00,
            bmask: 0x00ff0000,
            amask: 0xff000000,
        ) is ?surface { surface } else { return false; };

        SDL_BlitScaled(surface, null, this.surface, null);
        SDL_UpdateWindowSurface(this.window);
        SDL_FreeSurface(surface);
        true
    }

    pub fn set_title(mut this, title: str) {
        SDL_SetWindowTitle(this.window, title.as_raw() as *raw c_char);
    }

    pub fn poll_event(mut this): ?SdlEvent {
        mut event = unsafe std::mem::zeroed::<SDL_Event>();
        if SDL_PollEvent(&mut event) == 0 {
            return null;
        }
        unsafe {
            if event.typ == SDL_QUIT {
                SdlEvent::Quit
            } else if event.typ == SDL_KEYDOWN {
                SdlEvent::KeyDown(KeyEvent::from_raw(event.key))
            } else if event.typ == SDL_KEYUP {
                SdlEvent::KeyUp(KeyEvent::from_raw(event.key))
            }
        }
    }
}

const BUF_COUNT: uint = 3;
const BUF_SIZE: uint = 1024 * 2;

pub struct Audio {
    device: u32,
    sem: *mut SDL_sem,
    queue: [f32],
    read_buf: uint = 0,
    write_buf: uint = 0,
    write_pos: uint = 0,

    pub fn new(sample_rate: c_int = 48000): ?*mut This {
        guard SDL_Init(SDL_INIT_AUDIO) == 0 else {
            return null;
        }

        guard SDL_CreateSemaphore(BUF_COUNT as! u32 - 1) is ?sem else {
            return null;
        }

        mut self = std::alloc::new(Audio(device: 0, sem:, queue: @[]));
        let spec = SDL_AudioSpec(
            freq: sample_rate,
            format: AUDIO_F32SYS,
            channels: 1,
            samples: BUF_SIZE as! u16,
            silence: 0,
            size: 0,
            callback: Audio::sdl_callback,
            user_data: self as *raw c_void, // this might be a problem for the GC
        );
        self.device = SDL_OpenAudioDevice(null, 0, &spec, null, 0);
        guard self.device != 0 else {
            SDL_DestroySemaphore(sem);
            return null;
        }

        self.queue = @[0.0; BUF_SIZE * BUF_COUNT];
        self
    }

    pub fn deinit(mut this) {
        SDL_CloseAudioDevice(this.device);
        SDL_DestroySemaphore(this.sem);
    }

    pub fn unpause(mut this) {
        SDL_PauseAudioDevice(this.device, 0);
    }

    pub fn pause(mut this) {
        SDL_PauseAudioDevice(this.device, 1);
    }

    pub fn queue_len(this): uint {
        let free = SDL_SemValue(this.sem) as uint * BUF_SIZE + (BUF_SIZE - this.write_pos);
        BUF_SIZE - BUF_COUNT - free
    }

    pub fn write(mut this, mut samples: [f32..]) {
        while !samples.is_empty() {
            let n = (BUF_SIZE - this.write_pos).min(samples.len());
            this.queue[this.write_buf * BUF_SIZE + this.write_pos..][..n] = samples[..n];

            samples = samples[n..];
            this.write_pos += n;

            if this.write_pos >= BUF_SIZE {
                this.write_pos = 0;
                this.write_buf = (this.write_buf + 1) % BUF_COUNT;
                SDL_SemWait(this.sem);
            }
        }
    }

    fn sdl_callback(user_data: ?*raw c_void, samples: *raw u8, len: c_int) {
        let self = unsafe user_data! as *mut Audio;
        let samples = unsafe std::span::SpanMut::new(samples as *raw f32, len as uint / 4);
        guard SDL_SemValue(self.sem) < BUF_COUNT as! u32 - 1 else {
            return samples.fill(0.0);
        }

        samples[..] = self.queue[self.read_buf * BUF_SIZE..][..samples.len()];
        self.read_buf = (self.read_buf + 1) % BUF_COUNT;
        SDL_SemPost(self.sem);
    }
}

pub struct Renderer {
    renderer: *mut SDL_Renderer,

    pub fn set_scale(mut this, scale: f32): bool {
        SDL_RenderSetScale(this.renderer, scale, scale) == 0
    }

    pub fn set_draw_color(mut this, {r, g, b, a}: Color) {
        SDL_SetRenderDrawColor(this.renderer, r, g, b, a);
    }

    pub fn draw_point(mut this, x: i32, y: i32) {
        SDL_RenderDrawPoint(this.renderer, x as! c_int, y as! c_int);
    }

    pub fn clear(mut this, color: Color) {
        this.set_draw_color(color);
        SDL_RenderClear(this.renderer);
    }

    pub fn present(mut this) {
        SDL_RenderPresent(this.renderer);
    }

    pub fn deinit(mut this) {
        SDL_DestroyRenderer(this.renderer);
    }
}

pub fn get_last_error(): str {
    let error = SDL_GetError();
    unsafe str::from_utf8_unchecked(std::span::Span::new(
        error as *raw u8, 
        std::intrin::strlen(error) as! uint,
    ))
}

pub fn delay(ms: u32) {
    SDL_Delay(ms);
}

pub fn get_ticks(): u64 {
    SDL_GetTicks64()
}
