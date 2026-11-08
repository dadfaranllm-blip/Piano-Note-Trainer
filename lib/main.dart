import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Allow both portrait and landscape; the user can lock a preferred mode in settings.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(const PianoTrainerApp());
}

const noteLetters = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
const persianLetters = ['دو', 'ر', 'می', 'فا', 'سل', 'لا', 'سی'];
const noteSemitones = [0, 2, 4, 5, 7, 9, 11];

enum NoteNames { persian, english, both }
enum Clef { treble, bass }
enum Drill { single, melody, song }
enum SongPlayMode { staff, falling, combined }
enum Pace {
  free('آزاد', 0), slow('آرام', 12), normal('متوسط', 8),
  fast('سریع', 5), expert('چالشی', 3);
  const Pace(this.title, this.seconds);
  final String title;
  final int seconds;
}

class MusicNote {
  const MusicNote(this.letter, this.octave, this.midi, this.step);
  final String letter;
  final int octave;
  final int midi;
  // Steps relative to C4, independent of the selected clef.
  final int step;
  String get latin => '$letter$octave';
  String get persian => persianLetters[noteLetters.indexOf(letter)];
  String label(NoteNames display) => switch (display) {
    NoteNames.persian => '$persian$octave',
    NoteNames.english => latin,
    NoteNames.both => '$persian ($latin)',
  };
}

final List<MusicNote> allNotes = List.unmodifiable([
  for (var octave = 2; octave <= 6; octave++)
    for (var index = 0; index < 7; index++)
      MusicNote(noteLetters[index], octave,
          12 * (octave + 1) + noteSemitones[index],
          (octave - 4) * 7 + index),
]);

List<MusicNote> notesForSelection(Set<int> octaves, Set<String> letters) => allNotes.where((n) => octaves.contains(n.octave) && letters.contains(n.letter)).toList(growable: false);

int effectiveTempo(int baseBpm, int speedPercent) => (baseBpm * speedPercent / 100).round().clamp(20, 320).toInt();

// Treble: E4 bottom, F5 top; bass: G2 bottom, A3 top.
// Return distance in staff diatonic steps from bottom line.
int staffPosition(MusicNote note, Clef clef) =>
    note.step - (clef == Clef.treble ? 2 : -10);

class PracticeSong {
  const PracticeSong(this.id, this.title, this.author, this.pitchNames);
  final String id;
  final String title;
  final String author;
  final List<String> pitchNames;
  // Durations in quarter-note beats.  For songs that have no explicit rhythm
  // data, use quarter notes except at phrase endings.
  List<double> get beats => List<double>.generate(pitchNames.length, (i) {
    if (id == 'twinkle') return [6, 13].contains(i) ? 2.0 : 1.0;
    if (id == 'steps') return i == pitchNames.length - 1 ? 2.0 : 1.0;
    if (id == 'ode') return [13, 14, 28, 29].contains(i) ? 2.0 : 1.0;
    if (id == 'mary') return [6, 9, 12, 25].contains(i) ? 2.0 : 1.0;
    return 1.0;
  });
  List<MusicNote> get notes => pitchNames.map((name) =>
    allNotes.firstWhere((note) => note.latin == name)).toList(growable: false);
}

// Traditional / public-domain melodies and an original exercise.
const practiceSongs = <PracticeSong>[
  PracticeSong('steps', 'قدم‌های موسیقی', 'تمرین اختصاصی',
    ['C4','D4','E4','F4','G4','F4','E4','D4','C4']),
  PracticeSong('twinkle', 'ستاره کوچولو', 'ملودی سنتی',
    ['C4','C4','G4','G4','A4','A4','G4','F4','F4','E4','E4','D4','D4','C4']),
  PracticeSong('ode', 'سرود شادی', 'بتهوون — اثر در مالکیت عمومی',
    ['E4','E4','F4','G4','G4','F4','E4','D4','C4','C4','D4','E4','E4','D4','D4',
     'E4','E4','F4','G4','G4','F4','E4','D4','C4','C4','D4','E4','D4','C4','C4']),
  PracticeSong('mary', 'مری یک بره داشت', 'ملودی سنتی',
    ['E4','D4','C4','D4','E4','E4','E4','D4','D4','D4','E4','G4','G4',
     'E4','D4','C4','D4','E4','E4','E4','E4','D4','D4','E4','D4','C4']),
];

class PianoTrainerApp extends StatelessWidget {
  const PianoTrainerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'نت‌خوان پیانو', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF37745D)),
      scaffoldBackgroundColor: const Color(0xFFF6F5EF),
      useMaterial3: true,
    ),
    home: const Directionality(textDirection: TextDirection.rtl, child: TrainerPage()),
  );
}

class TrainerPage extends StatefulWidget {
  const TrainerPage({super.key});
  @override
  State<TrainerPage> createState() => _TrainerPageState();
}

class _TrainerPageState extends State<TrainerPage> with WidgetsBindingObserver {
  static const sound = MethodChannel('piano_note_trainer/sound');
  static const storage = MethodChannel('piano_note_trainer/storage');
  final random = Random();
  final Map<int, int> mistakes = {};
  final Set<String> selectedLetters = {...noteLetters};
  final Set<int> selectedOctaves = {4};
  final List<int> questionBag = [];
  String questionBagSignature = '';
  SongPlayMode songPlayMode = SongPlayMode.staff;
  final Map<String, SongPlayMode> songModes = {};
  SongPlayMode get activeSongPlayMode => songModes[chosenSong] ?? songPlayMode;
  int speedPercent = 100;
  bool autoSpeed = false;
  int successfulSongStreak = 0;
  String orientationMode = 'auto';
  bool reminderEnabled = false;
  int reminderHour = 19;
  int reminderMinute = 0;
  final Map<String, int> practiceSecondsByDay = {};
  final Map<String, int> correctByDay = {};
  final Map<String, int> attemptsByDay = {};
  Timer? activityTimer;
  int secondsSinceSave = 0;
  bool inactivitySaved = false;
  NoteNames naming = NoteNames.both;
  Clef clef = Clef.treble;
  Drill drill = Drill.single;
  Pace pace = Pace.free;
  int stage = 1;
  String chosenSong = 'steps';
  int songErrors = 0;
  int rhythmErrors = 0;
  int rhythmSuccess = 0;
  DateTime? songStartTime;
  DateTime? lastPracticeInteraction;
  final Set<int> songErroredIndices = {};
  bool checkRhythm = true;
  int bpm = 80;
  final Set<String> completedLessons = {};
  final Map<String, int> lessonScores = {};
  final Map<String, int> bestSongScores = {};
  int completedSongs = 0;
  bool loaded = false;
  bool smartPractice = true;
  bool showKeyLabels = true;
  bool revealAnswer = false;
  bool locked = false;
  int correct = 0;
  int attempts = 0;
  int streak = 0;
  int secondsLeft = 0;
  int questionSerial = 0;
  int melodyIndex = 0;
  int? pressedMidi;
  String status = 'نت روی حامل را با پیانو بنواز';
  Color statusColor = const Color(0xFF53665D);
  List<MusicNote> phrase = [];
  Timer? ticker;
  Timer? transition;
  Timer? fallingMissTimer;

  MusicNote get target => phrase[melodyIndex];
  PracticeSong get currentSong => practiceSongs.firstWhere((s) => s.id == chosenSong);
  Clef get effectiveClef => drill == Drill.song ? Clef.treble : clef;
  int get effectiveOctave => drill == Drill.song ? 4 : (selectedOctaves.isEmpty ? 4 : selectedOctaves.reduce(min));
  int get effectiveOctaveCount => drill == Drill.song ? 2 : max(1, (selectedOctaves.isEmpty ? 4 : selectedOctaves.reduce(max)) - effectiveOctave + 1).toInt();
  int get effectiveBpm => effectiveTempo(bpm, speedPercent);
  String get todayKey => _dayKey(DateTime.now());
  String get selectedOctaveLabel { final values = selectedOctaves.toList()..sort(); return values.join(', '); }
  static String _dayKey(DateTime d) => '${d.year.toString().padLeft(4,"0")}-${d.month.toString().padLeft(2,"0")}-${d.day.toString().padLeft(2,"0")}';

