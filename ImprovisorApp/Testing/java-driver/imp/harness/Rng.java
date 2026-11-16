package imp.harness;

import java.util.Random;

/**
 * The single seeded random stream used by the Java engine when built for the
 * golden harness. Testing/scripts/build_java.sh rewrites, in a scratch copy of
 * the Impro-Visor source:
 *
 *   Math.random()            -> imp.harness.Rng.random()
 *   new Random()             -> imp.harness.Rng.get()
 *   Collections.shuffle(x)   -> Collections.shuffle(x, imp.harness.Rng.get())
 *
 * so every draw comes from ONE java.util.Random, in program order. The Swift
 * port threads one JavaRandom through the same call sites.
 */
public final class Rng
{
private static final Random R = new Random(0);
private static long draws = 0;

private Rng() { }

public static Random get() { return R; }

public static double random() { draws++; return R.nextDouble(); }

public static void seed(long seed) { R.setSeed(seed); draws = 0; }
}
