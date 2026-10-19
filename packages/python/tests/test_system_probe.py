import os
import subprocess
import sys
import threading

import pytest

from suggestedtests import (
    CpuTime,
    MemoryUsage,
    NativeBridgeError,
    SystemProbe,
    _native,
    format_bytes,
)


def burn(ms_of_work: int = 50_000) -> int:
    x = 0
    for i in range(ms_of_work):
        x = (x * 31 + i) % 1_000_003
    return x


def test_format_bytes():
    assert format_bytes(0) == "0 B"
    assert format_bytes(1023) == "1023 B"
    assert format_bytes(1536) == "1.5 KiB"
    assert format_bytes(5 * 1024**2) == "5.0 MiB"
    assert format_bytes(-2048) == "-2.0 KiB"


def test_cpu_time_arithmetic():
    later, earlier = CpuTime(30, 7), CpuTime(10, 2)
    assert later - earlier == CpuTime(20, 5)
    assert later.total_ns == 37


def test_native_bridge_error_message():
    assert "not supported on this OS" in str(NativeBridgeError("x", _native.ERR_UNSUPPORTED))
    assert "OS error 13" in str(NativeBridgeError("x", 13))


def test_platform_dir_is_known_here():
    assert _native.platform_dir() is not None


def test_elf_interpreter_of_non_elf_is_none(tmp_path):
    f = tmp_path / "x"
    f.write_bytes(b"not an elf")
    assert _native.elf_interpreter(str(f)) is None


def test_explicit_library_path_wins(monkeypatch, tmp_path):
    monkeypatch.setenv(_native.ENV_VAR, str(tmp_path / "missing.so"))
    assert _native.candidates() == [tmp_path / "missing.so"]
    with pytest.raises(OSError, match="missing.so"):
        _native.load()


def test_system_probe_cannot_be_instantiated():
    with pytest.raises(TypeError):
        SystemProbe()


@pytest.mark.requires_native_bridge
class TestWithBridge:
    def test_is_available(self):
        assert SystemProbe.is_available()
        assert SystemProbe.skip_reason() is None

    def test_process_cpu_time_increases(self):
        before = SystemProbe.process_cpu_time()
        while (SystemProbe.process_cpu_time() - before).total_ns <= 0:
            burn()

    def test_thread_cpu_time_is_per_thread(self):
        main_before = SystemProbe.thread_cpu_time_ns()
        other = []
        t = threading.Thread(target=lambda: other.append(SystemProbe.thread_cpu_time_ns()))
        t.start()
        t.join()
        assert other[0] >= 0
        while SystemProbe.thread_cpu_time_ns() <= main_before:
            burn()

    def test_memory_usage_is_plausible(self):
        m = SystemProbe.memory_usage()
        assert isinstance(m, MemoryUsage)
        assert m.current_rss_bytes > 1024 * 1024
        assert m.peak_rss_bytes >= m.current_rss_bytes
        assert "MiB" in str(m)

    def test_load_hook_ran_when_the_library_was_loaded(self):
        # native/src/load.rs: .init_array / __mod_init_func / .CRT$XCU ran on load.
        assert SystemProbe._lib.st_load_state() == _native.LOAD_AT_LOAD

    def test_cpu_count(self):
        assert SystemProbe.cpu_count() >= 1

    def test_set_verbose_rejects_non_bools(self):
        with pytest.raises(TypeError):
            SystemProbe.set_verbose(1)

    @staticmethod
    def _run(code, **env):
        environ = {k: v for k, v in os.environ.items() if k != _native.VERBOSE_ENV_VAR}
        environ.update(env)
        script = "from suggestedtests import SystemProbe\n" + code
        done = subprocess.run(
            [sys.executable, "-c", script],
            env=environ,
            capture_output=True,
            text=True,
            check=True,
        )
        return done.stdout, done.stderr

    def test_bridge_is_silent_by_default(self):
        _, err = self._run("assert SystemProbe.is_available()")
        assert "suggestedtests:" not in err

    def test_env_var_prints_the_report_when_the_bridge_loads(self):
        out, err = self._run(
            "assert SystemProbe.is_available()\nprint(SystemProbe.verbose())",
            SUGGESTEDTESTS_VERBOSE="1",
        )
        assert out.strip() == "True"
        assert err.count("suggestedtests: platform: ") == 1, err
        assert "suggestedtests: environment: " in err

    def test_import_alone_loads_the_bridge(self):
        environ = {k: v for k, v in os.environ.items() if k != _native.VERBOSE_ENV_VAR}
        done = subprocess.run(
            [sys.executable, "-c", "import suggestedtests"],
            env={**environ, _native.VERBOSE_ENV_VAR: "1"},
            capture_output=True,
            text=True,
            check=True,
        )
        assert done.stderr.count("suggestedtests: platform: ") == 1, done.stderr

    def test_set_verbose_prints_the_report_once(self):
        out, err = self._run(
            "print(SystemProbe.verbose(), SystemProbe.set_verbose(True),"
            " SystemProbe.set_verbose(True), SystemProbe.set_verbose(False),"
            " SystemProbe.verbose())"
        )
        assert out.split() == ["False", "False", "True", "True", "False"]
        assert err.count("suggestedtests: platform: ") == 1, err


