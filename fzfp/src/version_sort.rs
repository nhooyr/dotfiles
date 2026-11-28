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
    while let Some(dot) = name.iter().rposition(|&byte| byte == b'.')
        && dot > 0
        && let [first, rest @ ..] = &name[dot + 1..]
        && (first.is_ascii_alphabetic() || *first == b'~')
        && rest
            .iter()
            .all(|byte| byte.is_ascii_alphanumeric() || *byte == b'~')
    {
        name = &name[..dot];
    }
    name.len()
}

fn compare_versions(mut left: &[u8], mut right: &[u8]) -> Ordering {
    while !left.is_empty() || !right.is_empty() {
        let shared_text = left
            .iter()
            .zip(right)
            .take_while(|(a, b)| a == b && !a.is_ascii_digit())
            .count();
        left = &left[shared_text..];
        right = &right[shared_text..];

        let order =
            version_weight(left.first().copied()).cmp(&version_weight(right.first().copied()));
        if order != Ordering::Equal {
            return order;
        }

        let (left_digits, left_tail) = split_number(left);
        let (right_digits, right_tail) = split_number(right);
        let order = (left_digits.len(), left_digits).cmp(&(right_digits.len(), right_digits));
        if order != Ordering::Equal {
            return order;
        }
        (left, right) = (left_tail, right_tail);
    }
    Ordering::Equal
}

fn version_weight(byte: Option<u8>) -> i16 {
    match byte {
        Some(b'~') => -1,
        None | Some(b'0'..=b'9') => 0,
        Some(byte) if byte.is_ascii_alphabetic() => i16::from(byte),
        Some(byte) => i16::from(byte) + 256,
    }
}

fn split_number(name: &[u8]) -> (&[u8], &[u8]) {
    let length = name.iter().take_while(|byte| byte.is_ascii_digit()).count();
    let (digits, rest) = name.split_at(length);
    let zeroes = digits.iter().take_while(|&&byte| byte == b'0').count();
    (&digits[zeroes..], rest)
}
