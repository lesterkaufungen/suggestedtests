package io.github.lesterkaufungen.suggestedtests.junit;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.junit.jupiter.api.extension.ExtendWith;

/**
 * Registers the {@link SuggestedTestsExtension} on a test class: {@code TestData} parameters
 * are injected with a per-test seed that is reported on failure.
 *
 * <pre>{@code
 * @SuggestedTests
 * class SignupTest {
 *   @Test
 *   void acceptsAnyValidEmail(TestData data) {
 *     assertTrue(signup.accepts(data.email()));
 *   }
 * }
 * }</pre>
 */
@Documented
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.TYPE, ElementType.METHOD})
@ExtendWith(SuggestedTestsExtension.class)
public @interface SuggestedTests {}
