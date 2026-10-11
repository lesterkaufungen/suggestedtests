// Bundles the Rust bridge in `native/` as a code asset.
//
// Resolution order for the target OS / architecture (/ libc on Linux):
//  1. The precompiled library in `native/prebuilt/<os>-<arch>[-musl]/`.
//     This is the default and never touches Rust or cargo.
//  2. Only if no precompiled library exists for the platform: `cargo build`
//     of `native/`, when `cargo` is on PATH.
//  3. Otherwise nothing: the package still works, but
//     `SystemProbe.isAvailable` is false and native-only helpers skip or fail
//     with an explanation.
//
// On Linux the libc of the running Dart VM decides between the glibc
// (`linux-x64`, needs glibc >= 2.17) and musl (`linux-x64-musl`) builds: a
// library linked against one libc cannot be loaded into a process using the
// other.
//
// To force a source build while editing the Rust code, set in the root
// package's pubspec.yaml:
//
//   hooks:
//     user_defines:
//       suggestedtests:
//         build_from_source: true
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _libName = 'suggestedtests_native';
const _assetName = 'src/native/bindings.dart';

/// Rust target triple per (OS, architecture, musl).
final _rustTargets = {
  (OS.linux, Architecture.x64, false): 'x86_64-unknown-linux-gnu',
  (OS.linux, Architecture.arm64, false): 'aarch64-unknown-linux-gnu',
  (OS.linux, Architecture.x64, true): 'x86_64-unknown-linux-musl',
  (OS.linux, Architecture.arm64, true): 'aarch64-unknown-linux-musl',
  (OS.macOS, Architecture.x64, false): 'x86_64-apple-darwin',
  (OS.macOS, Architecture.arm64, false): 'aarch64-apple-darwin',
  (OS.windows, Architecture.x64, false): 'x86_64-pc-windows-msvc',
  (OS.windows, Architecture.arm64, false): 'aarch64-pc-windows-msvc',
};

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final os = input.config.code.targetOS;
    final arch = input.config.code.targetArchitecture;
    final musl = os == OS.linux && _hostUsesMusl();
    final fileName = os.dylibFileName(_libName);
    final fromSource = input.userDefines['build_from_source'] == true;

    final platformDir = '${os.name}-${arch.name}${musl ? '-musl' : ''}';
    final prebuilt =
        input.packageRoot.resolve('native/prebuilt/$platformDir/$fileName');

    final Uri? library;
    if (!fromSource && File.fromUri(prebuilt).existsSync()) {
      library = prebuilt;
      output.dependencies.add(prebuilt);
    } else {
      library = await _cargoBuild(input, output, os, arch, musl, fileName);
    }
    if (library == null) return;

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: _assetName,
        linkMode: DynamicLoadingBundled(),
        file: library,
      ),
    );
  });
}

/// Whether the Dart VM running this hook (the same SDK that will load the
/// library) is linked against musl. Reads the ELF `PT_INTERP` of the
/// executable, e.g. `/lib/ld-musl-x86_64.so.1` vs `/lib64/ld-linux-x86-64.so.2`.
bool _hostUsesMusl() {
  final interpreter = _elfInterpreter(Platform.resolvedExecutable);
  if (interpreter != null) return interpreter.contains('musl');
  // Static or unreadable executable: fall back to what the system provides.
  final hasGlibc = File('/lib64/ld-linux-x86-64.so.2').existsSync() ||
      File('/lib/ld-linux-aarch64.so.1').existsSync();
  final hasMusl = Directory('/lib')
      .listSync()
      .any((e) => e.path.split('/').last.startsWith('ld-musl-'));
  return hasMusl && !hasGlibc;
}

/// The program interpreter of a 64-bit little-endian ELF file, or null.
String? _elfInterpreter(String path) {
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final header = file.readSync(64);
    if (header.length < 64 ||
        header[0] != 0x7f ||
        header[1] != 0x45 || // E
        header[2] != 0x4c || // L
        header[3] != 0x46 || // F
        header[4] != 2 || // 64-bit
        header[5] != 1) {
      // little-endian
      return null;
    }
    final h = ByteData.sublistView(header);
    final phOffset = h.getUint64(0x20, Endian.little);
    final phEntrySize = h.getUint16(0x36, Endian.little);
    final phCount = h.getUint16(0x38, Endian.little);
    for (var i = 0; i < phCount; i++) {
      file.setPositionSync(phOffset + i * phEntrySize);
      final ph = ByteData.sublistView(file.readSync(56));
      const ptInterp = 3;
      if (ph.lengthInBytes < 56 || ph.getUint32(0, Endian.little) != ptInterp) {
        continue;
      }
      file.setPositionSync(ph.getUint64(8, Endian.little));
      final bytes = file.readSync(ph.getUint64(32, Endian.little));
      return String.fromCharCodes(bytes.takeWhile((b) => b != 0));
    }
    return null;
  } on Object {
    return null;
  } finally {
    file?.closeSync();
  }
}

Future<Uri?> _cargoBuild(
  BuildInput input,
  BuildOutputBuilder output,
  OS os,
  Architecture arch,
  bool musl,
  String fileName,
) async {
  final triple = _rustTargets[(os, arch, musl)];
  if (triple == null || !await _hasCargo()) return null;

  final crate = input.packageRoot.resolve('native/');
  for (final entity in Directory.fromUri(crate.resolve('src/'))
      .listSync(recursive: true)
      .whereType<File>()) {
    output.dependencies.add(entity.uri);
  }
  output.dependencies
    ..add(crate.resolve('Cargo.toml'))
    ..add(crate.resolve('Cargo.lock'));

  final targetDir = input.outputDirectoryShared.resolve('cargo/');
  final result = await Process.run(
    'cargo',
    [
      'build',
      '--release',
      '--locked',
      '--manifest-path',
      crate.resolve('Cargo.toml').toFilePath(),
      '--target',
      triple,
      '--target-dir',
      targetDir.toFilePath(),
    ],
    // musl targets link libc statically by default, which cannot produce a
    // loadable shared library.
    environment: {if (musl) 'RUSTFLAGS': '-C target-feature=-crt-static'},
  );
  if (result.exitCode != 0) {
    throw Exception(
      'suggestedtests: `cargo build --target $triple` failed '
      '(exit ${result.exitCode}).\n'
      'If the target is missing, run: rustup target add $triple\n'
      '${result.stderr}',
    );
  }
  return targetDir.resolve('$triple/release/$fileName');
}

Future<bool> _hasCargo() async {
  try {
    return (await Process.run('cargo', ['--version'])).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
