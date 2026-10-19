<?php

declare(strict_types=1);

namespace SuggestedTests;

/** CPU time consumed by the process, split into user and kernel time. */
final class CpuTime
{
    /** @var int Time spent running user-space code, in nanoseconds. */
    public $userNs;
    /** @var int Time spent in the kernel on behalf of the process, in nanoseconds. */
    public $systemNs;

    public function __construct(int $userNs, int $systemNs)
    {
        $this->userNs = $userNs;
        $this->systemNs = $systemNs;
    }

    /** `userNs + systemNs`. */
    public function totalNs(): int
    {
        return $this->userNs + $this->systemNs;
    }

    /** The CPU time spent between `$earlier` and this sample. */
    public function minus(self $earlier): self
    {
        return new self($this->userNs - $earlier->userNs, $this->systemNs - $earlier->systemNs);
    }

    public function __toString(): string
    {
        return sprintf('CpuTime(user: %s, system: %s)', Format::ms($this->userNs / 1e6), Format::ms($this->systemNs / 1e6));
    }
}
