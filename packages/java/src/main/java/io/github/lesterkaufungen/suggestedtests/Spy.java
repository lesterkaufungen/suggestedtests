package io.github.lesterkaufungen.suggestedtests;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
import java.util.function.BiConsumer;
import java.util.function.Consumer;
import java.util.function.Function;
import java.util.function.Predicate;
import java.util.function.Supplier;

/**
 * Records the calls of a functional interface and delegates to an optional implementation. No
 * mocking framework needed.
 *
 * <pre>{@code
 * Spy<Consumer<String>> onChange = Spy.consumer();
 * field.onChange(onChange.get());
 * field.type("hi");
 * assertCalledWith(onChange, "hi");
 * }</pre>
 *
 * @param <F> the functional interface
 */
public final class Spy<F> {
  private final Class<F> type;
  private final F proxy;
  private final List<List<Object>> calls = Collections.synchronizedList(new ArrayList<>());

  private Spy(Class<F> type, F impl) {
    if (!type.isInterface()) throw new IllegalArgumentException(type.getName() + " is not an interface");
    this.type = type;
    Method single = singleAbstractMethod(type);
    InvocationHandler handler =
        (proxyObject, method, args) -> {
          Object[] a = args == null ? new Object[0] : args;
          if (method.getDeclaringClass() == Object.class) return objectMethod(proxyObject, method, a);
          if (!method.equals(single)) {
            if (isDefault(method)) return invokeDefault(proxyObject, method, a);
            Method body = desugaredDefault(method);
            if (body != null) return invokeStatic(body, prepend(proxyObject, a));
            throw new UnsupportedOperationException(method + " is not the spied method");
          }
          calls.add(Collections.unmodifiableList(Arrays.asList(a.clone())));
          if (impl == null) return defaultValue(method.getReturnType());
          try {
            return method.invoke(impl, a);
          } catch (InvocationTargetException e) {
            throw e.getCause();
          }
        };
    this.proxy = type.cast(Proxy.newProxyInstance(type.getClassLoader(), new Class<?>[] {type}, handler));
  }

  private static Method singleAbstractMethod(Class<?> type) {
    Method found = null;
    for (Method m : type.getMethods()) {
      if (!isDefault(m)
          && !Modifier.isStatic(m.getModifiers())
          && !isObjectMethod(m)
          && desugaredDefault(m) == null) {
        if (found != null) throw new IllegalArgumentException(type.getName() + " is not a functional interface");
        found = m;
      }
    }
    if (found == null) throw new IllegalArgumentException(type.getName() + " has no abstract method");
    return found;
  }

  /** {@link Method#isDefault()}, which Android only has from API 24 (desugaring doesn't add it). */
  private static boolean isDefault(Method m) {
    int kind = m.getModifiers() & (Modifier.ABSTRACT | Modifier.PUBLIC | Modifier.STATIC);
    return kind == Modifier.PUBLIC && m.getDeclaringClass().isInterface();
  }

  /**
   * Where D8 moved the body of default method {@code m} when it desugared it (Android below API
   * 24): {@code I$-CC.$default$m(I, ...)}, with {@code java.} replaced by {@code j$.} for the JDK
   * interfaces of core library desugaring. {@code I.m} itself is then abstract. Null for a really
   * abstract method.
   */
  private static Method desugaredDefault(Method m) {
    Class<?> type = m.getDeclaringClass();
    if (!type.isInterface()) return null;
    Class<?>[] params = m.getParameterTypes();
    Class<?>[] withSelf = new Class<?>[params.length + 1];
    withSelf[0] = type;
    System.arraycopy(params, 0, withSelf, 1, params.length);
    ClassLoader loader = type.getClassLoader() != null ? type.getClassLoader() : Spy.class.getClassLoader();
    String name = type.getName();
    String companion = (name.startsWith("java.") ? "j$." + name.substring(5) : name) + "$-CC";
    try {
      Method body = Class.forName(companion, false, loader).getMethod("$default$" + m.getName(), withSelf);
      return Modifier.isStatic(body.getModifiers()) ? body : null;
    } catch (ClassNotFoundException | NoSuchMethodException e) {
      return null; // not desugared
    }
  }

  private static Object[] prepend(Object first, Object[] rest) {
    Object[] all = new Object[rest.length + 1];
    all[0] = first;
    System.arraycopy(rest, 0, all, 1, rest.length);
    return all;
  }

  private static Object invokeStatic(Method method, Object[] args) throws Throwable {
    try {
      return method.invoke(null, args);
    } catch (InvocationTargetException e) {
      throw e.getCause();
    }
  }

