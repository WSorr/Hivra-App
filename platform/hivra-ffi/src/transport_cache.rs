use super::*;
use once_cell::sync::Lazy;
use std::sync::Mutex;

#[derive(Clone, Copy)]
pub(crate) enum TransportProfile {
    Default,
    Quick,
}

struct CachedNostrTransport {
    sender_secret: [u8; 32],
    transport: NostrTransport,
}

static DEFAULT_NOSTR_TRANSPORT: Lazy<Mutex<Option<CachedNostrTransport>>> =
    Lazy::new(|| Mutex::new(None));
static QUICK_NOSTR_TRANSPORT: Lazy<Mutex<Option<CachedNostrTransport>>> =
    Lazy::new(|| Mutex::new(None));

fn cache_for_profile(profile: TransportProfile) -> &'static Mutex<Option<CachedNostrTransport>> {
    match profile {
        TransportProfile::Default => &DEFAULT_NOSTR_TRANSPORT,
        TransportProfile::Quick => &QUICK_NOSTR_TRANSPORT,
    }
}

fn config_for_profile(profile: TransportProfile) -> NostrConfig {
    match profile {
        TransportProfile::Default => NostrConfig::default(),
        TransportProfile::Quick => NostrConfig::quick_launch(),
    }
}

pub(crate) fn with_cached_nostr_transport<R, F>(
    sender_secret: [u8; 32],
    profile: TransportProfile,
    init_failure_code: i32,
    operation: F,
) -> Result<R, i32>
where
    F: FnOnce(&NostrTransport) -> Result<R, i32>,
{
    let cache = cache_for_profile(profile);
    let mut cached = cache.lock().unwrap();

    let must_recreate = cached
        .as_ref()
        .map(|entry| entry.sender_secret != sender_secret)
        .unwrap_or(true);

    if must_recreate {
        let config = config_for_profile(profile);
        let transport = match NostrTransport::new(config, &sender_secret) {
            Ok(transport) => transport,
            Err(_) => return Err(init_failure_code),
        };
        *cached = Some(CachedNostrTransport {
            sender_secret,
            transport,
        });
    }

    let entry = cached.as_ref().ok_or(init_failure_code)?;
    operation(&entry.transport)
}

pub(crate) fn clear_cached_nostr_transports() {
    *DEFAULT_NOSTR_TRANSPORT.lock().unwrap() = None;
    *QUICK_NOSTR_TRANSPORT.lock().unwrap() = None;
}
