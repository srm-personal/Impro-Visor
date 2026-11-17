package imp.harness;

import imp.ImproVisor;
import imp.data.ChordPart;
import imp.data.MelodyPart;
import imp.roadmap.RoadMap;
import imp.roadmap.brickdictionary.Block;
import imp.roadmap.brickdictionary.BrickLibrary;
import imp.roadmap.cykparser.CYKParser;
import java.io.File;
import java.util.ArrayList;
import java.util.List;

/**
 * Stand-in for the Notate window in the solo-generation code (option B).
 *
 * imp.lickgen.LickGen and imp.lickgen.Grammar call `notate.xxx(...)` at about
 * twenty places. Notate is a JFrame and cannot exist headless, so
 * Testing/scripts/build_java.sh rewrites — in the scratch copy only — every
 * `notate.xxx(` in those two files to `imp.harness.Hooks.xxx(`. Each method
 * below returns what the real window returns in its default state; where that
 * is a judgement call it is marked ASSUMPTION and listed in BUG_LOG.md (O-06).
 */
public final class Hooks
{
/** The tune being improvised on (Notate.getChordProg / getCurrentMelodyPart). */
public static ChordPart chords;
public static MelodyPart melody;

public static final List<String> status = new ArrayList<String>();

private static BrickLibrary library;
private static CYKParser parser;

private Hooks() { }

public static ChordPart getChordProg() { return chords; }

public static MelodyPart getCurrentMelodyPart() { return melody; }

/** Status-bar text; kept so the driver can report it. */
public static void setLickGenStatus(String text) { status.add(text); }

/** Trading is off by default: Grammar.run then ignores the two values below. */
public static boolean getPassiveTrading() { return false; }

public static boolean getImprovisorTradeFirst() { return true; }

/**
 * TradingDialog.getSlotsPerTurn() = measures * slotsPerBar. Only read on the
 * syncopation paths, which the shipped grammars switch off
 * (use-syncopation false). ASSUMPTION: 4 bars of 4/4.
 */
public static int getTradingQuantum() { return 4 * 480; }

/**
 * Notate.ensureRoadmap(): make sure the chord progression has a roadmap, for
 * grammars with `(builtin brick NAME)` conditions.
 *
 * ASSUMPTION: the real method opens the roadmap window and starts the
 * analysis on a background thread, then immediately takes whatever roadmap the
 * window holds — a race. The harness uses the roadmap that analysis produces
 * when it has finished: blocks from the chords, CYK parse against
 * vocab/My.dictionary, then RoadMap.process() (joins and keys), which is what
 * RoadMapFrame.analyze + RoadMapPanel.placeBricks do.
 */
public static void ensureRoadmap()
  {
  if( chords.getRoadMap() != null )
    {
    return;
    }
  try
    {
    if( library == null )
      {
      library = new BrickLibrary();
      library.processDictionary(new File(ImproVisor.getDictionaryDirectory(), "My.dictionary").getPath());
      parser = new CYKParser();
      parser.createRules(library);
      }
    ArrayList<Block> blocks = chords.toBlockList();
    ArrayList<Block> analyzed = parser.parse(blocks, library);
    RoadMap map = new RoadMap(analyzed);
    map.process();
    chords.setRoadmap(map);
    }
  catch( Exception e )
    {
    throw new RuntimeException("roadmap analysis failed: " + e, e);
    }
  }
}