  List<MusicNote> get pool => notesForSelection(selectedOctaves, selectedLetters);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    phrase = [allNotes.firstWhere((n) => n.midi == 60)];
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) restoreProgress(); });
  }

  MusicNote choose(List<MusicNote> options, {int? previousMidi}) {
    if (options.isEmpty) throw StateError('No notes selected for practice.');
    final ids = options.map((n) => n.midi).toList()..sort();
    final signature = '${ids.join(',')}:${smartPractice ? 1 : 0}';
    if (questionBag.isEmpty || questionBagSignature != signature) {
      questionBagSignature = signature;
      questionBag..clear()..addAll(ids)..shuffle(random);
      // Smart review is appended after every selected note has appeared once.
      if (smartPractice) {
        final review = <int>[];
        for (final note in options) {
          final extra = ((mistakes[note.midi] ?? 0) ~/ 2).clamp(0, 3);
          for (var i = 0; i < extra; i++) { review.add(note.midi); }
        }
        review.shuffle(random);
        questionBag.addAll(review);
      }
    }
    final previous = previousMidi ?? (phrase.isNotEmpty ? phrase.last.midi : -1);
    if (questionBag.length > 1 && questionBag.first == previous) {
      final alternative = questionBag.indexWhere((midi) => midi != previous);
      if (alternative > 0) {
        final first = questionBag[0];
        questionBag[0] = questionBag[alternative];
        questionBag[alternative] = first;
      }
    }
    final selected = questionBag.removeAt(0);
    return options.firstWhere((note) => note.midi == selected);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (loaded) startActivityClock();
    } else {
      activityTimer?.cancel();
      saveProgress();
    }
  }

  void startActivityClock() {
    activityTimer?.cancel();
    activityTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !loaded) return;
      final lastInput = lastPracticeInteraction;
      if (lastInput == null || DateTime.now().difference(lastInput) > const Duration(minutes: 2)) {
        if (!inactivitySaved) { inactivitySaved = true; saveProgress(); }
        return;
      }
      final key = todayKey;
      practiceSecondsByDay[key] = (practiceSecondsByDay[key] ?? 0) + 1;
      secondsSinceSave++;
      if (secondsSinceSave >= 10) {
        secondsSinceSave = 0;
        saveProgress();
      }
      if (mounted) setState(() {});
    });
  }

  void recordAnswer(bool isCorrect) {
    final key = todayKey;
    attemptsByDay[key] = (attemptsByDay[key] ?? 0) + 1;
    if (isCorrect) correctByDay[key] = (correctByDay[key] ?? 0) + 1;
  }

  Future<void> setOrientation(String mode) async {
    orientationMode = mode;
    final orientations = mode == 'portrait'
      ? [DeviceOrientation.portraitUp]
      : mode == 'landscape'
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
    await SystemChrome.setPreferredOrientations(orientations);
    if (mounted) setState(() {});
    saveProgress();
  }

  Future<void> configureReminder(bool enabled, int hour, int minute) async {
    reminderEnabled = enabled;
    reminderHour = hour;
    reminderMinute = minute;
    try {
      await const MethodChannel('piano_note_trainer/reminders').invokeMethod<void>(
        'configure', {'enabled': enabled, 'hour': hour, 'minute': minute});
    } catch (_) { /* The app remains usable if the native reminder bridge is unavailable. */ }
    if (mounted) setState(() {});
    saveProgress();
  }

  Future<void> openDashboard() async {
    lastPracticeInteraction = null;
    cancelTimers();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      Directionality(textDirection: TextDirection.rtl, child: ProgressDashboard(
        secondsByDay: Map.of(practiceSecondsByDay), correctByDay: Map.of(correctByDay),
        attemptsByDay: Map.of(attemptsByDay)))));
    if (mounted) newQuestion();
  }

  void cancelTimers() { ticker?.cancel(); transition?.cancel(); fallingMissTimer?.cancel(); }

  Future<void> restoreProgress() async {
    try {
      final encoded = await storage.invokeMethod<String>('read');
      if (encoded != null && encoded.isNotEmpty) {
        final data = jsonDecode(encoded) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          correct = (data['correct'] as num?)?.toInt() ?? 0;
          attempts = (data['attempts'] as num?)?.toInt() ?? 0;
          completedSongs = (data['completedSongs'] as num?)?.toInt() ?? 0;
          checkRhythm = data['checkRhythm'] != false;
          speedPercent = ((data['speedPercent'] as num?)?.toInt() ?? 100).clamp(25, 200).toInt();
          autoSpeed = data['autoSpeed'] == true;
          successfulSongStreak = (data['successfulSongStreak'] as num?)?.toInt() ?? 0;
          songPlayMode = SongPlayMode.values.firstWhere((v) => v.name == data['songPlayMode'], orElse: () => SongPlayMode.staff);
          for (final entry in (data['songModes'] as Map? ?? {}).entries) { songModes[entry.key.toString()] = SongPlayMode.values.firstWhere((v) => v.name == entry.value, orElse: () => SongPlayMode.staff); }
          orientationMode = (data['orientationMode'] as String?) ?? 'auto';
          reminderEnabled = data['reminderEnabled'] == true;
          reminderHour = ((data['reminderHour'] as num?)?.toInt() ?? 19).clamp(0, 23).toInt();
          reminderMinute = ((data['reminderMinute'] as num?)?.toInt() ?? 0).clamp(0, 59).toInt();
          for (final entry in (data['practiceSecondsByDay'] as Map? ?? {}).entries) { if (entry.value is num) practiceSecondsByDay[entry.key.toString()] = (entry.value as num).toInt(); }
          for (final entry in (data['correctByDay'] as Map? ?? {}).entries) { if (entry.value is num) correctByDay[entry.key.toString()] = (entry.value as num).toInt(); }
          for (final entry in (data['attemptsByDay'] as Map? ?? {}).entries) { if (entry.value is num) attemptsByDay[entry.key.toString()] = (entry.value as num).toInt(); }
          bpm = ((data['bpm'] as num?)?.toInt() ?? 80).clamp(40, 160).toInt();
          completedLessons.addAll((data['completedLessons'] as List? ?? []).whereType<String>());
          for (final entry in (data['lessonScores'] as Map? ?? {}).entries) {
            if (entry.value is num) lessonScores[entry.key.toString()] = (entry.value as num).toInt();
          }
          for (final entry in (data['mistakes'] as Map? ?? {}).entries) {
            final key = int.tryParse(entry.key.toString());
            if (key != null && entry.value is num) mistakes[key] = (entry.value as num).toInt();
          }
          for (final entry in (data['bestSongs'] as Map? ?? {}).entries) {
            if (entry.value is num) bestSongScores[entry.key.toString()] = (entry.value as num).toInt();
          }
          naming = NoteNames.values.firstWhere((v) => v.name == data['naming'], orElse: () => NoteNames.both);
          clef = Clef.values.firstWhere((v) => v.name == data['clef'], orElse: () => Clef.treble);
          drill = Drill.values.firstWhere((v) => v.name == data['drill'], orElse: () => Drill.single);
          pace = Pace.values.firstWhere((v) => v.name == data['pace'], orElse: () => Pace.free);
          stage = ((data['stage'] as num?)?.toInt() ?? 1).clamp(1, 4).toInt();
          chosenSong = practiceSongs.any((v) => v.id == data['chosenSong']) ? data['chosenSong'] as String : 'steps';
          smartPractice = data['smartPractice'] != false;
          showKeyLabels = data['showKeyLabels'] != false;
          final octaves = data['selectedOctaves'];
          if (octaves is List) { final valid = octaves.whereType<num>().map((v) => v.toInt()).where((v) => v >= 2 && v <= 6).toSet(); if (valid.isNotEmpty) selectedOctaves..clear()..addAll(valid); }
          final previousSelection = data['selectedLetters'];
          if (previousSelection is List) {
            final valid = previousSelection.whereType<String>().where(noteLetters.contains).toSet();
            if (valid.isNotEmpty) { selectedLetters..clear()..addAll(valid); }
          }
        });
      }
    } catch (_) { /* Malformed or unsupported storage: safely use defaults. */ }
    if (!mounted) return;
    loaded = true;
    if (orientationMode == 'portrait' || orientationMode == 'landscape') { await setOrientation(orientationMode); }
    if (reminderEnabled) { await configureReminder(true, reminderHour, reminderMinute); }
    startActivityClock();
    newQuestion();
  }

  Future<void> saveProgress() async {
    if (!loaded) return;
    final encoded = jsonEncode({
      'correct': correct, 'attempts': attempts, 'mistakes': mistakes.map((k,v) => MapEntry('$k',v)),
      'completedSongs': completedSongs, 'bestSongs': bestSongScores,
      'naming': naming.name, 'clef': clef.name, 'drill': drill.name,
      'pace': pace.name, 'stage': stage, 'chosenSong': chosenSong,
      'smartPractice': smartPractice, 'showKeyLabels': showKeyLabels,
      'selectedLetters': selectedLetters.toList(), 'selectedOctaves': selectedOctaves.toList(),
      'songPlayMode': songPlayMode.name, 'songModes': songModes.map((k,v) => MapEntry(k,v.name)), 'speedPercent': speedPercent, 'autoSpeed': autoSpeed,
      'successfulSongStreak': successfulSongStreak, 'orientationMode': orientationMode,
      'reminderEnabled': reminderEnabled, 'reminderHour': reminderHour, 'reminderMinute': reminderMinute,
      'practiceSecondsByDay': practiceSecondsByDay, 'correctByDay': correctByDay, 'attemptsByDay': attemptsByDay,
      'checkRhythm': checkRhythm, 'bpm': bpm,
      'completedLessons': completedLessons.toList(), 'lessonScores': lessonScores,
    });
    try { await storage.invokeMethod<void>('write', {'json': encoded}); await const MethodChannel('piano_note_trainer/widget').invokeMethod<void>('update'); }
    catch (_) { /* Don't block training if storage is unavailable. */ }
  }


  void newQuestion() {
    cancelTimers();
    final choices = pool;
    if (choices.isEmpty && drill != Drill.song) return;
    if (drill == Drill.song) {
      setState(() {
        phrase = currentSong.notes;
        melodyIndex = 0;
        songStartTime = activeSongPlayMode == SongPlayMode.falling || activeSongPlayMode == SongPlayMode.combined
          ? DateTime.now().add(const Duration(milliseconds: 1800)) : null;
        songErrors = 0;
        songErroredIndices.clear();
        rhythmErrors = 0; rhythmSuccess = 0;
        questionSerial++;
        locked = false;
        revealAnswer = false;
        pressedMidi = null;
        secondsLeft = pace.seconds;
        status = 'آهنگ را به ترتیب نت‌ها اجرا کن';
        statusColor = const Color(0xFF53665D);
      });
      beginTimer();
      if (activeSongPlayMode != SongPlayMode.staff) scheduleFallingMiss();
      return;
    }
    final next = <MusicNote>[];
    final noteCount = drill == Drill.melody ? 4 : 1;
    for (var i = 0; i < noteCount; i++) {
      final previous = next.isNotEmpty ? next.last.midi : (phrase.isNotEmpty ? phrase.last.midi : null);
      next.add(choose(choices, previousMidi: previous));
    }
    setState(() {
      phrase = next;
      melodyIndex = 0;
      questionSerial++;
      locked = false;
      revealAnswer = false;
      pressedMidi = null;
      secondsLeft = pace.seconds;
      status = 'نت روی حامل را با پیانو بنواز';
      statusColor = const Color(0xFF53665D);
    });
    beginTimer();
  }

  void beginTimer() {
    ticker?.cancel();
    if (pace.seconds == 0 || (drill == Drill.song && checkRhythm)) return;
    ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || locked) { timer.cancel(); return; }
      if (secondsLeft <= 1) {
        timer.cancel();
        setState(() {
          secondsLeft = 0;
          streak = 0;
          locked = true;
          revealAnswer = true;
          mistakes[target.midi] = (mistakes[target.midi] ?? 0) + 1;
          if (drill == Drill.song) songErrors++;
          status = 'زمان تمام شد! ${target.label(naming)}';
          statusColor = const Color(0xFFC15C4E);
        });
        saveProgress();
        scheduleNext();
      } else {
        setState(() => secondsLeft--);
      }
    });
  }

  void scheduleNext() {
    final serial = questionSerial;
    transition?.cancel();
    transition = Timer(const Duration(milliseconds: 1100), () {
      if (mounted && serial == questionSerial) newQuestion();
    });
  }

  Future<void> playSound(int midi) async {
    lastPracticeInteraction = DateTime.now();
    inactivitySaved = false;
    try { await sound.invokeMethod<void>('startNote', {'midi': midi}); }
    on MissingPluginException { /* Training remains functional without audio. */ }
    catch (_) { /* Audio failure is non-fatal. */ }
  }

  Future<void> stopSound(int midi) async {
    try { await sound.invokeMethod<void>('stopNote', {'midi': midi}); }
    catch (_) { /* Ignore audio teardown errors. */ }
  }

  void onKey(int midi, Duration held) {
    stopSound(midi);
    lastPracticeInteraction = DateTime.now();
    inactivitySaved = false;
    if (locked) return;
    final answeredNote = target;
    final answer = midi == answeredNote.midi;
    final expectedBeats = drill == Drill.song ? currentSong.beats[melodyIndex] : 1.0;
    final expectedMs = expectedBeats * 60000 / effectiveBpm;
    // An absolute floor accommodates Android touch latency and short notes.
    final toleranceMs = max(140.0, expectedMs * 0.35);
    // The first correct note establishes beat zero. Later notes must start
    // near their expected positions on the same beat grid; checking hold time
    // alone would not detect a late or early attack.
    final touchStarted = DateTime.now().subtract(held);
    if (drill == Drill.song && answer && songStartTime == null) {
      songStartTime = touchStarted;
    }
    final expectedStartMs = drill == Drill.song
      ? currentSong.beats.take(melodyIndex).fold<double>(0, (a, b) => a + b) * 60000 / effectiveBpm
      : 0.0;
    final attackErrorMs = songStartTime == null ? 0.0
      : (touchStarted.difference(songStartTime!).inMilliseconds - expectedStartMs).toDouble();
    final timingTolerance = (activeSongPlayMode == SongPlayMode.falling || activeSongPlayMode == SongPlayMode.combined)
      ? max(170.0, expectedMs * .28) : toleranceMs;
    final rhythmicMatch = (held.inMilliseconds - expectedMs).abs() <= toleranceMs
      && (activeSongPlayMode == SongPlayMode.staff || attackErrorMs.abs() <= timingTolerance);
    final fallingMode = drill == Drill.song && activeSongPlayMode != SongPlayMode.staff;
    if (fallingMode && answer && attackErrorMs < -timingTolerance) {
      setState(() { pressedMidi = midi; status = 'کمی صبر کن؛ نت هنوز به خط اجرا نرسیده است'; statusColor = const Color(0xFFC18A35); });
      return;
    }
    if (fallingMode && answer && attackErrorMs > timingTolerance) {
      handleFallingMiss();
      return;
    }
    setState(() {
      attempts++;
      recordAnswer(answer);
      pressedMidi = midi;
      if (answer) {
        correct++;
        final remainingMistakes = (mistakes[answeredNote.midi] ?? 0) - 1;
        mistakes[answeredNote.midi] = max(0, remainingMistakes);
        streak++;
        if (drill == Drill.song && checkRhythm) {
          if (rhythmicMatch) { rhythmSuccess++; } else { rhythmErrors++; }
        }
        ticker?.cancel();
        statusColor = const Color(0xFF218454);
        if (drill != Drill.single && melodyIndex < phrase.length - 1) {
          melodyIndex++;
          status = (drill == Drill.song && checkRhythm && !rhythmicMatch)
            ? '✓ نت درست؛ زمان شروع یا کشش باید ${expectedBeats.toStringAsFixed(1)} ضرب باشد'
            : '✓ درست! ${answeredNote.label(naming)} — نت بعدی';
          secondsLeft = pace.seconds;
          beginTimer();
          if (fallingMode) scheduleFallingMiss();
        } else {
          locked = true;
          status = (drill == Drill.song && checkRhythm && !rhythmicMatch)
              ? '✓ نت درست؛ زمان شروع یا کشش دقیق نبود'
              : '✓ آفرین! ${answeredNote.label(naming)}';
        }
      } else {
        streak = 0;
        mistakes[answeredNote.midi] = (mistakes[answeredNote.midi] ?? 0) + 1;
        if (drill == Drill.song) {
          if (fallingMode) { if (songErroredIndices.add(melodyIndex)) songErrors++; }
          else { songErrors++; }
        }
        status = '✕ درست نبود؛ دوباره امتحان کن';
        statusColor = const Color(0xFFC15C4E);
      }
    });
    saveProgress();
    if (locked && answer) {
      if (drill == Drill.song) {
        finishSong();
      } else { scheduleNext(); }
    }
  }

  void scheduleFallingMiss() {
    fallingMissTimer?.cancel();
    if (songStartTime == null || melodyIndex >= currentSong.notes.length) return;
    final elapsedBeats = currentSong.beats.take(melodyIndex).fold<double>(0, (a, b) => a + b);
    final dueAt = songStartTime!.add(Duration(milliseconds: (elapsedBeats * 60000 / effectiveBpm).round()));
    final deadline = dueAt.add(const Duration(milliseconds: 420));
    final delay = deadline.difference(DateTime.now());
    fallingMissTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted || locked || drill != Drill.song || activeSongPlayMode == SongPlayMode.staff) return;
      handleFallingMiss();
    });
  }

  void handleFallingMiss() {
    if (locked || drill != Drill.song || melodyIndex >= phrase.length) return;
    fallingMissTimer?.cancel();
    final missed = target;
    setState(() {
      attempts++;
      recordAnswer(false);
      if (songErroredIndices.add(melodyIndex)) songErrors++;
      rhythmErrors++;
      mistakes[missed.midi] = (mistakes[missed.midi] ?? 0) + 1;
      streak = 0;
      pressedMidi = null;
      if (melodyIndex < phrase.length - 1) {
        melodyIndex++;
        status = 'نت از دست رفت: ${missed.label(naming)}؛ نت بعدی';
        statusColor = const Color(0xFFC15C4E);
      } else {
        locked = true;
        status = 'پایان آهنگ؛ یک نت از دست رفت';
        statusColor = const Color(0xFFC15C4E);
      }
    });
    saveProgress();
    if (locked) { finishSong(); } else { scheduleFallingMiss(); }
  }

  void finishSong() {
    fallingMissTimer?.cancel();
    ticker?.cancel();
    final pitchScore = (100 * phrase.length / (phrase.length + songErrors)).round();
    final rhythmScore = checkRhythm ? (100 * rhythmSuccess / phrase.length).round() : 100;
    final score = checkRhythm ? ((pitchScore + rhythmScore) / 2).round() : pitchScore;
    bestSongScores[chosenSong] = max(bestSongScores[chosenSong] ?? 0, score);
    completedSongs++;
    if (autoSpeed && score >= 90) {
      successfulSongStreak++;
      if (successfulSongStreak >= 3) {
        speedPercent = (speedPercent + 10).clamp(25, 200).toInt();
        successfulSongStreak = 0;
      }
    } else if (score < 90) { successfulSongStreak = 0; }
    saveProgress();
    final serial = questionSerial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || serial != questionSerial) return;
      showDialog<void>(context: context, barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('آهنگ تمام شد! 🎵'),
          content: Text('آهنگ: ${currentSong.title}\nامتیاز کل: $score از ۱۰۰\nدقت نت: $pitchScore٪\nدقت ریتم: ${checkRhythm ? '$rhythmScore٪' : 'غیرفعال'}\nخطا و نت ازدست‌رفته: $songErrors\nبهترین امتیاز: ${bestSongScores[chosenSong]}'),
          actions: [
            TextButton(onPressed: () { Navigator.pop(dialogContext); newQuestion(); }, child: const Text('دوباره اجرا کن')),
            FilledButton(onPressed: () { Navigator.pop(dialogContext); updateSettings(() => drill = Drill.single); }, child: const Text('تمرین نت‌خوانی')),
          ],
        ),
      );
    });
  }

  void updateSettings(VoidCallback change) {
    setState(change);
    questionBag.clear();
    newQuestion();
    saveProgress();
  }

  void setSongSpeed(int value) {
    final next = value.clamp(25, 200).toInt();
    if (next == speedPercent) return;
    setState(() {
      speedPercent = next;
      if (drill == Drill.song && songStartTime != null && melodyIndex < currentSong.beats.length) {
        final elapsedBeats = currentSong.beats.take(melodyIndex).fold<double>(0, (a, b) => a + b);
        final offset = Duration(milliseconds: (elapsedBeats * 60000 / effectiveBpm).round());
        songStartTime = DateTime.now().add(const Duration(milliseconds: 1200)).subtract(offset);
      }
    });
    if (drill == Drill.song && activeSongPlayMode != SongPlayMode.staff) scheduleFallingMiss();
    saveProgress();
  }

  void resetScores() {
    setState(() { correct = 0; attempts = 0; streak = 0; mistakes.clear(); });
    newQuestion();
    saveProgress();
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); cancelTimers(); activityTimer?.cancel(); super.dispose(); }

  Future<void> openTheory() async {
    lastPracticeInteraction = null;
    cancelTimers();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Directionality(textDirection: TextDirection.rtl,
        child: TheoryPage(
          completed: completedLessons,
          scores: lessonScores,
          onComplete: (id, score) {
            setState(() {
              completedLessons.add(id);
              lessonScores[id] = max(lessonScores[id] ?? 0, score);
            });
            saveProgress();
          },
        )),
    ));
    if (mounted) newQuestion();
  }

  Future<void> openSettings() async {
    lastPracticeInteraction = null;
    cancelTimers();
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refreshSheet) {
          void change(VoidCallback fn) {
            updateSettings(fn);
            refreshSheet(() {});
          }
          return Directionality(textDirection: TextDirection.rtl,
            child: SafeArea(child: Padding(
              padding: EdgeInsets.fromLTRB(18, 6, 18, MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
              child: SingleChildScrollView(child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min, children: [
                const Text('تنظیمات تمرین', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                const Text('نام نت‌ها', style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(spacing: 6, children: [
                  ChoiceChip(label: const Text('دو، ر، می…'), selected: naming == NoteNames.persian,
                    onSelected: (_) => change(() => naming = NoteNames.persian)),
                  ChoiceChip(label: const Text('C, D, E…'), selected: naming == NoteNames.english,
                    onSelected: (_) => change(() => naming = NoteNames.english)),
                  ChoiceChip(label: const Text('هر دو'), selected: naming == NoteNames.both,
                    onSelected: (_) => change(() => naming = NoteNames.both)),
                ]),
                const SizedBox(height: 8),
                const Text('اکتاوهای مورد تمرین', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('اکتاو ۴ (دو وسط پیانو) پیش‌فرض است؛ هر تعداد اکتاو را می‌توانی انتخاب کنی.', style: TextStyle(fontSize: 12)),
                Wrap(spacing: 6, children: [
                  for (var octave = 2; octave <= 6; octave++)
                    FilterChip(label: Text('اکتاو $octave'), selected: selectedOctaves.contains(octave),
                      onSelected: (v) { if (!v && selectedOctaves.length == 1) return; change(() { if (v) selectedOctaves.add(octave); else selectedOctaves.remove(octave); questionBag.clear(); }); }),
                ]),
                const SizedBox(height: 8),
                const Text('نت‌های مورد تمرین', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('انتخاب نت‌ها در تمام اکتاوهای انتخاب‌شده اعمال می‌شود.', style: TextStyle(fontSize: 12)),
                Wrap(spacing: 5, runSpacing: 0, children: [
                  for (var i = 0; i < noteLetters.length; i++)
                    FilterChip(label: Text('${persianLetters[i]} / ${noteLetters[i]}'),
                      selected: selectedLetters.contains(noteLetters[i]),
                      onSelected: (v) {
                        if (!v && selectedLetters.length == 1) return;
                        change(() { if (v) { selectedLetters.add(noteLetters[i]); }
                          else { selectedLetters.remove(noteLetters[i]); } });
                      }),
                ]),
                const SizedBox(height: 8),
                const Text('کلید موسیقی', style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(spacing: 7, children: [
                  ChoiceChip(label: const Text('کلید سل'), selected: clef == Clef.treble,
                    onSelected: (_) => change(() => clef = Clef.treble)),
                  ChoiceChip(label: const Text('کلید فا'), selected: clef == Clef.bass,
                    onSelected: (_) => change(() => clef = Clef.bass)),
                ]),
                const SizedBox(height: 8),
                const Text('نوع تمرین', style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(spacing: 7, children: [
                  ChoiceChip(label: const Text('تک‌نت'), selected: drill == Drill.single,
                    onSelected: (_) => change(() => drill = Drill.single)),
                  ChoiceChip(label: const Text('ملودی ۴ نتی'), selected: drill == Drill.melody,
                    onSelected: (_) => change(() => drill = Drill.melody)),
                  ChoiceChip(label: const Text('آهنگ واقعی'), selected: drill == Drill.song,
                    onSelected: (_) => change(() => drill = Drill.song)),
                ]),
                if (drill == Drill.song) ...[
                  const Text('انتخاب آهنگ — نت‌ها با کلید سل نمایش داده می‌شوند',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final song in practiceSongs)
                    RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero,
                      title: Text(song.title),
                      subtitle: Text('${song.author} • ${song.pitchNames.length} نت • رکورد: ${bestSongScores[song.id] ?? 0}'),
                      value: song.id, groupValue: chosenSong,
                      onChanged: (v) { if (v != null) change(() => chosenSong = v); }),
                ],
                if (drill == Drill.song) ...[
                  const Text('روش اجرای آهنگ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Wrap(spacing: 6, children: [
                    ChoiceChip(label: const Text('نت روی حامل'), selected: activeSongPlayMode == SongPlayMode.staff, onSelected: (_) => change(() => songModes[chosenSong] = SongPlayMode.staff)),
                    ChoiceChip(label: const Text('نت‌های سقوط‌کننده'), selected: activeSongPlayMode == SongPlayMode.falling, onSelected: (_) => change(() => songModes[chosenSong] = SongPlayMode.falling)),
                    ChoiceChip(label: const Text('حالت ترکیبی'), selected: activeSongPlayMode == SongPlayMode.combined, onSelected: (_) => change(() => songModes[chosenSong] = SongPlayMode.combined)),
                  ]),
                  Text('سرعت آهنگ: $speedPercent٪ • تمپوی مؤثر: $effectiveBpm BPM', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(min: 25, max: 200, divisions: 35, value: speedPercent.toDouble(), label: '$speedPercent٪', onChanged: (v) { setSongSpeed(v.round()); refreshSheet(() {}); }),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('افزایش تدریجی سرعت پس از سه اجرای موفق'), value: autoSpeed, onChanged: (v) => change(() => autoSpeed = v)),
                  SwitchListTile(contentPadding: EdgeInsets.zero,
                    title: const Text('بررسی کشش و زمان نگه‌داشتن کلاویه'),
                    subtitle: const Text('از لحظه لمس تا رها کردن کلید اندازه‌گیری می‌شود.'),
                    value: checkRhythm, onChanged: (v) => change(() => checkRhythm = v)),
                  Text('تمپو: $bpm ضرب در دقیقه (BPM)', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(min: 40, max: 160, divisions: 24, value: bpm.toDouble(),
                    label: '$bpm', onChanged: (v) => change(() => bpm = v.round())),
                ],
                SwitchListTile(contentPadding: EdgeInsets.zero,
                  title: const Text('تکرار هوشمند نت‌های اشتباه'),
                  value: smartPractice, onChanged: (v) => change(() => smartPractice = v)),
                SwitchListTile(contentPadding: EdgeInsets.zero,
                  title: const Text('نمایش نام نت روی کلاویه‌ها'),
                  value: showKeyLabels, onChanged: (v) => change(() => showKeyLabels = v)),
                const Divider(),
                const Text('جهت صفحه', style: TextStyle(fontWeight: FontWeight.bold)),
                Wrap(spacing: 6, children: [
                  ChoiceChip(label: const Text('خودکار'), selected: orientationMode == 'auto', onSelected: (_) { setOrientation('auto'); refreshSheet(() {}); }),
                  ChoiceChip(label: const Text('عمودی'), selected: orientationMode == 'portrait', onSelected: (_) { setOrientation('portrait'); refreshSheet(() {}); }),
                  ChoiceChip(label: const Text('افقی'), selected: orientationMode == 'landscape', onSelected: (_) { setOrientation('landscape'); refreshSheet(() {}); }),
                ]),
                const Divider(),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('یادآور روزانه تمرین'), subtitle: Text('ساعت: ${reminderHour.toString().padLeft(2,"0")}:${reminderMinute.toString().padLeft(2,"0")}'), value: reminderEnabled, onChanged: (v) { configureReminder(v, reminderHour, reminderMinute); refreshSheet(() {}); }),
                Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(icon: const Icon(Icons.schedule), label: const Text('انتخاب ساعت یادآوری'), onPressed: () async { final picked = await showTimePicker(context: sheetContext, initialTime: TimeOfDay(hour: reminderHour, minute: reminderMinute)); if (picked != null) { change(() { reminderHour = picked.hour; reminderMinute = picked.minute; }); if (reminderEnabled) configureReminder(true, picked.hour, picked.minute); } })),
                const SizedBox(height: 8),
                FilledButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('بازگشت به تمرین')),
              ]))),
            ));
        },
      ),
    );
    if (mounted) newQuestion();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
      final landscape = constraints.maxWidth > constraints.maxHeight;
      final compact = constraints.maxHeight < 700;
      final header = Padding(padding: EdgeInsets.fromLTRB(landscape ? 8 : 14, landscape ? 2 : 10, landscape ? 8 : 14, 4), child: Row(children: [
        const Icon(Icons.piano, color: Color(0xFF2B6950), size: 27),
        const SizedBox(width: 6),
        const Expanded(child: Text('نت‌خوان پیانو', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        IconButton(visualDensity: VisualDensity.compact, tooltip: 'گزارش پیشرفت', onPressed: openDashboard, icon: const Icon(Icons.insights)),
        IconButton(visualDensity: VisualDensity.compact, tooltip: 'تئوری موسیقی', onPressed: openTheory, icon: const Icon(Icons.menu_book_outlined)),
        IconButton(visualDensity: VisualDensity.compact, tooltip: 'چرخش صفحه', onPressed: () => setOrientation(orientationMode == 'landscape' ? 'portrait' : 'landscape'), icon: const Icon(Icons.screen_rotation)),
        IconButton(visualDensity: VisualDensity.compact, tooltip: 'تنظیمات', onPressed: openSettings, icon: const Icon(Icons.tune)),
      ]));
      final stats = Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [
        _stat('درست', '$correct'), const SizedBox(width: 5),
        _stat('پشت‌سرهم', '$streak'), const SizedBox(width: 5),
        _stat('دقت', attempts == 0 ? '—' : '${(correct * 100 / attempts).round()}٪'),
      ]));
      final paceControl = Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [
        const Text('سرعت:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(width: 6),
        Expanded(child: SizedBox(height: 34, child: ListView(scrollDirection: Axis.horizontal, reverse: true,
          children: [for (final p in Pace.values) Padding(padding: const EdgeInsets.only(left: 4),
            child: ChoiceChip(label: Text(p.title, style: const TextStyle(fontSize: 11)), selected: pace == p,
              onSelected: (_) => updateSettings(() => pace = p)))],
        ))),
      ]));
      final songSpeedControl = drill == Drill.song ? Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [
        const Text('تمپو', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        Expanded(child: Slider(min: 25, max: 200, divisions: 35, value: speedPercent.toDouble(), onChanged: (v) => setSongSpeed(v.round()))),
        SizedBox(width: 40, child: Text('$speedPercent٪', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
      ])) : const SizedBox.shrink();
      final practiceCard = Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8EAE3))),
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 0), child: Row(children: [
            Expanded(child: Text(drill == Drill.single ? 'این چه نتی است؟' : drill == Drill.song ? '${currentSong.title}: نت ${melodyIndex + 1} از ${phrase.length}' : 'ملودی: نت ${melodyIndex + 1} از ${phrase.length}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
            if (pace.seconds != 0) Text('$secondsLeft ثانیه', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ])),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child:
            drill == Drill.song && activeSongPlayMode == SongPlayMode.falling
              ? FallingNotesBoard(song: currentSong, activeIndex: melodyIndex, bpm: effectiveBpm, startAt: songStartTime, speedPercent: speedPercent, naming: naming)
              : drill == Drill.song && activeSongPlayMode == SongPlayMode.combined
                ? Column(children: [
                    Expanded(child: FallingNotesBoard(song: currentSong, activeIndex: melodyIndex, bpm: effectiveBpm, startAt: songStartTime, speedPercent: speedPercent, naming: naming)),
                    Expanded(child: CustomPaint(painter: StaffPainter(notes: phrase.skip((melodyIndex ~/ 4) * 4).take(4).toList(), activeIndex: melodyIndex % 4, clef: effectiveClef, beats: currentSong.beats.skip((melodyIndex ~/ 4) * 4).take(4).toList(), success: locked && pressedMidi == target.midi), child: const SizedBox.expand())),
                  ])
                : CustomPaint(painter: StaffPainter(notes: drill == Drill.song ? phrase.skip((melodyIndex ~/ 4) * 4).take(4).toList() : phrase, activeIndex: drill == Drill.song ? melodyIndex % 4 : melodyIndex, clef: effectiveClef, beats: drill == Drill.song ? currentSong.beats.skip((melodyIndex ~/ 4) * 4).take(4).toList() : null, success: locked && pressedMidi == target.midi), child: const SizedBox.expand())
          )),
          if (drill == Drill.song) Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Text('♩ = $effectiveBpm BPM • سرعت $speedPercent٪ • کشش ${currentSong.beats[melodyIndex]} ضرب', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(status, textAlign: TextAlign.center, style: TextStyle(fontSize: compact ? 11 : 14, fontWeight: FontWeight.w800, color: statusColor))),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton.icon(onPressed: () => setState(() => revealAnswer = !revealAnswer), icon: Icon(revealAnswer ? Icons.visibility_off : Icons.visibility, size: 16), label: Text(revealAnswer ? 'پنهان کردن پاسخ' : 'نمایش پاسخ')),
            if (revealAnswer) Text(target.label(naming), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ]),
      );
      final footer = Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Row(children: [
        Text(drill == Drill.song ? 'آهنگ • کلید سل' : "${clef == Clef.treble ? 'کلید سل' : 'کلید فا'} • اکتاو $selectedOctaveLabel", style: const TextStyle(fontSize: 11)),
        const Spacer(), TextButton(onPressed: newQuestion, child: const Text('نت بعدی')),
      ]));
      final keyboard = PianoKeyboard(startOctave: effectiveOctave, octaveCount: effectiveOctaveCount, pressedMidi: pressedMidi, naming: naming, showLabels: showKeyLabels, onPressed: onKey, onTouchDown: playSound, onTouchCancel: stopSound);
      if (landscape) {
        return Row(children: [
          Expanded(flex: 6, child: Column(children: [header, stats, Expanded(child: practiceCard), footer])),
          Expanded(flex: 5, child: Column(children: [paceControl, songSpeedControl, Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(3, 3, 8, 8), child: keyboard))])),
        ]);
      }
      return Column(children: [header, stats, const SizedBox(height: 5), paceControl, songSpeedControl, Expanded(child: practiceCard), footer,
        SizedBox(height: compact ? 112 : 174, child: keyboard), const SizedBox(height: 5)]);
    })),
  );

  Widget _stat(String title, String value) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
    decoration: BoxDecoration(color: const Color(0xFFE9EEE7), borderRadius: BorderRadius.circular(10)),
    child: Column(children: [
      Text(title, style: const TextStyle(fontSize: 10, color: Color(0xFF53665D))),
      Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
    ]),
  ));
}

