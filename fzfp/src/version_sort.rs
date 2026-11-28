use std::cmp::Ordering;
use std::ffi::OsString;
use std::os::unix::ffi::OsStrExt;

pub(super) struct VersionName {
    pub(super) filename: OsString,
    stem_end: usize,
}

impl VersionName {
    pub(super) fn new(filename: OsString) -> Self {
        let stem_end = stem_end(filename.as_bytes());
        Self { filename, stem_end }
    }

    pub(super) fn compare(&self, other: &Self) -> Ordering {
        let left = self.filename.as_bytes();
        let right = other.filename.as_bytes();
        // GNU ls -v lists hidden names first and compares stems before extensions.
        (!left.starts_with(b"."))
            .cmp(&(!right.starts_with(b".")))
            .then_with(|| compare_versions(&left[..self.stem_end], &right[..other.stem_end]))
            .then_with(|| compare_versions(left, right))
            .then_with(|| left.cmp(right))
    }
}

fn stem_end(mut name: &[u8]) -> usize {
    while let Some(dot) = name.iter().rposition(|&byte| byte == b'.') {
        let Some((&first, rest)) = name[dot + 1..].split_first() else {
            break;
        };
        if dot == 0
            || !(first.is_ascii_alphabetic() || first == b'~')
            || !rest
                .iter()
                .all(|byte| byte.is_ascii_alphanumeric() || *byte == b'~')
        {
            break;
        }
        name = &name[..dot];
    }
    name.len()
}

fn compare_versions(mut left: &[u8], mut right: &[u8]) -> Ordering {
    while !left.is_empty() || !right.is_empty() {
        while left.first().is_some_and(|byte| !byte.is_ascii_digit())
            || right.first().is_some_and(|byte| !byte.is_ascii_digit())
        {
            if left.first() != right.first() {
                return letter_order(left.first().copied())
                    .cmp(&letter_order(right.first().copied()));
            }
            left = &left[1..];
            right = &right[1..];
        }

        let left_digits = take_number(&mut left);
        let right_digits = take_number(&mut right);
        let order = left_digits
            .len()
            .cmp(&right_digits.len())
            .then_with(|| left_digits.cmp(right_digits));
        if order != Ordering::Equal {
            return order;
        }
    }
    Ordering::Equal
}

fn letter_order(byte: Option<u8>) -> i16 {
    match byte {
        Some(b'~') => -1,
        None | Some(b'0'..=b'9') => 0,
        Some(byte) if byte.is_ascii_alphabetic() => i16::from(byte),
        Some(byte) => i16::from(byte) + 256,
    }
}

fn take_number<'a>(name: &mut &'a [u8]) -> &'a [u8] {
    let length = name.iter().take_while(|byte| byte.is_ascii_digit()).count();
    let (digits, rest) = name.split_at(length);
    *name = rest;
    let zeroes = digits.iter().take_while(|&&byte| byte == b'0').count();
    &digits[zeroes..]
}
