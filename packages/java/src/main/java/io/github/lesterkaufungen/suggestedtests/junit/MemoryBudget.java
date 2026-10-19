package io.github.lesterkaufungen.suggestedtests.junit;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.junit.jupiter.api.extension.ExtendWith;

/**
 * Fails a test whose body grows memory beyond the budget. Negative values (the default) mean
 * no limit; set at least one. RSS limits need the native bridge.
 *
 * <pre>{@code
 * @Test
 * @MemoryBudget(maxPeakGrowthBytes = 64 * Memory.MiB)
 * void importStaysSmall() { importer.run(bigFile); }
 * }</pre>
 */
@Documented
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.TYPE, ElementType.METHOD})
@ExtendWith(SuggestedTestsExtension.class)
public @interface MemoryBudget {
  /** @return maximum growth of resident memory, in bytes */
  long maxRssGrowthBytes() default -1;

  /** @return maximum rise of the process' peak resident memory, in bytes */
  long maxPeakGrowthBytes() default -1;

  /** @return maximum growth of the used Java heap, in bytes */
  long maxHeapGrowthBytes() default -1;
}
