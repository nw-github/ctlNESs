use super::rb::RingBuffer;
use super::emu::NTSC_CLOCK_RATE;

pub struct Mixer {
    sample_rate: f64,
    decim_ratio: f64,
    pitch_ratio: f64 = 1.0,
    fraction: f64 = 0.0,
    average: f64 = 0.0,
    count: f64 = 0.0,
    filters: [Filter; 3],

    pub fn new(sample_rate: f64): This {
        Mixer(
            sample_rate:,
            decim_ratio: NTSC_CLOCK_RATE / sample_rate,
            filters: [
                Filter::hi_pass(90.0, sample_rate),
                Filter::hi_pass(440.0, sample_rate),
                Filter::lo_pass(12000.0, sample_rate),
                // supposed to be 14000, but 14000 + dynamic rate control introduces some weird
                // artifacts with high pitched sounds
            ],
        )
    }

    pub fn process(mut this, buf: *mut RingBuffer<f32>, samples: [f64..], max_delta: ?f64 = 0.005) {
        this.pitch_ratio = if max_delta is ?max_delta {
            let cap = buf.cap() as f64;
            ((cap - 2.0 * buf.len() as f64) / cap) * max_delta + 1.0
        } else {
            1.0
        };
        this.decim_ratio = NTSC_CLOCK_RATE / (this.sample_rate * this.pitch_ratio);

        for sample in samples.iter() {
            this.average += *sample;
            this.count += 1.0;
            while this.fraction <= 0.0 {
                mut sample = *sample;
                for filter in this.filters[..].iter_mut() {
                    filter.apply(&mut sample);
                }

                if buf.push(sample as f32) is ?_ {
                    std::time::sleep(std::time::Duration::from_millis(1));
                }

                this.average = 0.0;
                this.count = 0.0;
                this.fraction += this.decim_ratio;
            }

            this.fraction -= 1.0;
        }
    }
}

pub struct Filter {
    rc: f64,
    dt: f64,
    a: f64,
    x: f64 = 0.0,
    y: f64 = 0.0,
    lo: bool,

    pub fn lo_pass(freq: f64, sample_rate: f64): Filter {
        Filter::new(freq, sample_rate, true)
    }

    pub fn hi_pass(freq: f64, sample_rate: f64): Filter {
        Filter::new(freq, sample_rate, false)
    }

    pub fn apply(mut this, sample: *mut f64) {
        this.y = if this.lo {
            this.a * *sample + (1.0 - this.a) * this.y
        } else {
            this.a * this.y + this.a * (sample - this.x)
        };
        this.x = *sample;
        *sample = this.y;
    }

    fn new(freq: f64, sample_rate: f64, lo: bool): Filter {
        let rc = 1.0 / (2.0 * f64::pi() * freq);
        let dt = 1.0 / sample_rate;
        if lo {
            Filter(rc:, dt:, a: dt / (rc + dt), lo:)
        } else {
            Filter(rc:, dt:, a: rc / (rc + dt), lo:)
        }
    }
}
