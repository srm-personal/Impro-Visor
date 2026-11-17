package imp.harness;

import imp.ImproVisor;
import imp.data.Chord;
import imp.data.ChordPart;
import imp.data.Leadsheet;
import imp.data.MelodyPart;
import imp.data.Note;
import imp.data.Part;
import imp.data.Score;
import imp.data.Transposition;
import imp.data.Unit;
import imp.data.advice.Advisor;
import imp.style.SectionRecord;
import imp.util.ErrorLog;
import imp.util.Preferences;
import imp.voicing.AutomaticVoicingSettings;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileReader;
import java.io.PrintWriter;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Random;
import javax.sound.midi.MetaMessage;
import javax.sound.midi.MidiEvent;
import javax.sound.midi.MidiMessage;
import javax.sound.midi.MidiSystem;
import javax.sound.midi.Sequence;
import javax.sound.midi.ShortMessage;
import javax.sound.midi.Track;
import polya.Polylist;
import polya.Tokenizer;

/**
 * Headless golden generator for the Swift port's differential tests.
 *
 * Drives the unmodified Impro-Visor engine (imp.data / imp.style / ...) without
 * constructing Notate or any window. See Testing/HARNESS_PLAN.md.
 *
 *   GoldenDriver rng     OUT.tsv            java.util.Random reference vectors
 *   GoldenDriver counts  LIST.txt OUT.tsv   parse every leadsheet, dump counts
 *   GoldenDriver styles  OUT.tsv            parse every style, dump counts
 *   GoldenDriver render  CASES.tsv OUTDIR   render accompaniment goldens
 *
 * Paths in LIST/CASES are relative to the repository root (the JVM's cwd).
 */
