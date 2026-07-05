use super::*;
use std::sync::{Mutex, OnceLock};

static LAST_DELIVERY_RECEIPTS: OnceLock<Mutex<Vec<LabeledDeliveryReceipt>>> = OnceLock::new();

#[derive(Clone, serde::Serialize)]
struct LabeledDeliveryReceipt {
    label: String,
    receipt: DeliveryReceipt,
}

fn delivery_receipts_cell() -> &'static Mutex<Vec<LabeledDeliveryReceipt>> {
    LAST_DELIVERY_RECEIPTS.get_or_init(|| Mutex::new(Vec::new()))
}

pub(crate) fn clear_delivery_receipts() {
    if let Ok(mut guard) = delivery_receipts_cell().lock() {
        guard.clear();
    }
}

pub(crate) fn record_delivery_receipt(label: &str, receipt: DeliveryReceipt) {
    if let Ok(mut guard) = delivery_receipts_cell().lock() {
        guard.push(LabeledDeliveryReceipt {
            label: label.to_string(),
            receipt,
        });
    }
}

#[no_mangle]
pub unsafe extern "C" fn hivra_last_delivery_receipts_json() -> *mut c_char {
    let receipts = match delivery_receipts_cell().lock() {
        Ok(guard) => guard.clone(),
        Err(_) => Vec::new(),
    };
    let payload = serde_json::json!({
        "schema_version": 1,
        "receipts": receipts,
    });
    match CString::new(payload.to_string()) {
        Ok(value) => value.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}
