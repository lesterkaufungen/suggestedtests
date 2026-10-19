package io.github.lesterkaufungen.suggestedtests;

import static org.junit.jupiter.api.Assertions.*;

import io.github.lesterkaufungen.suggestedtests.internal.NativeBridge;
import io.github.lesterkaufungen.suggestedtests.junit.RequiresNativeBridge;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class SystemProbeTest {
  private static long burn() {
    long x = 0;
    for (int i = 0; i < 1_000_000; i++) x = (x * 31 + i) % 1_000_003;
    return x;
  }

  @Test
  void format() {
    assertEquals("0 B", Format.bytes(0));
    assertEquals("1.5 KiB", Format.bytes(1536));
    assertEquals("5.0 MiB", Format.bytes(5L << 20));
    assertEquals("-2.0 KiB", Format.bytes(-2048));
    assertEquals("850µs", Format.duration(Duration.ofNanos(850_000)));
    assertEquals("1.25ms", Format.duration(Duration.ofNanos(1_250_000)));
    assertEquals("2.00s", Format.duration(Duration.ofSeconds(2)));
  }

  @Test
  void cpuTimeArithmetic() {
    CpuTime d = new CpuTime(Duration.ofNanos(30), Duration.ofNanos(7)).minus(new CpuTime(Duration.ofNanos(10), Duration.ofNanos(2)));
    assertEquals(new CpuTime(Duration.ofNanos(20), Duration.ofNanos(5)), d);
    assertEquals(Duration.ofNanos(25), d.total());
  }

  @Test
  void exceptionExplainsStatus() {
    assertTrue(new NativeBridgeException("x", NativeBridge.ERR_UNSUPPORTED, null).getMessage().contains("not supported on this OS"));
    assertTrue(new NativeBridgeException("x", 13, null).getMessage().contains("OS error 13"));
  }

  @Test
  void platformIsKnown() {
    assertTrue(NativeBridge.platformDir().isPresent());
  }

  @Test
  void platformDirMapping() {
    assertEquals("x86", NativeBridge.archDir("i686").get());
    assertEquals("x86", NativeBridge.archDir("x86").get());
    assertEquals("arm", NativeBridge.archDir("arm").get());
    assertEquals("riscv64", NativeBridge.archDir("riscv64").get());
    assertFalse(NativeBridge.archDir("mips").isPresent());
    assertEquals("linux-arm-musl", NativeBridge.platformDir("Linux", "arm", () -> true).get());
    assertEquals("windows-x86", NativeBridge.platformDir("Windows 10", "x86", () -> false).get());
    assertEquals("macos-arm64", NativeBridge.platformDir("Mac OS X", "arm64", () -> false).get());
  }

  @Test
  void elfInterpreterReads32And64Bit() throws java.io.IOException {
    for (int cls = 1; cls <= 2; cls++) {
      String interp = cls == 1 ? "/lib/ld-musl-armhf.so.1" : "/lib64/ld-linux-x86-64.so.2";
      boolean is64 = cls == 2;
      int ehsize = is64 ? 64 : 52;
      int phsize = is64 ? 56 : 32;
      byte[] text = (interp + "\0").getBytes(java.nio.charset.StandardCharsets.ISO_8859_1);
      java.nio.ByteBuffer b = java.nio.ByteBuffer.allocate(ehsize + phsize + text.length).order(java.nio.ByteOrder.LITTLE_ENDIAN);
      b.put(new byte[] {0x7f, 'E', 'L', 'F', (byte) cls, 1});
      if (is64) {
        b.putLong(0x20, ehsize).putShort(0x36, (short) phsize).putShort(0x38, (short) 1);
        b.putInt(ehsize, 3).putLong(ehsize + 8, ehsize + phsize).putLong(ehsize + 32, text.length);
      } else {
        b.putInt(0x1c, ehsize).putShort(0x2a, (short) phsize).putShort(0x2c, (short) 1);
        b.putInt(ehsize, 3).putInt(ehsize + 4, ehsize + phsize).putInt(ehsize + 16, text.length);
      }
      b.position(ehsize + phsize);
      b.put(text);
      java.nio.file.Path file = java.nio.file.Files.createTempFile("st-elf", ".bin");
      java.nio.file.Files.write(file, b.array());
      assertEquals(interp, NativeBridge.elfInterpreter(file).get());
      java.nio.file.Files.delete(file);
    }
  }

  @Test
  void elfInterpreterOfNonElfIsEmpty() {
    assertFalse(NativeBridge.elfInterpreter(Paths.get("pom.xml")).isPresent());
    assertFalse(NativeBridge.elfInterpreter(Paths.get("/does/not/exist")).isPresent());
  }

  @Test
  @RequiresNativeBridge
  void processCpuTimeAdvances() {
    CpuTime before = SystemProbe.processCpuTime();
    while (SystemProbe.processCpuTime().minus(before).total().isZero()) burn();
  }

  @Test
  @RequiresNativeBridge
  void threadCpuTimeAdvances() {
    long before = SystemProbe.threadCpuTimeNs();
    while (SystemProbe.threadCpuTimeNs() <= before) burn();
  }

  @Test
  @RequiresNativeBridge
  void memoryUsageIsPlausible() {
    MemoryUsage m = SystemProbe.memoryUsage();
    assertTrue(m.currentRssBytes() > Memory.MiB);
    assertTrue(m.peakRssBytes() >= m.currentRssBytes());
    assertTrue(m.toString().contains("MiB"));
    assertTrue(SystemProbe.cpuCount() >= 1);
  }

  @Test
  @RequiresNativeBridge
  void jniRejectsShortArrays() {
    assertEquals(NativeBridge.ERR_NULL, NativeBridge.processCpuTime(new long[1]));
    assertEquals(NativeBridge.ERR_NULL, NativeBridge.memoryUsage(null));
    assertEquals(NativeBridge.OK, NativeBridge.threadCpuTimeNs(new long[1]));
  }

  /** Runs in a fresh JVM: the report goes to that process' stderr. */
  static final class VerboseChild {
    public static void main(String[] args) {
      if (!SystemProbe.isAvailable()) throw new AssertionError(SystemProbe.skipReason().get());
      if (args[0].equals("set")) {
        System.out.print(SystemProbe.verbose() + " " + SystemProbe.setVerbose(true) + " "
            + SystemProbe.setVerbose(true) + " " + SystemProbe.setVerbose(false) + " ");
      }
      System.out.print(SystemProbe.verbose());
    }
  }

  /** Runs in a fresh JVM: only opens a JUnit Platform session, as test runners do. */
  static final class SessionChild {
    public static void main(String[] args) {
      org.junit.platform.launcher.core.LauncherFactory.openSession().close();
    }
  }

  /** @return {stdout, stderr} of {@link VerboseChild} */
  private static String[] runChild(String mode, String env, String property) throws Exception {
    return runChild(VerboseChild.class, mode, env, property);
  }

  /** @return {stdout, stderr} of {@code main} with {@code mode} as its argument */
  private static String[] runChild(Class<?> main, String mode, String env, String property)
      throws Exception {
    List<String> command = new ArrayList<>();
    command.add(Paths.get(System.getProperty("java.home"), "bin", "java").toString());
    command.add("-cp");
    command.add(System.getProperty("java.class.path"));
    String lib = System.getProperty(NativeBridge.PROPERTY);
    if (lib != null) command.add("-D" + NativeBridge.PROPERTY + "=" + lib);
    if (property != null) command.add("-D" + NativeBridge.VERBOSE_PROPERTY + "=" + property);
    command.add(main.getName());
    command.add(mode);
    File out = File.createTempFile("verbose", ".out");
    File err = File.createTempFile("verbose", ".err");
    try {
      ProcessBuilder pb = new ProcessBuilder(command).redirectOutput(out).redirectError(err);
      pb.environment().remove(NativeBridge.VERBOSE_ENV_VAR);
      if (env != null) pb.environment().put(NativeBridge.VERBOSE_ENV_VAR, env);
      int status = pb.start().waitFor();
      String[] result = {
        new String(Files.readAllBytes(out.toPath()), StandardCharsets.UTF_8),
        new String(Files.readAllBytes(err.toPath()), StandardCharsets.UTF_8)
      };
      assertEquals(0, status, result[0] + result[1]);
      return result;
    } finally {
      out.delete();
      err.delete();
    }
  }

  private static int reports(String stderr) {
    return stderr.split("suggestedtests: platform: ", -1).length - 1;
  }

  @Test
  @RequiresNativeBridge
  void bridgeIsSilentByDefault() throws Exception {
    String[] r = runChild("load", null, null);
    assertEquals("false", r[0]);
    assertFalse(r[1].contains("suggestedtests:"), r[1]);
  }

  @Test
  @RequiresNativeBridge
  void envVarPrintsTheReportWhenTheBridgeLoads() throws Exception {
    String[] r = runChild("load", "1", null);
    assertEquals("true", r[0]);
    assertEquals(1, reports(r[1]), r[1]);
    assertTrue(r[1].contains("suggestedtests: environment: "), r[1]);
  }

  @Test
  @RequiresNativeBridge
  void aJUnitPlatformSessionLoadsTheBridge() throws Exception {
    String[] r = runChild(SessionChild.class, "", "1", null);
    assertEquals(1, reports(r[1]), r[1]);
  }

  @Test
  @RequiresNativeBridge
  void propertyPrintsTheReportWhenTheBridgeLoads() throws Exception {
    String[] r = runChild("load", null, "true");
    assertEquals("true", r[0]);
    assertEquals(1, reports(r[1]), r[1]);
  }

  @Test
  @RequiresNativeBridge
  void setVerbosePrintsTheReportOnce() throws Exception {
    String[] r = runChild("set", null, null);
    assertEquals("false false true true false", r[0]);
    assertEquals(1, reports(r[1]), r[1]);
  }

  @Test
  void truthyValues() {
    for (String v : new String[] {"1", "true", "TRUE", " yes ", "on"}) assertTrue(NativeBridge.isTruthy(v), v);
    for (String v : new String[] {"", "0", "false", "no", "2"}) assertFalse(NativeBridge.isTruthy(v), v);
    assertFalse(NativeBridge.isTruthy(null));
  }
}
