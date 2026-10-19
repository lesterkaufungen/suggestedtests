package io.github.lesterkaufungen.suggestedtests;

import io.github.lesterkaufungen.suggestedtests.internal.NativeBridge;

/** Thrown when the native bridge is missing or an OS call fails. */
public final class NativeBridgeException extends RuntimeException {
  private static final long serialVersionUID = 1L;

  private final String operation;
  private final int status;

  /**
   * Creates an exception.
   *
   * @param operation the bridge function that failed
   * @param status negative for bridge errors, positive for the raw OS error code ({@code errno}
   *     on Linux/macOS, {@code GetLastError()} on Windows)
   * @param detail extra context, or null
   */
  public NativeBridgeException(String operation, int status, String detail) {
    super(operation + " failed: " + reason(status) + (detail == null ? "" : "\n" + detail));
    this.operation = operation;
    this.status = status;
  }

  private static String reason(int status) {
    switch (status) {
      case NativeBridge.ERR_NULL:
        return "null pointer";
      case NativeBridge.ERR_UNSUPPORTED:
        return "not supported on this OS";
      case NativeBridge.ERR_UNKNOWN:
        return "unknown OS error";
      default:
        return "OS error " + status;
    }
  }

  /** @return the bridge function that failed */
  public String operation() {
    return operation;
  }

  /** @return the status code */
  public int status() {
    return status;
  }
}
