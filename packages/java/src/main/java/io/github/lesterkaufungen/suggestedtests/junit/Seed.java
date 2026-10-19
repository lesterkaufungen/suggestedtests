package io.github.lesterkaufungen.suggestedtests.junit;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.junit.jupiter.api.extension.ExtendWith;

/**
 * Fixes the seed of injected {@code TestData} for a test method or class. The system property
 * {@code suggestedtests.seed} (or {@code $SUGGESTEDTESTS_SEED}) overrides it.
 */
@Documented
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.TYPE, ElementType.METHOD})
@ExtendWith(SuggestedTestsExtension.class)
public @interface Seed {
  /** @return the seed */
  long value();
}
