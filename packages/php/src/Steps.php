<?php

declare(strict_types=1);

namespace SuggestedTests;

/**
 * Given/when/then steps. Steps run in declaration order when `run()` is
 * called. A failing step's exception is rethrown unchanged (same class, so
 * PHPUnit still reports a failure and its diff) with the step prepended to
 * its message, e.g. `Then: the total is 30` .
 *
 * ```php
 * $this->scenario(function (Steps $s) {
 *     $s->given('an empty cart', function () use (&$cart) { $cart = new Cart(); });
 *     $s->when('two items are added', function () use (&$cart) { $cart->add(10)->add(20); });
 *     $s->then('the total is 30', function () use (&$cart) { $this->assertSame(30, $cart->total()); });
 * });
 * ```
 */
final class Steps
{
    /** @var list<array{string, string, callable}> */
    private $steps = [];

    private function add(string $keyword, string $description, callable $body): self
    {
        if ($description === '') {
            throw new \InvalidArgumentException('step description must not be empty');
        }
        $this->steps[] = [$keyword, $description, $body];
        return $this;
    }

    /** Declares setup / preconditions. */
    public function given(string $description, callable $body): self
    {
        return $this->add('Given', $description, $body);
    }

    /** Declares the action under test. */
    public function when(string $description, callable $body): self
    {
        return $this->add('When', $description, $body);
    }

    /** Declares an expectation. */
    public function then(string $description, callable $body): self
    {
        return $this->add('Then', $description, $body);
    }

    /** Continues the previous step kind (e.g. a second `then`). */
    public function and(string $description, callable $body): self
    {
        return $this->add('And', $description, $body);
    }

    /** Runs the declared steps in order. */
    public function run(): void
    {
        if ($this->steps === []) {
            throw new \LogicException('scenario declared no steps');
        }
        foreach ($this->steps as [$keyword, $description, $body]) {
            try {
                $body();
            } catch (\Throwable $error) {
                throw Failure::prefix($error, "$keyword: $description\n");
            }
        }
    }
}