  private static boolean isObjectMethod(Method m) {
    try {
      Object.class.getMethod(m.getName(), m.getParameterTypes());
      return true;
    } catch (NoSuchMethodException e) {
      return false;
    }
  }

  private Object objectMethod(Object self, Method method, Object[] args) {
    switch (method.getName()) {
      case "equals":
        return self == args[0];
      case "hashCode":
        return System.identityHashCode(self);
      default:
        return toString();
    }
  }

  private static Object invokeDefault(Object proxy, Method method, Object[] args) throws Throwable {
    try {
      // InvocationHandler.invokeDefault exists from Java 16.
      Method invokeDefault =
          InvocationHandler.class.getMethod("invokeDefault", Object.class, Method.class, Object[].class);
      return invokeDefault.invoke(null, proxy, method, args);
    } catch (NoSuchMethodException e) {
      throw new UnsupportedOperationException("default method " + method.getName() + " of a Spy needs Java 16+");
    } catch (InvocationTargetException e) {
      throw e.getCause();
    }
  }

  private static Object defaultValue(Class<?> type) {
    if (!type.isPrimitive() || type == void.class) return null;
    if (type == boolean.class) return false;
    if (type == char.class) return '\0';
    if (type == byte.class) return (byte) 0;
    if (type == short.class) return (short) 0;
    if (type == int.class) return 0;
    if (type == long.class) return 0L;
    if (type == float.class) return 0f;
    return 0d;
  }

  /**
   * A spy for any functional interface.
   *
   * @param <F> the interface
   * @param type the interface
   * @param impl called with the same arguments; null returns null / zero / false
   * @return the spy
   */
  public static <F> Spy<F> of(Class<F> type, F impl) {
    return new Spy<>(Objects.requireNonNull(type, "type"), impl);
  }

  /** @return a spy for a {@link Runnable} that does nothing */
  public static Spy<Runnable> runnable() {
    return of(Runnable.class, null);
  }

  /**
   * @param <T> the argument type
   * @return a spy for a {@link Consumer} that does nothing
   */
  @SuppressWarnings("unchecked")
  public static <T> Spy<Consumer<T>> consumer() {
    return of((Class<Consumer<T>>) (Class<?>) Consumer.class, null);
  }

  /**
   * @param <T> the first argument type
   * @param <U> the second argument type
   * @return a spy for a {@link BiConsumer} that does nothing
   */
  @SuppressWarnings("unchecked")
  public static <T, U> Spy<BiConsumer<T, U>> biConsumer() {
    return of((Class<BiConsumer<T, U>>) (Class<?>) BiConsumer.class, null);
  }

  /**
   * @param <T> the argument type
   * @param <R> the result type
   * @param impl the implementation
   * @return a spy for a {@link Function}
   */
  @SuppressWarnings("unchecked")
  public static <T, R> Spy<Function<T, R>> function(Function<T, R> impl) {
    return of((Class<Function<T, R>>) (Class<?>) Function.class, impl);
  }

  /**
   * @param <T> the result type
   * @param impl the implementation
   * @return a spy for a {@link Supplier}
   */
  @SuppressWarnings("unchecked")
  public static <T> Spy<Supplier<T>> supplier(Supplier<T> impl) {
    return of((Class<Supplier<T>>) (Class<?>) Supplier.class, impl);
  }

  /**
   * @param <T> the argument type
   * @param impl the implementation
   * @return a spy for a {@link Predicate}
   */
  @SuppressWarnings("unchecked")
  public static <T> Spy<Predicate<T>> predicate(Predicate<T> impl) {
    return of((Class<Predicate<T>>) (Class<?>) Predicate.class, impl);
  }

  /** @return the recording implementation of {@code F}; pass it to the code under test */
  public F get() {
    return proxy;
  }

  /** @return arguments of every call, oldest first */
  public List<List<Object>> calls() {
    synchronized (calls) {
      return Collections.unmodifiableList(new ArrayList<>(calls));
    }
  }

  /** @return number of calls so far */
  public int callCount() {
    return calls.size();
  }

  /** @return whether the spy was called at least once */
  public boolean called() {
    return !calls.isEmpty();
  }

  /** @return arguments of the most recent call */
  public List<Object> lastCall() {
    synchronized (calls) {
      if (calls.isEmpty()) throw new IllegalStateException("Spy was never called");
      return calls.get(calls.size() - 1);
    }
  }

  /** Forgets all recorded calls. */
  public void reset() {
    calls.clear();
  }

  @Override
  public String toString() {
    return "Spy<" + type.getSimpleName() + ">(calls: " + calls() + ")";
  }
}