public class GoldenDriver
{
static final short PPQN = 480;   // same as imp.com.ExportToMidiCommand / MidiSynth

public static void main(String[] args) throws Exception
  {
  if( args.length < 1 ) { usage(); }
  String mode = args[0];
  if( mode.equals("rng") )
    {
    rngVectors(args[1]);
    return;
    }
  init();
  if( mode.equals("counts") )      { counts(args[1], args[2]); }
  else if( mode.equals("roundtrip") ) { roundtrip(args[1], args[2]); }
  else if( mode.equals("save") )
    {
    // save LEADSHEET OUT.ls — Java's own writer, for comparing with Swift's.
    java.io.BufferedWriter w = new java.io.BufferedWriter(new java.io.FileWriter(args[2]));
    Leadsheet.saveLeadSheet(w, load(args[1]), false);
    w.close();
    }
  else if( mode.equals("styles") ) { styles(args[1]); }
  else if( mode.equals("render") ) { render(args[1], args[2]); }
  else if( mode.equals("solo") ) { solo(args[1], args[2]); }
  else { usage(); }
  System.exit(0);
  }

static void usage()
  {
  System.err.println("usage: GoldenDriver rng OUT | counts LIST OUT | styles OUT | render CASES OUTDIR");
  System.exit(2);
  }

// ---------------------------------------------------------------- startup

/**
 * The part of ImproVisor's private constructor that the engine needs:
 * preferences, the Advisor with the vocabulary (chords, scales), and styles.
 * LoadAdviceCommand is not used because it opens a splash dialog.
 */
static void init() throws Exception
  {
  ImproVisor.avs = new AutomaticVoicingSettings();
  ImproVisor.avs.setDefaults();
  ImproVisor.getUserDirectory();
  Preferences.loadPreferences();

  Advisor advisor = new Advisor();
  Field f = ImproVisor.class.getDeclaredField("advisor");
  f.setAccessible(true);
  f.set(null, advisor);

  File voc = new File(ImproVisor.getVocabDirectory(), "My.voc");
  Tokenizer in = new Tokenizer(new FileInputStream(voc));
  Polylist rules = new Polylist();
  Object ob;
  while( (ob = in.nextSexp()) != Tokenizer.eof )
    {
    if( (ob instanceof Polylist) && ((Polylist)ob).nonEmpty() )
      {
      rules = rules.cons((Polylist)ob);
      }
    }
  advisor.setRules(rules.reverse());
  Advisor.readStyles();
  report("init", ErrorLog.drain());
  }

static void report(String what, List<String> messages)
  {
  for( String m : messages )
    {
    System.err.println("[" + what + "] " + m);
    }
  }

static Score load(String path) throws Exception
  {
  Score score = new Score();
  FileInputStream stream = new FileInputStream(new File(path));
  try
    {
    Leadsheet.readLeadSheet(new Tokenizer(stream), score);
    }
  finally
    {
    stream.close();
    }
  // The GUI normalizes part lengths as soon as it touches the score
  // (Score.size() → checkLength()); do the same so renders match the app.
  score.checkLength();
  return score;
  }

/** Counts row for a score (shared by `counts` and `roundtrip`). */
static String describe(Score score)
  {
  StringBuilder b = new StringBuilder();
  ChordPart chords = score.getChordProg();
  int units = 0;
  StringBuilder first = new StringBuilder();
  Part.PartIterator it = chords.iterator();
  while( it.hasNext() )
    {
    Chord c = (Chord)it.next();
    if( units < 6 )
      {
      if( units > 0 ) first.append(' ');
      first.append(c.getName()).append('/').append(c.getRhythmValue());
      }
    units++;
    }
  StringBuilder parts = new StringBuilder();
  for( int p = 0; p < score.size(); p++ )
    {
    MelodyPart m = score.getPart(p);
    int notes = 0, rests = 0;
    Part.PartIterator mi = m.iterator();
    while( mi.hasNext() )
      {
      Unit u = mi.next();
      if( u instanceof Note )
        {
        if( ((Note)u).isRest() ) rests++; else notes++;
        }
      }
    if( p > 0 ) parts.append(' ');
    parts.append(m.size()).append(':').append(notes).append(':').append(rests);
    }
  int[] metre = score.getMetre();
  b.append("\tok\t").append(metre[0]).append('/').append(metre[1]);
  b.append('\t').append(score.getTempo());
  b.append('\t').append(score.getKeySignature());
  b.append('\t').append(chords.size());
  b.append('\t').append(units);
  b.append('\t').append(chords.getSectionInfo().size());
  b.append('\t').append(score.size());
  b.append('\t').append(parts);
  b.append('\t').append(clean(first.toString()));
  return b.toString();
  }

/** Java's own load → save → reload, reported in the `counts` format. */
static void roundtrip(String listFile, String outFile) throws Exception
  {
  PrintWriter out = new PrintWriter(outFile, "UTF-8");
  File tmp = File.createTempFile("harness", ".ls");
  for( String path : readLines(listFile) )
    {
    StringBuilder b = new StringBuilder(path);
    try
      {
      Score score = load(path);
      java.io.BufferedWriter w = new java.io.BufferedWriter(new java.io.FileWriter(tmp));
      Leadsheet.saveLeadSheet(w, score, false);
      w.close();
      b.append(describe(load(tmp.getPath())));
      }
    catch( Throwable t )
      {
      b.append("\tthrew\t").append(clean(t.toString()));
      }
    List<String> messages = ErrorLog.drain();
    b.append('\t').append(messages.size());
    if( !messages.isEmpty() ) b.append(' ').append(clean(messages.get(0)));
    out.println(b);
    }
  tmp.delete();
  out.close();
  }

static List<String> readLines(String file) throws Exception
  {
  List<String> lines = new ArrayList<String>();
  BufferedReader r = new BufferedReader(new FileReader(file));
  String line;
  while( (line = r.readLine()) != null )
    {
    if( line.trim().length() > 0 && !line.startsWith("#") )
      {
      lines.add(line);
      }
    }
  r.close();
  return lines;
  }

static String clean(String s)
  {
  return s == null ? "" : s.replace('\t', ' ').replace('\n', ' ').replace('\r', ' ');
  }

// ---------------------------------------------------------------- counts

static void counts(String listFile, String outFile) throws Exception
  {
  PrintWriter out = new PrintWriter(outFile, "UTF-8");
  out.println("#file\tstatus\tmetre\ttempo\tkey\tchordSlots\tchordUnits\tsections\tparts\tpartDetail(size:notes:rests)\tfirstChords\tmessages");
  for( String path : readLines(listFile) )
    {
    // Leadsheet style headers mutate the shared Style objects; that does not
    // affect counts, so styles are not reloaded here.
    StringBuilder b = new StringBuilder(path);
    try
      {
      b.append(describe(load(path)));
      }
    catch( Throwable t )
      {
      b.append("\tthrew\t").append(clean(t.toString()));
      }
    List<String> messages = ErrorLog.drain();
    b.append('\t').append(messages.size());
    if( !messages.isEmpty() ) b.append(' ').append(clean(messages.get(0)));
    out.println(b);
    }
  out.close();
  }

static void styles(String outFile) throws Exception
  {
  PrintWriter out = new PrintWriter(outFile, "UTF-8");
  out.println("#style\tbass\tchord\tdrum\tswing\tcompSwing\tvoicingType\tbassLow\tbassHigh\tchordLow\tchordHigh\tbassDurations\tchordDurations\tdrumDurations");
  int n = imp.style.Style.numberOfStyles();
  for( int i = 0; i < n; i++ )
    {
    imp.style.Style s = imp.style.Style.getNth(i);
    StringBuilder b = new StringBuilder(s.getName());
    b.append('\t').append(s.getBP().size());
    b.append('\t').append(s.getCP().size());
    b.append('\t').append(s.getDP().size());
    b.append('\t').append(s.getSwing());
    b.append('\t').append(s.getAccompanimentSwing());
    b.append('\t').append(s.getVoicingType());
    b.append('\t').append(s.getBassLow().getMIDI());
    b.append('\t').append(s.getBassHigh().getMIDI());
    b.append('\t').append(s.getChordLow().getMIDI());
    b.append('\t').append(s.getChordHigh().getMIDI());
    StringBuilder d = new StringBuilder();
    for( imp.style.stylePatterns.BassPattern p : s.getBP() ) d.append(p.getDuration()).append(':').append(p.getWeight()).append(' ');
    b.append('\t').append(d.toString().trim());
    d = new StringBuilder();
    for( imp.style.stylePatterns.ChordPattern p : s.getCP() ) d.append(p.getDuration()).append(':').append(p.getWeight()).append(' ');
    b.append('\t').append(d.toString().trim());
    d = new StringBuilder();
    for( imp.style.stylePatterns.DrumPattern p : s.getDP() ) d.append(p.getDuration()).append(':').append(p.getWeight()).append(' ');
    b.append('\t').append(d.toString().trim());
    out.println(b);
    }
  out.close();
  }

// ---------------------------------------------------------------- render

/**
 * CASES.tsv columns: id, leadsheet path, style name or "-" (keep the
 * leadsheet's own styles/sections), seed.
 */
static void render(String casesFile, String outDir) throws Exception
  {
  new File(outDir).mkdirs();
  for( String line : readLines(casesFile) )
    {
    String[] c = line.split("\t");
    String id = c[0], path = c[1], style = c[2];
    long seed = Long.parseLong(c[3]);
    try
      {
      // Leadsheet (style ...) headers mutate the shared Style objects, so
      // start every case from freshly parsed styles.
      Advisor.readStyles();
      ErrorLog.drain();
      Score score = load(path);
      if( !style.equals("-") )
        {
        // One section, the whole tune, in the requested style.
        score.getChordProg().setStyle(style);
        }
      Rng.seed(seed);
      // Exactly what the app does for Play (PlayScoreCommand:300-323) and for
      // MIDI export (ExportToMidiCommand:115-121): swing a COPY of the score,
      // then render it.
      // The app renders with the leadsheet's own playback transposition
      // (Notate.getTransposition()); Score.copy() does not carry it over.
      Transposition transposition = score.getTransposition();
      score = score.copy();
      score.makeSwing();
      Sequence seq = score.render(PPQN, transposition);
      List<String> messages = ErrorLog.drain();
      writeEvents(new File(outDir, id + ".events.txt"), id, path, style, seed, score, seq, messages);
      MidiSystem.write(seq, 1, new File(outDir, id + ".mid"));
      }
    catch( Throwable t )
      {
      System.err.println("[render " + id + "] threw " + t);
      t.printStackTrace();
      PrintWriter out = new PrintWriter(new File(outDir, id + ".events.txt"), "UTF-8");
      out.println("# id " + id);
      out.println("# threw " + clean(t.toString()));
      out.close();
      }
    }
  }

static class Ev
  {
  int channel; long tick; int pitch; int velocity; long duration;
  }

/**
 * Note events, canonically ordered by (tick, channel, pitch, velocity,
 * duration). Simultaneous events have no meaningful order in a MIDI track, and
 * javax.sound.midi.Track.add's ordering of same-tick events is an
 * implementation detail, so the dump does not preserve it.
 */
static void writeEvents(File file, String id, String path, String style, long seed,
                        Score score, Sequence seq, List<String> messages) throws Exception
  {
  List<Ev> evs = new ArrayList<Ev>();
  List<String> programs = new ArrayList<String>();
  long endTick = -1;
  Track[] tracks = seq.getTracks();
  for( int t = 0; t < tracks.length; t++ )
    {
    Track track = tracks[t];
    HashMap<Integer, ArrayList<Ev>> open = new HashMap<Integer, ArrayList<Ev>>();
    for( int i = 0; i < track.size(); i++ )
      {
      MidiEvent me = track.get(i);
      MidiMessage mm = me.getMessage();
      if( mm instanceof ShortMessage )
        {
        ShortMessage sm = (ShortMessage)mm;
        int cmd = sm.getCommand();
        int key = sm.getChannel() * 128 + sm.getData1();
        if( cmd == ShortMessage.NOTE_ON && sm.getData2() > 0 )
          {
          Ev e = new Ev();
          e.channel = sm.getChannel(); e.tick = me.getTick(); e.pitch = sm.getData1();
          e.velocity = sm.getData2(); e.duration = -1;
          evs.add(e);
          ArrayList<Ev> q = open.get(key);
          if( q == null ) { q = new ArrayList<Ev>(); open.put(key, q); }
          q.add(e);
          }
        else if( cmd == ShortMessage.NOTE_OFF || cmd == ShortMessage.NOTE_ON )
          {
          ArrayList<Ev> q = open.get(key);
          if( q != null && !q.isEmpty() )
            {
            Ev e = q.remove(0);          // FIFO pairing
            e.duration = me.getTick() - e.tick;
            }
          }
        else if( cmd == ShortMessage.PROGRAM_CHANGE )
          {
          String p = sm.getChannel() + " " + sm.getData1();
          if( !programs.contains(p) ) programs.add(p);
          }
        }
      else if( mm instanceof MetaMessage && ((MetaMessage)mm).getType() == 47 )
        {
        endTick = Math.max(endTick, me.getTick());
        }
      }
    }
  Collections.sort(evs, new Comparator<Ev>()
    {
    public int compare(Ev a, Ev b)
      {
      if( a.tick != b.tick ) return Long.compare(a.tick, b.tick);
      if( a.channel != b.channel ) return Integer.compare(a.channel, b.channel);
      if( a.pitch != b.pitch ) return Integer.compare(a.pitch, b.pitch);
      if( a.velocity != b.velocity ) return Integer.compare(a.velocity, b.velocity);
      return Long.compare(a.duration, b.duration);
      }
    });

  PrintWriter out = new PrintWriter(file, "UTF-8");
  out.println("# id " + id);
  out.println("# leadsheet " + path);
  out.println("# style " + style);
  out.println("# seed " + seed);
  out.println("# ppqn " + seq.getResolution());
  int[] metre = score.getMetre();
  out.println("# metre " + metre[0] + "/" + metre[1]);
  out.println("# tempo " + score.getTempo());
  out.println("# chordSlots " + score.getChordProg().size());
  StringBuilder sec = new StringBuilder();
  for( SectionRecord r : score.getChordProg().getSectionRecords() )
    {
    sec.append(' ').append(r.getStyleName()).append('@').append(r.getIndex());
    }
  out.println("# sections" + sec);
  out.println("# channels melody=" + ImproVisor.getMelodyChannel() + " chord=" + ImproVisor.getChordChannel()
              + " bass=" + ImproVisor.getBassChannel() + " drum=" + ImproVisor.getDrumChannel());
  for( String p : programs ) out.println("# program " + p);
  for( String m : messages ) out.println("# message " + clean(m));
  out.println("# endTick " + endTick);
  out.println("# columns: channel tick pitch velocity duration");
  for( Ev e : evs )
    {
    out.println(e.channel + " " + e.tick + " " + e.pitch + " " + e.velocity + " " + e.duration);
    }
  out.close();
  }

// ---------------------------------------------------------------- solo

/**
 * CASES.tsv columns: id, leadsheet path, grammar file name, seed.
 *
 * Follows Notate.originalGenerate / makeLick / putLick for the default
 * settings (use grammar; no soloist outline, critic, transform or trading),
 * improvising over the whole first chorus. Three stages are dumped so the
 * Swift port can be matched one stage at a time:
 *
 *   abstract   the abstract melody from Grammar.run
 *   lick       the notes from LickGen.fillMelody, trimmed as Notate trims them
 *   rectified  after RectifyPitchesCommand, when the grammar has rectify true
 */
static void solo(String casesFile, String outDir) throws Exception
  {
  new File(outDir).mkdirs();
  for( String line : readLines(casesFile) )
    {
    String[] c = line.split("\t");
    String id = c[0], path = c[1], grammarName = c[2];
    long seed = Long.parseLong(c[3]);
    PrintWriter out = new PrintWriter(new File(outDir, id + ".solo.txt"), "UTF-8");
    out.println("# id " + id);
    out.println("# leadsheet " + path);
    out.println("# grammar " + grammarName);
    out.println("# seed " + seed);
    try
      {
      ErrorLog.drain();
      Hooks.status.clear();
      Score score = load(path);
      ChordPart chordProg = score.getChordProg();
      Hooks.chords = chordProg;
      Hooks.melody = score.getPart(0);

      // Seed BEFORE constructing LickGen: its field initializer draws once
      // (prevPitch = (int)(Math.random() * 20 + 60)).
      Rng.seed(seed);
      String grammarFile = new File(ImproVisor.getGrammarDirectory(), grammarName).getPath();
      imp.lickgen.LickGen lickgen = new imp.lickgen.LickGen(grammarFile, null, null);

      // LickgenFrame.resetTriageParameters: the fill parameters come from the grammar.
      int minPitch = Integer.parseInt(lickgen.getParameter(imp.lickgen.LickGen.MIN_PITCH_STRING));
      int maxPitch = Integer.parseInt(lickgen.getParameter(imp.lickgen.LickGen.MAX_PITCH_STRING));
      int minInterval = Integer.parseInt(lickgen.getParameter(imp.lickgen.LickGen.MIN_INTERVAL));
      int maxInterval = Integer.parseInt(lickgen.getParameter(imp.lickgen.LickGen.MAX_INTERVAL));
      double leapProb = Double.parseDouble(lickgen.getParameter(imp.lickgen.LickGen.LEAP_PROB));
      double chordToneWeight = Double.parseDouble(lickgen.getParameter(imp.lickgen.LickGen.CHORD_TONE_WEIGHT));
      double colorToneWeight = Double.parseDouble(lickgen.getParameter(imp.lickgen.LickGen.COLOR_TONE_WEIGHT));
      double scaleToneWeight = Double.parseDouble(lickgen.getParameter(imp.lickgen.LickGen.SCALE_TONE_WEIGHT));
      double chordToneDecay = Double.parseDouble(lickgen.getParameter(imp.lickgen.LickGen.CHORD_TONE_DECAY));
      boolean avoidRepeats = Boolean.parseBoolean(lickgen.getParameter(imp.lickgen.LickGen.AVOID_REPEATS));
      boolean rectify = Boolean.parseBoolean(lickgen.getParameter(imp.lickgen.LickGen.RECTIFY));

      // resetTriageParameters(true), run whenever a grammar is loaded.
      lickgen.setPreferredScale(lickgen.getParameter(imp.lickgen.LickGen.SCALE_ROOT),
                                lickgen.getParameter(imp.lickgen.LickGen.SCALE_TYPE));

      // Notate.originalGenerate with nothing selected.
      int start = 0;
      int end = chordProg.size();
      int totalSlots = end - start + 1;
      int beatsRequested = totalSlots / imp.Constants.BEAT;

      // ASSUMPTION: the pitch-probability grid holds what "Fill" computes from
      // the grammar's weights (LickgenFrame.FillProbsButtonActionPerformed).
      lickgen.setProbs(lickgen.fillProbs(chordProg, chordToneWeight, scaleToneWeight, colorToneWeight,
                                         chordToneDecay, start, totalSlots));

      Polylist abstractMelody = lickgen.generateRhythmFromGrammar(start, totalSlots);
      out.println("# abstract " + clean(String.valueOf(abstractMelody)));

      MelodyPart lick = lickgen.fillMelody(minPitch, maxPitch, minInterval, maxInterval, imp.Constants.BEAT,
                                           leapProb, abstractMelody, chordProg, start, avoidRepeats);
      // Notate.makeLick, then originalGenerate.
      int desiredSize = end - start + 1;
      if( lick.size() > desiredSize )
        {
        lick = lick.extract(0, desiredSize - 1, true);
        }
      if( lick.size() / imp.Constants.BEAT > beatsRequested )
        {
        lick = lick.extract(0, imp.Constants.BEAT * beatsRequested - 1, true);
        }
      out.println("# params minPitch=" + minPitch + " maxPitch=" + maxPitch + " minInterval=" + minInterval
                  + " maxInterval=" + maxInterval + " leapProb=" + leapProb + " avoidRepeats=" + avoidRepeats
                  + " rectify=" + rectify);
      out.println("# chordSlots " + chordProg.size());
      dumpPart(out, "lick", lick);

      // Notate.putLick: paste into the chorus, then rectify the selection.
      MelodyPart target = score.getPart(0);
      target.newPasteOver(lick, start);
      if( rectify )
        {
        // LickgenFrame.getRectifyOptions(): the dialog's initial check boxes —
        // chord on, color OFF, approach on, "avoid repeats" on
        // (LickgenFrame.java:1253, 1276, 1084; colorBox is never selected).
        new imp.com.RectifyPitchesCommand(target, start, end, chordProg, false, false,
                                          true, false, true, true).execute();
        }
      dumpPart(out, "rectified", target);
      for( String m : Hooks.status ) out.println("# status " + clean(m));
      for( String m : ErrorLog.drain() ) out.println("# message " + clean(m));
      }
    catch( Throwable t )
      {
      out.println("# threw " + clean(t.toString()));
      StackTraceElement[] st = t.getStackTrace();
      for( int i = 0; i < Math.min(6, st.length); i++ ) out.println("# at " + st[i]);
      }
    out.close();
    }
  }

/** One line per unit: stage, slot, pitch (-1 = rest), duration, volume. */
static void dumpPart(PrintWriter out, String stage, MelodyPart part)
  {
  out.println("# " + stage + " size " + part.size());
  int slot = 0;
  Part.PartIterator it = part.iterator();
  while( it.hasNext() )
    {
    int index = it.nextIndex();
    Unit u = it.next();
    if( u instanceof Note )
      {
      Note n = (Note)u;
      out.println(stage + " " + index + " " + (n.isRest() ? -1 : n.getPitch()) + " " + n.getRhythmValue()
                  + " " + n.getVolume());
      }
    slot = index;
    }
  }

// ---------------------------------------------------------------- rng

/**
 * Reference vectors from the real java.util.Random, for the Swift JavaRandom
 * unit test. One line per (seed, method): the first 12 results.
 */
static void rngVectors(String outFile) throws Exception
  {
  long[] seeds = {0L, 1L, 42L, -1L, 123456789L, 0x5DEECE66DL, Long.MAX_VALUE, Long.MIN_VALUE, 20261116L};
  int[] bounds = {1, 2, 3, 7, 10, 16, 100, 1000, 1 << 20, (1 << 30) + 1, Integer.MAX_VALUE};
  PrintWriter out = new PrintWriter(outFile, "UTF-8");
  int n = 12;
  for( long seed : seeds )
    {
    Random r = new Random(seed);
    StringBuilder b = new StringBuilder(seed + "\tnextInt");
    for( int i = 0; i < n; i++ ) b.append('\t').append(r.nextInt());
    out.println(b);
    for( int bound : bounds )
      {
      r = new Random(seed);
      b = new StringBuilder(seed + "\tnextInt:" + bound);
      for( int i = 0; i < n; i++ ) b.append('\t').append(r.nextInt(bound));
      out.println(b);
      }
    r = new Random(seed);
    b = new StringBuilder(seed + "\tnextLong");
    for( int i = 0; i < n; i++ ) b.append('\t').append(r.nextLong());
    out.println(b);
    r = new Random(seed);
    b = new StringBuilder(seed + "\tnextDouble");
    for( int i = 0; i < n; i++ ) b.append('\t').append(Long.toString(Double.doubleToLongBits(r.nextDouble())));
    out.println(b);
    r = new Random(seed);
    b = new StringBuilder(seed + "\tnextFloat");
    for( int i = 0; i < n; i++ ) b.append('\t').append(Integer.toString(Float.floatToIntBits(r.nextFloat())));
    out.println(b);
    r = new Random(seed);
    b = new StringBuilder(seed + "\tnextBoolean");
    for( int i = 0; i < n; i++ ) b.append('\t').append(r.nextBoolean() ? 1 : 0);
    out.println(b);
    r = new Random(seed);
    b = new StringBuilder(seed + "\tnextGaussian");
    for( int i = 0; i < n; i++ ) b.append('\t').append(Long.toString(Double.doubleToLongBits(r.nextGaussian())));
    out.println(b);
    // Interleaved, as the engine uses the stream.
    r = new Random(seed);
    b = new StringBuilder(seed + "\tmixed");
    for( int i = 0; i < n; i++ )
      {
      b.append('\t').append(r.nextInt(3));
      b.append('\t').append(Long.toString(Double.doubleToLongBits(r.nextDouble())));
      b.append('\t').append(r.nextInt(100));
      }
    out.println(b);
    }
  out.close();
  }
}
