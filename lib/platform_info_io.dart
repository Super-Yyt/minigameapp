import 'dart:ffi';
import 'dart:io';

bool get isWindows => Platform.isWindows;

String? get updateOs {
  if (Platform.isWindows) return 'win10';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return null;
}

String? get updateArch {
  final abi = Abi.current().toString().toLowerCase();
  if (abi.contains('arm64')) return 'arm64';
  if (abi.contains('arm')) return 'arm';
  if (abi.contains('x64')) return 'x64';
  if (abi.contains('ia32')) return 'x86';
  if (abi.contains('riscv64')) return 'riscv64';
  return null;
}
