<?php

use PHPUnit\Framework\TestCase;

final class ParserTest extends TestCase
{
    public function testParsingStaysFast(): void
    {
        for ($i = 0; $i < 3; $i++) {
            $this->parser->parse($this->bigJson);
        }
        $samples = [];
        for ($i = 0; $i < 20; $i++) {
            $start = hrtime(true);
            $this->parser->parse($this->bigJson);
            $samples[] = (hrtime(true) - $start) / 1e6;
        }
        sort($samples);
        $median = ($samples[9] + $samples[10]) / 2;
        $this->assertLessThanOrEqual(5, $median, sprintf(
            'parse: median %.2fms > budget 5ms (min %.2fms, max %.2fms)',
            $median,
            $samples[0],
            $samples[19]
        ));
    }
}
