<?php

declare(strict_types=1);

namespace SuggestedTests;

use SuggestedTests\Native\Bridge;

/** Thrown when the native bridge is missing or an OS call fails. */
final class NativeBridgeException extends \RuntimeException
{
    /** @var string The bridge function that failed. */
    public $operation;
    /**
     * @var int Negative for bridge errors, positive for the raw OS error code
     *   (`errno` on Linux/macOS, `GetLastError()` on Windows).
     */
    public $status;
    /** @var ?string Extra context, if any. */
    public $detail;

    public function __construct(string $operation, int $status, ?string $detail = null)
    {
        $this->operation = $operation;
        $this->status = $status;
        $this->detail = $detail;
        switch ($status) {
            case Bridge::ERR_NULL:
                $reason = 'null pointer';
                break;
            case Bridge::ERR_UNSUPPORTED:
                $reason = 'not supported on this OS';
                break;
            case Bridge::ERR_UNKNOWN:
                $reason = 'unknown OS error';
                break;
            default:
                $reason = "OS error $status";
        }
        parent::__construct("$operation failed: $reason" . ($detail !== null ? "\n$detail" : ''), $status);
    }
}
