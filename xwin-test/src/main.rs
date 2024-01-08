extern crate winapi;
extern crate user32;

use std::{
    ffi::CString,
    ptr,
};
use user32::MessageBoxA;
use winapi::um::winuser::{ MB_OK, MB_ICONINFORMATION };

fn main() {
    let text = CString::new("Hello, World!").unwrap();
    let caption = CString::new("MessageBoxA Example").unwrap();

    unsafe {
        MessageBoxA(ptr::null_mut(), text.as_ptr(), caption.as_ptr(), MB_OK | MB_ICONINFORMATION);
    }
}
