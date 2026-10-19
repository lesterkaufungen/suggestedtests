//! Checks the committed `native/prebuilt/` binaries without running them:
//! each is built for its directory's OS, CPU and libc, and exports what the
//! C header and `src/jni.rs` declare. Every package loads (or copies) these
//! files, so a stale or misbuilt one breaks all of them at once.

mod common;

use common::*;

#[test]
fn every_prebuilt_matches_its_target() {
    let exports = library_exports();
    let mut problems = Vec::new();
    for t in TARGETS {
        for file in t.files() {
            let path = native_dir().join("prebuilt").join(t.dir).join(file);
            match std::fs::read(&path) {
                Ok(bytes) => problems.extend(
                    check(t, file, &bytes, &exports)
                        .into_iter()
                        .map(|p| format!("{}/{file}: {p}", t.dir)),
                ),
                Err(e) => problems.push(format!("{}/{file}: {e}", t.dir)),
            }
        }
    }
    assert!(
        problems.is_empty(),
        "native/prebuilt/ is stale or misbuilt (rebuild it, see CLAUDE.md):\n{}",
        problems.join("\n")
    );
}

#[test]
fn prebuilt_has_exactly_the_shipped_targets() {
    let dir = native_dir().join("prebuilt");
    let mut found: Vec<String> = std::fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    found.sort();
    let mut expected: Vec<String> = TARGETS.iter().map(|t| t.dir.to_string()).collect();
    expected.sort();
    assert_eq!(found, expected);
    assert_eq!(TARGETS.len(), 19);
}

#[test]
fn reads_the_exports_from_the_sources() {
    let header = header_functions();
    for f in [
        "st_abi_version",
        "st_platform",
        "st_environment",
        "st_load_state",
    ] {
        assert!(header.contains(f), "{f} not found in {header:?}");
    }
    let jni = jni_functions();
    assert!(
        jni.contains(
            "Java_io_github_lesterkaufungen_suggestedtests_internal_NativeBridge_abiVersion"
        ),
        "{jni:?}"
    );
    assert!(jni.iter().all(|f| f.starts_with("Java_")), "{jni:?}");
}

#[test]
fn rejects_files_that_are_not_libraries() {
    assert!(Binary::parse(b"").is_err());
    assert!(Binary::parse(b"<!DOCTYPE html>").is_err());
    // Truncated headers fail instead of panicking.
    assert!(Binary::parse(b"\x7fELF\x02\x01").is_err());
    assert!(Binary::parse(b"MZ").is_err());
}

fn problems_as(dir: &str, file: &str, from_dir: &str) -> String {
    let t = TARGETS.iter().find(|t| t.dir == dir).unwrap();
    let bytes = std::fs::read(native_dir().join("prebuilt").join(from_dir).join(file)).unwrap();
    check(t, file, &bytes, &library_exports()).join("\n")
}

#[test]
fn flags_a_file_in_the_wrong_directory() {
    let so = "libsuggestedtests_native.so";
    let wrong_cpu = problems_as("linux-x64", so, "linux-arm64");
    assert!(
        wrong_cpu.contains("built for Elf 64-bit arch 2"),
        "{wrong_cpu}"
    );
    let glibc_as_musl = problems_as("linux-x64-musl", so, "linux-x64");
    assert!(
        glibc_as_musl.contains("not linked against musl"),
        "{glibc_as_musl}"
    );
    let musl_as_glibc = problems_as("linux-x64", so, "linux-x64-musl");
    assert!(
        musl_as_glibc.contains("doesn't need libc.so.6"),
        "{musl_as_glibc}"
    );
    let small_pages = problems_as("android-x86_64", so, "linux-x64-musl");
    assert!(small_pages.contains("16 KB pages"), "{small_pages}");
    let soft_float = problems_as("linux-arm", so, "android-armeabi-v7a");
    assert!(soft_float.contains("soft float ABI"), "{soft_float}");
    let right_place = problems_as("linux-x64", NODE_ADDON, "linux-x64");
    assert!(right_place.is_empty(), "{right_place}");
}

#[test]
fn flags_missing_and_unexpected_exports() {
    let t = &TARGETS[0];
    let bytes = std::fs::read(native_dir().join("prebuilt").join(t.dir).join(t.library())).unwrap();
    let mut exports = library_exports();
    exports.remove("st_platform");
    exports.insert("st_not_built_yet".to_string());
    let problems = check(t, t.library(), &bytes, &exports).join("\n");
    assert!(
        problems.contains(r#"missing ["st_not_built_yet"], unexpected ["st_platform"]"#),
        "{problems}"
    );
}

#[test]
fn host_has_a_prebuilt() {
    // Every machine these tests run on is one of the shipped targets.
    assert!(host().is_some(), "no prebuilt for this machine");
}
