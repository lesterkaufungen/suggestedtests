package io.github.lesterkaufungen.suggestedtests;

import java.time.Duration;
import java.util.Objects;

/** CPU time consumed by the process, split into user and kernel time. */
public final class CpuTime {
  private final Duration user;
  private final Duration system;

  /**
   * Creates a sample.
   *
   * @param user time spent running user-space code
   * @param system time spent in the kernel on behalf of the process
   */
  public CpuTime(Duration user, Duration system) {
    this.user = Objects.requireNonNull(user, "user");
    this.system = Objects.requireNonNull(system, "system");
  }

  /** @return time spent running user-space code */
  public Duration user() {
    return user;
  }

  /** @return time spent in the kernel on behalf of the process */
  public Duration system() {
    return system;
  }

  /** @return {@code user + system} */
  public Duration total() {
    return user.plus(system);
  }

  /**
   * The CPU time spent between {@code earlier} and this sample.
   *
   * @param earlier an earlier sample
   * @return the difference
   */
  public CpuTime minus(CpuTime earlier) {
    return new CpuTime(user.minus(earlier.user), system.minus(earlier.system));
  }

  @Override
  public boolean equals(Object o) {
    return o instanceof CpuTime && ((CpuTime) o).user.equals(user) && ((CpuTime) o).system.equals(system);
  }

  @Override
  public int hashCode() {
    return Objects.hash(user, system);
  }

  @Override
  public String toString() {
    return "CpuTime(user: " + Format.duration(user) + ", system: " + Format.duration(system) + ")";
  }
}