class StaffPainter extends CustomPainter {
  StaffPainter({required this.notes, required this.activeIndex,
    required this.clef, required this.success, this.beats});
  final List<MusicNote> notes;
  final int activeIndex;
  final Clef clef;
  final bool success;
  final List<double>? beats;

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final positions = notes.map((n) => staffPosition(n, clef)).toList();
    final lowest = positions.reduce(min);
    final highest = positions.reduce(max);
    final extraBottom = max(0, -lowest) * .5;
    final extraTop = max(0, highest - 8) * .5;
    final gap = min(21.0, min(w / 18, h / (6.0 + extraTop + extraBottom)));
    final bottomY = h * .5 + (2.0 + (extraTop - extraBottom) / 2) * gap;
    final topY = bottomY - 4 * gap;
    final ink = Paint()..color = const Color(0xFF273C36)
      ..strokeWidth = 1.55..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final y = topY + i * gap;
      canvas.drawLine(Offset(w * .07, y), Offset(w * .94, y), ink);
    }
    final clefSymbol = clef == Clef.treble ? '𝄞' : '𝄢';
    final clefPainter = TextPainter(
      text: TextSpan(text: clefSymbol, style: TextStyle(
        fontSize: gap * (clef == Clef.treble ? 4.6 : 3.5),
        color: const Color(0xFF273C36),
        fontFamilyFallback: const ['Noto Music', 'Noto Sans Symbols 2', 'DejaVu Sans'])),
      textDirection: TextDirection.ltr,
    )..layout();
    clefPainter.paint(canvas, Offset(w * .08, topY - gap * (clef == Clef.treble ? 1.8 : .95)));

    for (var i = 0; i < notes.length; i++) {
      final x = notes.length == 1 ? w * .53 : w * (.34 + i * .16);
      final step = positions[i];
      final y = bottomY - step * gap / 2;
      final ledger = Paint()..color = const Color(0xFF273C36)..strokeWidth = 1.6;
      for (var s = -2; s >= step; s -= 2) {
        canvas.drawLine(Offset(x - gap, bottomY - s * gap / 2),
          Offset(x + gap, bottomY - s * gap / 2), ledger);
      }
      for (var s = 10; s <= step; s += 2) {
        canvas.drawLine(Offset(x - gap, bottomY - s * gap / 2),
          Offset(x + gap, bottomY - s * gap / 2), ledger);
      }
      final color = i == activeIndex ?
        (success ? const Color(0xFF218454) : const Color(0xFF263B35)) :
        (i < activeIndex ? const Color(0xFF218454) : const Color(0xFF9DA7A2));
      final pen = Paint()..color = color;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(-.22);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero,
        width: gap * 1.4, height: gap * .95), pen);
      if (beats != null && i < beats!.length && beats![i] >= 2) {
        final inner = Paint()..color = Colors.white;
        canvas.drawOval(Rect.fromCenter(center: Offset.zero,
          width: gap * 0.85, height: gap * .46), inner);
      }
      canvas.restore();
      if (beats != null && i < beats!.length) {
        final rhythmText = beats![i] == 2 ? '۲ ضرب' : beats![i] == 4 ? '۴ ضرب' : '۱ ضرب';
        final rhythmPainter = TextPainter(
          text: TextSpan(text: rhythmText, style: TextStyle(color: color, fontSize: 10)),
          textDirection: TextDirection.rtl,
        )..layout();
        rhythmPainter.paint(canvas, Offset(x - rhythmPainter.width / 2, h - 18));
      }
      final stem = Paint()..color = color..strokeWidth = 2.2;
      if (beats != null && i < beats!.length && beats![i] >= 4) continue;
      if (step < 5) {
        canvas.drawLine(Offset(x + gap * .65, y), Offset(x + gap * .65, y - gap * 3), stem);
      } else {
        canvas.drawLine(Offset(x - gap * .65, y), Offset(x - gap * .65, y + gap * 3), stem);
      }
    }
  }

  @override
  bool shouldRepaint(covariant StaffPainter old) =>
    old.notes != notes || old.activeIndex != activeIndex ||
    old.clef != clef || old.success != success || old.beats != beats;
}

