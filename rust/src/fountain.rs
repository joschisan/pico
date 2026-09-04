use flutter_rust_bridge::frb;
use picomint_client::ecash::Ecash;
use picomint_fountain::{FountainDecoder, FountainEncoder, Fragment};

use crate::EcashWrapper;

#[frb(opaque)]
pub struct EcashEncoder(FountainEncoder);

impl EcashEncoder {
    #[frb(sync)]
    pub fn new(ecash: &EcashWrapper) -> Self {
        Self(FountainEncoder::new(&ecash.0, 512))
    }

    #[frb]
    pub fn next_fragment(&mut self) -> String {
        picomint_base32::encode(&self.0.next_fragment())
    }
}

#[frb(opaque)]
pub struct EcashDecoder {
    inner: FountainDecoder<Ecash>,
}

impl EcashDecoder {
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            inner: FountainDecoder::default(),
        }
    }

    #[frb(sync)]
    pub fn add_fragment(&mut self, fragment: &str) -> Option<EcashWrapper> {
        let decoded = picomint_base32::decode::<Fragment>(fragment).ok()?;

        self.inner.add_fragment(&decoded).map(EcashWrapper)
    }
}
