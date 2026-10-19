import io.github.lesterkaufungen.suggestedtests.Benchmark
import io.github.lesterkaufungen.suggestedtests.Clock
import io.github.lesterkaufungen.suggestedtests.Concurrency
import io.github.lesterkaufungen.suggestedtests.Eventually
import io.github.lesterkaufungen.suggestedtests.Leaks
import io.github.lesterkaufungen.suggestedtests.Memory
import io.github.lesterkaufungen.suggestedtests.Scenario
import io.github.lesterkaufungen.suggestedtests.Spy
import io.github.lesterkaufungen.suggestedtests.Statistic
import io.github.lesterkaufungen.suggestedtests.SuggestedAssertions.assertCalledTimes
import io.github.lesterkaufungen.suggestedtests.SuggestedAssertions.assertCalledWith
import io.github.lesterkaufungen.suggestedtests.SuggestedAssertions.assertUnique
import io.github.lesterkaufungen.suggestedtests.SystemProbe
import io.github.lesterkaufungen.suggestedtests.TestData
import io.github.lesterkaufungen.suggestedtests.junit.MemoryBudget
import io.github.lesterkaufungen.suggestedtests.junit.RequiresNativeBridge
import io.github.lesterkaufungen.suggestedtests.junit.Seed
import io.github.lesterkaufungen.suggestedtests.junit.SuggestedTests
import io.github.lesterkaufungen.suggestedtests.junit4.SuggestedTestsRule
import java.time.Duration
import java.util.concurrent.CompletableFuture
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import org.junit.Rule
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class Cart {
    private val items = mutableListOf<Int>()
    fun add(price: Int) = apply { items += price }
    val total get() = items.sum()
}

/** Kotlin lambdas against every functional interface of the library (JUnit 5). */
@SuggestedTests
class KotlinCompatTest {
    @Test
    fun benchmarkAcceptsKotlinLambdas() {
        val result = Benchmark.of("sum") { (1..1000).sum() }.iterations(10).statistic(Statistic.P95)
            .assertWithin(Duration.ofMillis(100))
        assertEquals(10, result.samples().size)
    }

    @Test
    @RequiresNativeBridge
    fun cpuClockAndProbe() {
        Benchmark.of("sleep") { Thread.sleep(1) }.iterations(3).clock(Clock.CPU).run()
        assertTrue(SystemProbe.memoryUsage().currentRssBytes() > Memory.MiB)
    }

    @Test
    fun scenarioPassesTheValueToKotlinSteps() {
        Scenario.given("an empty cart") { Cart() }
            .`when`("two items are added") { it.add(10).add(20) }
            .then("the total is 30") { assertEquals(30, it.total) }
    }

    @Test
    fun scenarioWithoutAValue() {
        val started = AtomicInteger()
        Scenario.givenThat("the server is up") { started.incrementAndGet() }
            .then("it started once") { assertEquals(1, started.get()) }
    }

    @Test
    fun eventuallyWithUnitAndValueLambdas() {
        val n = AtomicInteger()
        Eventually.eventually { assertTrue(n.incrementAndGet() >= 2) }
        val value: Int = Eventually.eventually<Int> { n.get() }
        assertTrue(value >= 2)
        assertEquals(1, Eventually.assertCompletesWithin(Duration.ofSeconds(1), CompletableFuture.completedFuture(1)))
    }

    @Test
    fun spiesForJavaAndKotlinFunctionTypes() {
        val parse = Spy.function<String, Int> { it.toInt() }
        listOf("1", "2").map(parse.get()::apply)
        assertCalledTimes(parse, 2)
        assertCalledWith(parse, "2")

        @Suppress("UNCHECKED_CAST")
        val kotlinFn = Spy.of(Function1::class.java as Class<Function1<String, Int>>) { s: String -> s.length }
        assertEquals(5, kotlinFn.get().invoke("hello"))
        assertCalledWith(kotlinFn, "hello")
    }

    @Test
    @Seed(42)
    fun injectedTestData(data: TestData) {
        assertEquals(42, data.seed())
        assertUnique(data.listOf(50) { it.uuid() })
    }

    @Test
    @MemoryBudget(maxHeapGrowthBytes = 256 * Memory.MiB)
    fun memoryBudgetAnnotationWithAConstantExpression() {
        assertEquals(1000, TestData().listOf(1000) { it.email() }.size)
    }

    @Test
    fun raceAndLeaks() {
        val counter = AtomicLong()
        Concurrency.race(4) { repeat(1000) { counter.incrementAndGet() } }
        assertEquals(4000, counter.get())
        Leaks.assertNoLeakedThreads { Thread { }.apply { start(); join() } }
        Leaks.assertGarbageCollected { Any() }
    }
}

/** The JUnit 4 rule, as used by Android projects. */
class KotlinJUnit4RuleTest {
    @get:Rule
    val st = SuggestedTestsRule()

    @org.junit.Test
    @Seed(7)
    fun ruleProvidesSeededData() {
        org.junit.Assert.assertEquals(7L, st.testData().seed())
    }

    @org.junit.Test
    @RequiresNativeBridge
    fun ruleHonoursRequiresNativeBridge() {
        org.junit.Assert.assertTrue(SystemProbe.cpuCount() >= 1)
    }
}
