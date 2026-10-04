//! Local formatters; included inside the generated statement's block scope.
#![allow(dead_code)]
use std::fmt::Debug;

pub fn object_log<T: Debug + ?Sized>(marker: &str, label: &str, value: &T) {
    eprintln!(" {} object │ {}", marker, label);
    for line in format!("{:#?}", value).lines() {
        eprintln!("    {}", line);
    }
}

#[track_caller]
pub fn fail<T: Debug + ?Sized>(marker: &str, condition: &str, observed: &T) -> ! {
    let location = std::panic::Location::caller();
    eprintln!(
        "🧪 {} assert │ condition failed\n    │\n    │  expected   {}",
        marker, condition
    );
    let details = format!("{:#?}", observed);
    for (index, line) in details.lines().enumerate() {
        eprintln!(
            "    │  {}{}",
            if index == 0 {
                "observed   "
            } else {
                "           "
            },
            line
        );
    }
    eprintln!(
        "    │  location   {}:{}\n    ╰─ FAILED",
        location.file(),
        location.line()
    );
    panic!("{}", condition);
}

pub fn stack_log(marker: &str) {
    // Stable Rust exposes Backtrace through Display, not structured frame access.
    // Keep native frames/symbols intact instead of fabricating a call hierarchy.
    eprintln!(
        " {} stack │ native Rust backtrace\n{}",
        marker,
        std::backtrace::Backtrace::force_capture()
    );
}