class FallingNotesBoard extends StatefulWidget {
  const FallingNotesBoard({super.key, required this.song, required this.activeIndex, required this.bpm, required this.startAt, required this.speedPercent, required this.naming});
  final PracticeSong song;
  final int activeIndex;
  final int bpm;
  final DateTime? startAt;
  final int speedPercent;
  final NoteNames naming;
  @override
  State<FallingNotesBoard> createState() => _FallingNotesBoardState();
}
class _FallingNotesBoardState extends State<FallingNotesBoard> {
  Timer? repaintTimer;
  @override
  void initState() { super.initState(); repaintTimer = Timer.periodic(const Duration(milliseconds: 33), (_) { if (mounted) setState(() {}); }); }
  @override
  void didUpdateWidget(covariant FallingNotesBoard oldWidget) { super.didUpdateWidget(oldWidget); }
  @override
  void dispose() { repaintTimer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: FallingNotesPainter(song: widget.song, activeIndex: widget.activeIndex, bpm: widget.bpm, startAt: widget.startAt, speedPercent: widget.speedPercent, naming: widget.naming),
    child: const SizedBox.expand());
}
class FallingNotesPainter extends CustomPainter {
  FallingNotesPainter({required this.song, required this.activeIndex, required this.bpm, required this.startAt, required this.speedPercent, required this.naming});
  final PracticeSong song; final int activeIndex; final int bpm; final DateTime? startAt; final int speedPercent; final NoteNames naming;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final laneWidth = size.width / 7;
    final hitY = size.height - 26;
    final lanePaint = Paint()..color = const Color(0xFFE7ECE7)..strokeWidth = 1;
    for (var i=0;i<=7;i++) canvas.drawLine(Offset(i*laneWidth,0),Offset(i*laneWidth,size.height),lanePaint);
    canvas.drawLine(Offset(0,hitY),Offset(size.width,hitY),Paint()..color=const Color(0xFF258454)..strokeWidth=3);
    final labelPainter = TextPainter(textDirection: TextDirection.rtl);
    for (var i=0;i<7;i++) {
      final laneLabel = naming == NoteNames.persian ? persianLetters[i] : naming == NoteNames.english ? noteLetters[i] : '${persianLetters[i]}/${noteLetters[i]}';
      labelPainter.text=TextSpan(text: laneLabel,style: const TextStyle(color: Color(0xFF8A9690),fontSize:9));
      labelPainter.layout(); labelPainter.paint(canvas,Offset(i*laneWidth+(laneWidth-labelPainter.width)/2, size.height-15));
    }
    final start = startAt;
    if (start == null) return;
    final now = DateTime.now();
    final msPerBeat = 60000.0 / max(1,bpm);
    final elapsed = now.difference(start).inMilliseconds.toDouble();
    final pxPerMs = (size.height - 40) / 2600.0;
    for (var i=activeIndex;i<min(song.notes.length,activeIndex+12);i++) {
      final priorBeats = song.beats.take(i).fold<double>(0,(a,b)=>a+b);
      final dueMs = priorBeats*msPerBeat;
      final y = hitY - (dueMs-elapsed)*pxPerMs;
      final note = song.notes[i];
      final lane = noteLetters.indexOf(note.letter);
      if (y < -30 || y > size.height+30) continue;
      final barHeight = max(18.0, song.beats[i] * msPerBeat * pxPerMs);
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH((lane+.5)*laneWidth-laneWidth*.34, y-barHeight, laneWidth*.68, barHeight),const Radius.circular(8));
      final paint = Paint()..color = i==activeIndex ? const Color(0xFF32865D) : const Color(0xFF9CB8A7);
      canvas.drawRRect(rect,paint);
      final noteLabel = naming == NoteNames.persian ? note.persian : naming == NoteNames.english ? note.letter : '${note.persian}/${note.letter}';
      final tp=TextPainter(text:TextSpan(text:noteLabel,style:TextStyle(color:Colors.white,fontWeight:FontWeight.bold,fontSize:naming == NoteNames.both ? 9 : 12)),textDirection:TextDirection.ltr)..layout();
      tp.paint(canvas,Offset((lane+.5)*laneWidth-tp.width/2,y-tp.height/2));
    }
  }
  @override
  bool shouldRepaint(covariant FallingNotesPainter old) => old.activeIndex!=activeIndex || old.startAt!=startAt || old.bpm!=bpm || old.speedPercent!=speedPercent || old.naming!=naming || old.song!=song;
}

