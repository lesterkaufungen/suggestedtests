package io.github.lesterkaufungen.suggestedtests.internal;

import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Locale;
import java.util.Optional;
import java.util.stream.Stream;

/**
 * JNI bindings to the Rust bridge in the monorepo's {@code native/} (see
 * {@code native/src/jni.rs}; keep the two in sync).
 *
 * <p>On Android it is loaded with {@code System.loadLibrary} from the app's
 * native libraries. Elsewhere it is loaded from, in order: the system property
 * {@code suggestedtests.native.lib} or {@code $SUGGESTEDTESTS_NATIVE_LIB} (an
 * explicit path), then the jar resource
 * {@code io/github/lesterkaufungen/suggestedtests/native/<platform>/<lib>},
 * copied to a temporary file first.
 *
 * <p>Not part of the public API.
 */
public final class NativeBridge {
  /** Expected {@code st_abi_version()}. */
  public static final int ABI_VERSION = 1;
  /** Success. */
  public static final int OK = 0;
  /** A required out-argument was null or too short. */
  public static final int ERR_NULL = -1;
  /** Not available on this OS. */
  public static final int ERR_UNSUPPORTED = -2;
  /** The OS failed without an error code. */
  public static final int ERR_UNKNOWN = -3;
  /** System property naming an explicit library path. */
  public static final String PROPERTY = "suggestedtests.native.lib";
  /** Environment variable naming an explicit library path. */
  public static final String ENV_VAR = "SUGGESTEDTESTS_NATIVE_LIB";
  /** Environment variable the library reads while loading: turns its startup report on. */
  public static final String VERBOSE_ENV_VAR = "SUGGESTEDTESTS_VERBOSE";
  /** System property that turns the startup report on, for JVMs that can't set the environment. */
  public static final String VERBOSE_PROPERTY = "suggestedtests.verbose";

  private static final String RESOURCE_DIR = "/io/github/lesterkaufungen/suggestedtests/native/";

  private NativeBridge() {}

  /** @return the ABI version of the loaded library. */
  public static native int abiVersion();

  /**
   * Side effects distinct from the pure version query {@link #abiVersion()} does. Additive (no
   * ABI bump): throws {@link UnsatisfiedLinkError} on an older prebuilt that predates it.
   */
  public static native void onLoad();

  /**
   * @param out receives {user ns, system ns}
   * @return a status code
   */
  public static native int processCpuTime(long[] out);

  /**
   * @param out receives {ns}
   * @return a status code
   */
  public static native int threadCpuTimeNs(long[] out);

  /**
   * @param out receives {current RSS bytes, peak RSS bytes}
   * @return a status code
   */
  public static native int memoryUsage(long[] out);

  /** @return the number of logical CPUs. */
  public static native int cpuCount();

  /**
   * @param verbose 0 turns the startup report off, anything else on
   * @return the previous value (0 or 1)
   */
  public static native int setVerbose(int verbose);

  /** @return 1 if the startup report is on, else 0 */
  public static native int verbose();

  /**
   * @param value a {@link #VERBOSE_ENV_VAR} or {@link #VERBOSE_PROPERTY} value
   * @return whether it means on: 1, true, yes or on, as the library reads it
   */
  public static boolean isTruthy(String value) {
    if (value == null) return false;
    String v = value.trim().toLowerCase(Locale.ROOT);
    return v.equals("1") || v.equals("true") || v.equals("yes") || v.equals("on");
  }

