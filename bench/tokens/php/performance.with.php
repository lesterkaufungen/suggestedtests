<?php

use PHPUnit\Framework\TestCase;
use SuggestedTests\PHPUnit\SuggestedTests;

final class ParserTest extends TestCase
{
    use SuggestedTests;

    public function testParsingStaysFast(): void
    {
        $this->assertPerformance(fn () => $this->parser->parse($this->bigJson), budgetMs: 5);
    }
}