class PianoKeyboard extends StatelessWidget {
  const PianoKeyboard({super.key, required this.startOctave, required this.octaveCount,
    required this.pressedMidi, required this.naming,
    required this.showLabels, required this.onPressed, required this.onTouchDown, required this.onTouchCancel});
  final int startOctave;
  final int octaveCount;
  final int? pressedMidi;
  final NoteNames naming;
  final bool showLabels;
  final void Function(int, Duration) onPressed;
  final ValueChanged<int> onTouchDown;
  final ValueChanged<int> onTouchCancel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final base = 12 * (startOctave + 1);
    final whites = <int>[
      for (var octave = 0; octave < octaveCount; octave++)
        for (final semitone in noteSemitones) base + 12 * octave + semitone,
      base + 12 * octaveCount,
    ];
    const blackKeyIndices = [0, 1, 3, 4, 5];
    const blackKeySemitones = [1, 3, 6, 8, 10];
    // A fixed minimum key width makes the keyboard horizontally scrollable on phones.
    final whiteCount = octaveCount * 7 + 1;
    final width = max(bounds.maxWidth, whiteCount * 38.0);
    final keyWidth = width / whiteCount;
    return SingleChildScrollView(scrollDirection: Axis.horizontal,
      child: SizedBox(width: width, height: bounds.maxHeight,
        child: Directionality(textDirection: TextDirection.ltr, child: Stack(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final midi in whites) Expanded(child: NoteKeyTouch(midi: midi, onRelease: onPressed, onDown: onTouchDown, onCancel: onTouchCancel, child: Container(
                margin: const EdgeInsets.symmetric(horizontal: .6),
                decoration: BoxDecoration(
                  color: pressedMidi == midi ? const Color(0xFFB9E5C5) : Colors.white,
                  border: Border.all(color: const Color(0xFF84978E)),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                ),
                alignment: Alignment.bottomCenter,
                padding: const EdgeInsets.only(bottom: 10),
                child: showLabels ? Text(_keyLabel(midi),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)) : null,
              ),
            )),
          ]),
          for (var octave = 0; octave < octaveCount; octave++)
            for (var b = 0; b < blackKeyIndices.length; b++)
            Positioned(left: (octave * 7 + blackKeyIndices[b] + 1) * keyWidth - keyWidth * .31,
              top: 0, width: keyWidth * .62, height: bounds.maxHeight * .59,
              child: NoteKeyTouch(midi: base + octave * 12 + blackKeySemitones[b],
                onRelease: onPressed, onDown: onTouchDown, onCancel: onTouchCancel, child: Container(decoration: BoxDecoration(
                  color: pressedMidi == base + octave * 12 + blackKeySemitones[b]
                    ? const Color(0xFF47836A) : const Color(0xFF263630),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(5)),
                )),
              ),
            ),
        ]))),
    );
  });

  String _keyLabel(int midi) {
    final i = noteSemitones.indexOf(midi % 12);
    if (i < 0) return '';
    final name = switch (naming) {
      NoteNames.persian => persianLetters[i],
      NoteNames.english => noteLetters[i],
      NoteNames.both => noteLetters[i],
    };
    return '$name${midi ~/ 12 - 1}';
  }
}

