package compat;

import static org.testng.Assert.assertEquals;

import io.github.lesterkaufungen.suggestedtests.TestData;
import org.testng.annotations.Test;

/** Run by HelpersTest in a child JVM: no native helper, yet the run loads the bridge. */
public class NoNativeHelpers {
  @Test
  public void seededData() {
    assertEquals(new TestData(1).word(), new TestData(1).word());
  }
}
