<?php

declare(strict_types=1);

namespace SuggestedTests;

/**
 * Raises test failures. Under PHPUnit they are `AssertionFailedError`s, so
 * they are reported as failures rather than errors; elsewhere `\AssertionError`.
 *
 * @internal
 */
final class Failure
{
    /** @return never */
    public static function raise(string $message, ?\Throwable $previous = null)
    {
        if (class_exists(\PHPUnit\Framework\AssertionFailedError::class)) {
            throw new \PHPUnit\Framework\AssertionFailedError($message, 0, $previous);
        }
        throw new \AssertionError($message, 0, $previous);
    }

    /** Prepends `$prefix` to the message of `$error`, keeping its class and trace. */
    public static function prefix(\Throwable $error, string $prefix): \Throwable
    {
        $class = $error instanceof \Exception ? \Exception::class : \Error::class;
        $property = new \ReflectionProperty($class, 'message');
        $property->setAccessible(true); // required before PHP 8.1
        $property->setValue($error, $prefix . $error->getMessage());
        return $error;
    }
}