/// Measures actual finger-hold duration rather than only counting key taps.
/// Does not synthesize duration from a fixed timer; rhythm scoring uses input.
class NoteKeyTouch extends StatefulWidget {
  const NoteKeyTouch({super.key, required this.midi, required this.onRelease, required this.onDown, required this.onCancel, required this.child});
  final int midi;
  final void Function(int, Duration) onRelease;
  final ValueChanged<int> onDown;
  final ValueChanged<int> onCancel;
  final Widget child;
  @override
  State<NoteKeyTouch> createState() => _NoteKeyTouchState();
}
class _NoteKeyTouchState extends State<NoteKeyTouch> {
  DateTime? started;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) { started = DateTime.now(); widget.onDown(widget.midi); },
    onTapUp: (_) {
      final start = started;
      started = null;
      if (start != null) widget.onRelease(widget.midi, DateTime.now().difference(start));
    },
    onTapCancel: () { started = null; widget.onCancel(widget.midi); },
    child: widget.child,
  );
}

class ProgressDashboard extends StatelessWidget {
  const ProgressDashboard({super.key, required this.secondsByDay, required this.correctByDay, required this.attemptsByDay});
  final Map<String, int> secondsByDay, correctByDay, attemptsByDay;
  String keyFor(DateTime d) => '${d.year.toString().padLeft(4,"0")}-${d.month.toString().padLeft(2,"0")}-${d.day.toString().padLeft(2,"0")}';
  int secondsFor(DateTime d) => secondsByDay[keyFor(d)] ?? 0;
  String durationLabel(int seconds) => seconds >= 3600 ? '${seconds ~/ 3600} ساعت و ${(seconds % 3600) ~/ 60} دقیقه' : '${seconds ~/ 60} دقیقه';
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todaySeconds = secondsFor(now);
    final weekDays = List.generate(7, (i) => DateTime(now.year, now.month, now.day).subtract(Duration(days: 6-i)));
    final weekSeconds = weekDays.fold<int>(0, (sum, d) => sum + secondsFor(d));
    final monthDays = List.generate(now.day, (i) => DateTime(now.year, now.month, i+1));
    final monthSeconds = monthDays.fold<int>(0, (sum, d) => sum + secondsFor(d));
    final activeDays = monthDays.where((d) => secondsFor(d) >= 60).length;
    final todayKey = keyFor(now);
    final todayAttempts = attemptsByDay[todayKey] ?? 0;
    final todayCorrect = correctByDay[todayKey] ?? 0;
    final accuracy = todayAttempts == 0 ? 0 : (100 * todayCorrect / todayAttempts).round();
    return Scaffold(appBar: AppBar(title: const Text('گزارش پیشرفت تمرین')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _summaryCard('امروز', durationLabel(todaySeconds), '$todayCorrect نت صحیح از $todayAttempts تلاش • دقت $accuracy٪', Icons.today),
        const SizedBox(height: 12),
        _summaryCard('این هفته', durationLabel(weekSeconds), '${weekDays.where((d) => secondsFor(d) >= 60).length} روز تمرین در ۷ روز اخیر', Icons.date_range),
        const SizedBox(height: 12),
        _summaryCard('این ماه', durationLabel(monthSeconds), '$activeDays روز فعال در ماه جاری', Icons.calendar_month),
        const SizedBox(height: 18),
        const Text('فعالیت هفت روز اخیر', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [for (final d in weekDays) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Column(children: [
          Text('${secondsFor(d) ~/ 60}', style: const TextStyle(fontSize: 10)),
          Container(height: max(5.0, min(100.0, secondsFor(d) / max(1, weekSeconds) * 100)).toDouble(), decoration: BoxDecoration(color: secondsFor(d) >= 60 ? const Color(0xFF39835F) : const Color(0xFFD8DED8), borderRadius: BorderRadius.circular(6))),
          const SizedBox(height: 5), Text(['ی','د','س','چ','پ','ج','ش'][d.weekday % 7], style: const TextStyle(fontSize: 11)),
        ])))]),
      ]));
  }
  Widget _summaryCard(String title, String value, String detail, IconData icon) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
    CircleAvatar(child: Icon(icon)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), Text(detail, style: const TextStyle(fontSize: 12))])),
  ])));
}

