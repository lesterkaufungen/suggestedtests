<?php

declare(strict_types=1);

namespace SuggestedTests;

/**
 * A callable that records its calls and delegates to an optional
 * implementation. Pass it wherever a callback is expected:
 *
 * ```php
 * $onSaved = new Spy();
 * $form->onSaved($onSaved);
 * $form->submit();
 * $this->assertSpyCalledWith($onSaved, [$this->isInstanceOf(User::class)]);
 * ```
 */
final class Spy implements \Countable
{
    /** @var list<list<mixed>> */
    private $calls = [];

    /** @var ?\Closure */
    private $impl;

    /** @param ?callable $impl Called with the same arguments; its result is returned. */
    public function __construct(?callable $impl = null)
    {
        $this->impl = $impl === null ? null : \Closure::fromCallable($impl);
    }

    /**
     * Records the call and delegates to the implementation.
     *
     * @param mixed ...$args
     * @return mixed
     */
    public function __invoke(...$args)
    {
        $this->calls[] = array_values($args);
        return $this->impl === null ? null : ($this->impl)(...$args);
    }

    /** @return list<list<mixed>> Arguments of every call, oldest first. */
    public function calls(): array
    {
        return $this->calls;
    }

    /** Number of calls so far. */
    public function count(): int
    {
        return count($this->calls);
    }

    /** Whether the spy was called at least once. */
    public function called(): bool
    {
        return $this->calls !== [];
    }

    /** @return list<mixed> Arguments of the most recent call. */
    public function lastCall(): array
    {
        if ($this->calls === []) {
            throw new \LogicException('Spy was never called');
        }
        return $this->calls[count($this->calls) - 1];
    }

    /** Forgets all recorded calls. */
    public function reset(): void
    {
        $this->calls = [];
    }

    public function __toString(): string
    {
        return 'Spy(calls: ' . json_encode($this->calls, JSON_PARTIAL_OUTPUT_ON_ERROR | JSON_UNESCAPED_SLASHES) . ')';
    }
}
