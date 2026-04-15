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

fn should_retry_with_fresh_transport(code: i32) -> bool {
    matches!(code, -5 | -6 | -7 | -11 | -12 | -13 | -14)
}

fn rebuild_transport_for_profile(
    sender_secret: [u8; 32],
    profile: TransportProfile,
    init_failure_code: i32,
) -> Result<CachedNostrTransport, i32> {
    let config = config_for_profile(profile);
    let transport = match NostrTransport::new(config, &sender_secret) {
        Ok(transport) => transport,
        Err(_) => return Err(init_failure_code),
    };
    Ok(CachedNostrTransport {
        sender_secret,
        transport,
    })
}

pub(crate) fn with_cached_nostr_transport<R, F>(
    sender_secret: [u8; 32],
    profile: TransportProfile,
    init_failure_code: i32,
    operation: F,
) -> Result<R, i32>
where
    F: Fn(&NostrTransport) -> Result<R, i32>,
{
    let cache = cache_for_profile(profile);
    {
        let mut cached = cache.lock().unwrap();
        let must_recreate = cached
            .as_ref()
            .map(|entry| entry.sender_secret != sender_secret)
            .unwrap_or(true);

        if must_recreate {
            let rebuilt = rebuild_transport_for_profile(sender_secret, profile, init_failure_code)?;
            *cached = Some(rebuilt);
        }
    }

    let first_attempt = {
        let cached = cache.lock().unwrap();
        let entry = cached.as_ref().ok_or(init_failure_code)?;
        operation(&entry.transport)
    };
    match first_attempt {
        Ok(value) => Ok(value),
        Err(code) if should_retry_with_fresh_transport(code) => {
            {
                let mut cached = cache.lock().unwrap();
                let rebuilt =
                    rebuild_transport_for_profile(sender_secret, profile, init_failure_code)?;
                *cached = Some(rebuilt);
            }
            let cached = cache.lock().unwrap();
            let entry = cached.as_ref().ok_or(init_failure_code)?;
            operation(&entry.transport)
        }
        Err(code) => Err(code),
    }
}

pub(crate) fn clear_cached_nostr_transports() {
    *DEFAULT_NOSTR_TRANSPORT.lock().unwrap() = None;
    *QUICK_NOSTR_TRANSPORT.lock().unwrap() = None;
}

#[cfg(test)]
mod tests {
    use super::should_retry_with_fresh_transport;

    #[test]
    fn retryable_transport_codes_match_runtime_delivery_domain() {
        for code in [-5, -6, -7, -11, -12, -13, -14] {
            assert!(should_retry_with_fresh_transport(code));
        }
    }

    #[test]
    fn non_transport_codes_do_not_trigger_retry_rebuild() {
        for code in [-4, -3, -2, -1, 0, 1] {
            assert!(!should_retry_with_fresh_transport(code));
        }
    }
}