class TheoryLesson {
  const TheoryLesson(this.id, this.title, this.content, this.question, this.answers, this.correct, this.explanation);
  final String id, title, content, question, explanation;
  final List<String> answers;
  final int correct;
}
const theoryLessons = <TheoryLesson>[
  TheoryLesson('staff', '۱. خط حامل و کلیدها',
    'خط حامل از پنج خط و چهار فاصله تشکیل شده است. جای عمودی نت، زیرایی آن را مشخص می‌کند. در کلید سل، خط پایین «می۴ / E4» است و خطوط از پایین: می، سل، سی، ر، فا. در کلید فا، خط پایین «سل۲ / G2» است و خطوط: سل، سی، ر، فا، لا. خط‌های کمکی بیرون حامل برای نت‌های بالاتر یا پایین‌تر استفاده می‌شوند.',
    'خط پایین در کلید سل چه نتی است؟', ['دو۴', 'می۴', 'سل۴'], 1,
    'در کلید سل، پایین‌ترین خط حامل می۴ (E4) است.'),
  TheoryLesson('names', '۲. نام نت‌ها و اکتاو',
    'هفت نام طبیعی موسیقی عبارت‌اند از: دو=C، ر=D، می=E، فا=F، سل=G، لا=A و سی=B. پس از سی، دوباره دو در اکتاو بالاتر تکرار می‌شود. دو وسط پیانو C4 و دارای شماره MIDI برابر ۶۰ است. حرکت به سمت راست روی پیانو معمولاً صدا را زیرتر می‌کند.',
    'کدام حرف انگلیسی برای «سل» است؟', ['G', 'F', 'A'], 0,
    'سل معادل G است.'),
  TheoryLesson('rhythm', '۳. کشش نت‌ها و سکوت',
    'در میزان ساده با واحد ضربِ سیاه: نت گرد ۴ ضرب، سفید ۲ ضرب، سیاه ۱ ضرب و چنگ نیم ضرب ارزش دارد. سکوت‌ها نیز با همین ارزش‌ها وجود دارند. برای اجرای یک نت سفید در تمپوی ۶۰ BPM باید کلاویه را تقریباً ۲ ثانیه نگه داشت.',
    'در تمپوی ۶۰، یک نت سفید چقدر طول می‌کشد؟', ['۱ ثانیه', '۲ ثانیه', 'نیم ثانیه'], 1,
    'هر ضرب یک ثانیه است؛ سفید دو ضرب طول می‌کشد.'),
  TheoryLesson('meter', '۴. میزان و کسر میزان',
    'خط میزان، موسیقی را به میزان‌های منظم تقسیم می‌کند. در ۴/۴ هر میزان چهار ضربِ سیاه دارد؛ در ۳/۴ سه ضرب و در ۲/۴ دو ضرب. عدد بالایی شمار ضرب‌ها را می‌دهد و عدد پایینی نوع ارزش مبنای ضرب را مشخص می‌کند. تمپو (BPM) تعداد ضرب در دقیقه است.',
    'میزان ۳/۴ معمولاً چند ضرب سیاه دارد؟', ['۳', '۴', '۲'], 0,
    'کسر میزان ۳/۴ سه ضرب سیاه در هر میزان دارد.'),
  TheoryLesson('accidentals', '۵. دیز، بمل و بکار',
    'دیز (♯) صدا را یک نیم‌پرده بالا می‌برد و بمل (♭) یک نیم‌پرده پایین می‌آورد. بکار (♮) تغییر قبلی را خنثی می‌کند. فاصله می تا فا و سی تا دو، نیم‌پرده است؛ بیشتر نت‌های طبیعیِ مجاور یک پرده فاصله دارند. کلیدهای سیاه پیانو اغلب برای نت‌های تغییریافته استفاده می‌شوند.',
    'دیز چه تغییری ایجاد می‌کند؟', ['یک نیم‌پرده بالاتر', 'یک پرده پایین‌تر', 'بدون تغییر'], 0,
    'دیز زیرایی نت را نیم‌پرده افزایش می‌دهد.'),
  TheoryLesson('intervals', '۶. فاصله و گام',
    'فاصله، اختلاف زیرایی بین دو نت است. از دو تا ر فاصله دوم و از دو تا می فاصله سوم نام دارد. گام دو ماژور: C D E F G A B C است و هیچ دیز یا بملی ندارد. الگوی پرده‌ها در گام ماژور: پرده، پرده، نیم‌پرده، پرده، پرده، پرده، نیم‌پرده است.',
    'گام دو ماژور چند دیز یا بمل دارد؟', ['یکی', 'هیچ‌کدام', 'دو تا'], 1,
    'گام دو ماژور فقط از کلاویه‌های سفید تشکیل می‌شود.'),
  TheoryLesson('technique', '۷. وضعیت دست و انگشت‌گذاری',
    'مچ را راحت و هم‌سطح دست نگه دارید. شماره انگشت‌ها در هر دست از شست ۱ تا انگشت کوچک ۵ است. از فشار اضافی روی کلاویه‌ها خودداری کنید. با سرعت آزاد شروع کنید و تنها وقتی جای نت‌ها را دقیق شناختید سرعت را بالا ببرید.',
    'در انگشت‌گذاری پیانو شماره شست چیست؟', ['۱', '۳', '۵'], 0,
    'شست در هر دو دست انگشت شماره ۱ است.'),
  TheoryLesson('practice', '۸. روش تمرین نت‌خوانی',
    'ابتدا نت را روی حامل پیدا کنید، سپس نام آن را بگویید و کلاویه مناسب را بزنید. نت‌های اشتباه را بیشتر تکرار کنید. برای تمرین کشش، تمپوی ۶۰ یا ۸۰ BPM انتخاب کنید؛ انگشت را در آغاز نت پایین ببرید و بعد از زمان مشخص رها کنید. دقت مهم‌تر از سرعت است.',
    'برای یادگیری نت جدید بهتر است ابتدا چه کنید؟', ['فقط تند بزنید', 'نام و محل نت را تشخیص دهید', 'همه نت‌ها را هم‌زمان بزنید'], 1,
    'ابتدا تشخیص صحیح نت و سپس افزایش تدریجی سرعت.'),
];