  /**
   * The program interpreter ({@code PT_INTERP}) of a little-endian ELF file (32 or 64-bit).
   *
   * @param path the file
   * @return the interpreter path, or empty
   */
  public static Optional<String> elfInterpreter(Path path) {
    try (RandomAccessFile f = new RandomAccessFile(path.toFile(), "r")) {
      byte[] header = new byte[64];
      int read = f.read(header);
      if (read < 52
          || header[0] != 0x7f
          || header[1] != 'E'
          || header[2] != 'L'
          || header[3] != 'F'
          || (header[4] != 1 && header[4] != 2)
          || header[5] != 1) {
        return Optional.empty();
      }
      boolean is64 = header[4] == 2;
      ByteBuffer h = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN);
      long phOffset = is64 ? h.getLong(0x20) : Integer.toUnsignedLong(h.getInt(0x1c));
      int phSize = Short.toUnsignedInt(h.getShort(is64 ? 0x36 : 0x2a));
      int phCount = Short.toUnsignedInt(h.getShort(is64 ? 0x38 : 0x2c));
      byte[] ph = new byte[phSize];
      for (int i = 0; i < phCount; i++) {
        f.seek(phOffset + (long) i * phSize);
        if (phSize < 32 || f.read(ph) < 32) continue;
        ByteBuffer p = ByteBuffer.wrap(ph).order(ByteOrder.LITTLE_ENDIAN);
        if (p.getInt(0) != 3) continue; // PT_INTERP
        long offset = is64 ? p.getLong(8) : Integer.toUnsignedLong(p.getInt(4));
        long size = is64 ? p.getLong(32) : Integer.toUnsignedLong(p.getInt(16));
        byte[] bytes = new byte[(int) Math.min(size, 4096)];
        f.seek(offset);
        int n = Math.max(f.read(bytes), 0);
        int end = 0;
        while (end < n && bytes[end] != 0) end++;
        return Optional.of(new String(bytes, 0, end, StandardCharsets.ISO_8859_1));
      }
      return Optional.empty();
    } catch (IOException | RuntimeException e) {
      return Optional.empty();
    }
  }

  private static boolean usesMusl() {
    // A library built for one libc can't be loaded into a process using the
    // other, so ask the running java executable.
    // ProcessHandle (Java 9+) would name the executable; java.home works on 8.
    Optional<String> interpreter =
        elfInterpreter(Paths.get(System.getProperty("java.home", ""), "bin", "java"));
    if (interpreter.isPresent()) return interpreter.get().contains("musl");
    try (Stream<Path> entries = Files.list(Paths.get("/lib"))) {
      return entries.anyMatch(p -> p.getFileName().toString().startsWith("ld-musl-"));
    } catch (IOException e) {
      return false;
    }
  }

  /** @return {@code <os>-<arch>[-musl]}, the prebuilt directory for this JVM, or empty. */
  public static Optional<String> platformDir() {
    Optional<String> arch = archDir(System.getProperty("os.arch", ""));
    if (!arch.isPresent()) return Optional.empty();
    return platformDir(System.getProperty("os.name", ""), arch.get(), NativeBridge::usesMusl);
  }

  /**
   * Maps {@code os.arch} (the JVM's architecture, so a 32-bit JVM on a 64-bit OS reports x86)
   * to a prebuilt directory suffix.
   *
   * @param osArch the {@code os.arch} value
   * @return "x64", "arm64", "x86", "arm", "riscv64", or empty
   */
  public static Optional<String> archDir(String osArch) {
    switch (osArch.toLowerCase(Locale.ROOT)) {
      case "amd64":
      case "x86_64":
        return Optional.of("x64");
      case "aarch64":
      case "arm64":
        return Optional.of("arm64");
      case "x86":
      case "i386":
      case "i486":
      case "i586":
      case "i686":
        return Optional.of("x86");
      case "arm":
      case "armv7":
      case "armv7l":
      case "armhf":
        return Optional.of("arm");
      case "riscv64":
        return Optional.of("riscv64");
      default:
        return Optional.empty();
    }
  }

  /**
   * @param osName the {@code os.name} value
   * @param arch from {@link #archDir}
   * @param usesMusl asked only on Linux
   * @return the prebuilt directory, or empty
   */
  public static Optional<String> platformDir(String osName, String arch, java.util.function.BooleanSupplier usesMusl) {
    String os = osName.toLowerCase(Locale.ROOT);
    if (os.startsWith("linux")) return Optional.of("linux-" + arch + (usesMusl.getAsBoolean() ? "-musl" : ""));
    if (os.startsWith("mac")) return Optional.of("macos-" + arch);
    if (os.startsWith("windows")) return Optional.of("windows-" + arch);
    return Optional.empty();
  }

  /** @return whether this is Android's runtime (ART/Dalvik), not a desktop JVM. */
  public static boolean isAndroid() {
    return System.getProperty("java.vm.vendor", "").contains("Android")
        || "Dalvik".equals(System.getProperty("java.vm.name"));
  }

  /** @return the library's file name on this OS. */
  public static String libraryFileName() {
    String os = System.getProperty("os.name", "").toLowerCase(Locale.ROOT);
    if (os.startsWith("windows")) return "suggestedtests_native.dll";
    if (os.startsWith("mac")) return "libsuggestedtests_native.dylib";
    return "libsuggestedtests_native.so";
  }

  /** @return the explicit library path from the system property or environment, if any. */
  public static Optional<String> explicitPath() {
    String path = System.getProperty(PROPERTY);
    if (path == null || path.isEmpty()) path = System.getenv(ENV_VAR);
    return path == null || path.isEmpty() ? Optional.empty() : Optional.of(path);
  }

  /**
   * Loads the library.
   *
   * @throws UnsatisfiedLinkError if it is missing or can't be loaded
   */
  public static void load() {
    if (isAndroid()) {
      // Android apps ship native libraries in the APK (the AAR's jni/<abi>/).
      System.loadLibrary("suggestedtests_native");
      return;
    }
    Optional<String> explicit = explicitPath();
    if (explicit.isPresent()) {
      if (!Files.isRegularFile(Paths.get(explicit.get()))) {
        throw new UnsatisfiedLinkError("bridge library not found at: " + explicit.get());
      }
      System.load(Paths.get(explicit.get()).toAbsolutePath().toString());
      return;
    }
    String dir =
        platformDir()
            .orElseThrow(
                () ->
                    new UnsatisfiedLinkError(
                        "no prebuilt bridge for "
                            + System.getProperty("os.name")
                            + "/"
                            + System.getProperty("os.arch")));
    String name = libraryFileName();
    String resource = RESOURCE_DIR + dir + "/" + name;
    try (InputStream in = NativeBridge.class.getResourceAsStream(resource)) {
      if (in == null) throw new UnsatisfiedLinkError("bridge library not found at: " + resource);
      // A copy per load: a library file can only be loaded by one class loader.
      Path tmp = Files.createTempDirectory("suggestedtests-native");
      Path lib = tmp.resolve(name);
      Files.copy(in, lib, StandardCopyOption.REPLACE_EXISTING);
      lib.toFile().deleteOnExit();
      tmp.toFile().deleteOnExit();
      System.load(lib.toAbsolutePath().toString());
    } catch (IOException e) {
      UnsatisfiedLinkError error = new UnsatisfiedLinkError("cannot extract " + resource + ": " + e);
      error.initCause(e);
      throw error;
    }
  }
}