def test_platform_dir_mapping(monkeypatch):
    cases = [
        ("linux", "x86_64", 2**63 - 1, "linux-x64"),
        ("linux", "i686", 2**31 - 1, "linux-x86"),
        ("linux", "armv7l", 2**31 - 1, "linux-arm"),
        ("linux", "riscv64", 2**63 - 1, "linux-riscv64"),
        ("linux", "aarch64", 2**31 - 1, "linux-arm"),  # 32-bit interpreter on arm64
        ("win32", "AMD64", 2**31 - 1, "windows-x86"),  # 32-bit Python on 64-bit Windows
        ("darwin", "arm64", 2**63 - 1, "macos-arm64"),
        ("linux", "mips", 2**31 - 1, None),
    ]
    monkeypatch.setattr(_native, "_uses_musl", lambda: False)
    monkeypatch.setattr(_native, "_is_android", lambda: False)
    for plat, machine, maxsize, expected in cases:
        monkeypatch.setattr(_native.sys, "platform", plat)
        monkeypatch.setattr(_native.platform, "machine", lambda m=machine: m)
        monkeypatch.setattr(_native.sys, "maxsize", maxsize)
        assert _native.platform_dir() == expected, (plat, machine)
    monkeypatch.setattr(_native, "_is_android", lambda: True)
    monkeypatch.setattr(_native.sys, "platform", "linux")
    monkeypatch.setattr(_native.platform, "machine", lambda: "aarch64")
    monkeypatch.setattr(_native.sys, "maxsize", 2**63 - 1)
    assert _native.platform_dir() == "android-arm64-v8a"


def test_elf_interpreter_reads_32_and_64_bit(tmp_path):
    import struct

    def elf(cls, interp):
        is64 = cls == 2
        ehsize, phsize = (64, 56) if is64 else (52, 32)
        data_off = ehsize + phsize
        header = bytearray(ehsize)
        header[:6] = b"\x7fELF" + bytes([cls, 1])
        if is64:
            struct.pack_into("<Q", header, 0x20, ehsize)
            struct.pack_into("<HH", header, 0x36, phsize, 1)
            ph = struct.pack("<IIQQQQQQ", 3, 4, data_off, 0, 0, len(interp), len(interp), 1)
        else:
            struct.pack_into("<I", header, 0x1C, ehsize)
            struct.pack_into("<HH", header, 0x2A, phsize, 1)
            ph = struct.pack("<IIIIIIII", 3, data_off, 0, 0, len(interp), len(interp), 4, 1)
        return bytes(header) + ph + interp

    for cls, interp in ((1, b"/lib/ld-musl-armhf.so.1\0"), (2, b"/lib64/ld-linux-x86-64.so.2\0")):
        f = tmp_path / f"elf{cls}"
        f.write_bytes(elf(cls, interp))
        assert _native.elf_interpreter(str(f)) == interp.rstrip(b"\0").decode()
