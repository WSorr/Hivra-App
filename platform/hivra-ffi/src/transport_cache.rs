use super::*;
use once_cell::sync::Lazy;
use std::sync::{Arc, Mutex};

#[derive(Clone, Copy)]
pub(crate) enum TransportProfile {
    Default,
    Quick,
}

struct CachedNostrTransport {
    sender_secret: [u8; 32],
    transport: Arc<NostrTransport>,
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

fn should_retry_with_fresh_transport(profile: TransportProfile, code: i32) -> bool {
    // A quick operation backs a user action. Repeating a failed relay
    // handshake here turns a three-second publish budget into six seconds;
    // durable Core effects are instead retried by the delivery outbox.
    if matches!(profile, TransportProfile::Quick) {
        return false;
    }

    // Background/default operations may rebuild a stale session once.
    matches!(code, -5 | -11 | -12 | -14)
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
        transport: Arc::new(transport),
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

    // The cache lock protects replacement of the active transport only. A
    // relay fetch may wait for seconds, so holding it while publishing would
    // unnecessarily serialize UI sends behind background receives.
    let transport = {
        let cached = cache.lock().unwrap();
        let entry = cached.as_ref().ok_or(init_failure_code)?;
        Arc::clone(&entry.transport)
    };
    let first_attempt = operation(transport.as_ref());
    match first_attempt {
        Ok(value) => Ok(value),
        Err(code) if should_retry_with_fresh_transport(profile, code) => {
            {
                let mut cached = cache.lock().unwrap();
                let rebuilt =
                    rebuild_transport_for_profile(sender_secret, profile, init_failure_code)?;
                *cached = Some(rebuilt);
            }
            let transport = {
                let cached = cache.lock().unwrap();
                let entry = cached.as_ref().ok_or(init_failure_code)?;
                Arc::clone(&entry.transport)
            };
            operation(transport.as_ref())
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
    use super::{should_retry_with_fresh_transport, TransportProfile};

    #[test]
    fn default_profile_retries_stale_transport_codes() {
        for code in [-5, -11, -12, -14] {
            assert!(should_retry_with_fresh_transport(
                TransportProfile::Default,
                code
            ));
        }
    }

    #[test]
    fn quick_profile_never_repeats_interactive_publish() {
        for code in [-14, -12, -11, -5, -4, -3, -2, -1, 0, 1] {
            assert!(!should_retry_with_fresh_transport(
                TransportProfile::Quick,
                code
            ));
        }
    }

    #[test]
    fn default_profile_does_not_retry_non_transport_codes() {
        for code in [-13, -7, -6, -4, -3, -2, -1, 0, 1] {
            assert!(!should_retry_with_fresh_transport(
                TransportProfile::Default,
                code
            ));
        }
    }
}