class TheoryPage extends StatelessWidget {
  const TheoryPage({super.key, required this.completed, required this.scores, required this.onComplete});
  final Set<String> completed;
  final Map<String,int> scores;
  final void Function(String,int) onComplete;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('آموزش تئوری موسیقی')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Text('درس‌های کوتاه • مطالعه آفلاین • آزمون هر درس',
        style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text('درس‌های خوانده‌شده: ${completed.length} از ${theoryLessons.length}'),
      const SizedBox(height: 12),
      for (final lesson in theoryLessons) Card(child: ListTile(
        title: Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(completed.contains(lesson.id) ? '✓ گذرانده‌شده • بهترین نمره: ${scores[lesson.id] ?? 0}' : 'برای مطالعه و آزمون لمس کنید'),
        trailing: Icon(completed.contains(lesson.id) ? Icons.check_circle : Icons.chevron_left,
          color: completed.contains(lesson.id) ? Colors.green : null),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
          Directionality(textDirection: TextDirection.rtl,
            child: LessonDetail(lesson: lesson, onPassed: (score) => onComplete(lesson.id,score))))),
      )),
    ]),
  );
}

class LessonDetail extends StatefulWidget {
  const LessonDetail({super.key, required this.lesson, required this.onPassed});
  final TheoryLesson lesson;
  final ValueChanged<int> onPassed;
  @override
  State<LessonDetail> createState() => _LessonDetailState();
}
class _LessonDetailState extends State<LessonDetail> {
  int? selection;
  bool submitted = false;
  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    return Scaffold(appBar: AppBar(title: Text(lesson.title)),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Text(lesson.content, style: const TextStyle(fontSize: 17, height: 1.9)),
        const Divider(height: 32),
        Text('آزمون کوتاه', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(lesson.question, style: const TextStyle(fontWeight: FontWeight.bold)),
        for (var i = 0; i < lesson.answers.length; i++)
          RadioListTile<int>(title: Text(lesson.answers[i]), value: i,
            groupValue: selection, onChanged: submitted ? null : (v) => setState(() => selection = v)),
        FilledButton(onPressed: selection == null || submitted ? null : () {
          setState(() => submitted = true);
          if (selection == lesson.correct) widget.onPassed(100);
        }, child: const Text('بررسی پاسخ')),
        if (submitted) ...[
          const SizedBox(height: 12),
          Text(selection == lesson.correct ? '✓ پاسخ صحیح؛ درس تکمیل شد.' : '✕ پاسخ اشتباه است.',
            style: TextStyle(fontWeight: FontWeight.bold,
              color: selection == lesson.correct ? Colors.green : Colors.red)),
          Text(lesson.explanation),
          if (selection != lesson.correct) TextButton(onPressed: () => setState(() {
            submitted = false; selection = null;
          }), child: const Text('تلاش دوباره')),
        ],
      ]),
    );
  }
}
