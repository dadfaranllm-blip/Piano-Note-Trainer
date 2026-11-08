import 'package:flutter_test/flutter_test.dart';
import 'package:piano_note_trainer/main.dart';

void main() {
  test('Natural notes map to correct MIDI numbers and labels', () {
    final c3 = allNotes.firstWhere((n) => n.latin == 'C3');
    final c4 = allNotes.firstWhere((n) => n.latin == 'C4');
    final f5 = allNotes.firstWhere((n) => n.latin == 'F5');
    expect(c3.midi, 48);
    expect(c4.midi, 60);
    expect(c4.label(NoteNames.persian), 'دو4');
    expect(c4.label(NoteNames.english), 'C4');
    expect(c4.label(NoteNames.both), 'دو (C4)');
    expect(f5.midi, 77);
  });

  test('Treble clef E4 bottom line, F5 top line and C4 ledger', () {
    MusicNote n(String label) => allNotes.firstWhere((e) => e.latin == label);
    expect(staffPosition(n('E4'), Clef.treble), 0);
    expect(staffPosition(n('G4'), Clef.treble), 2);
    expect(staffPosition(n('B4'), Clef.treble), 4);
    expect(staffPosition(n('D5'), Clef.treble), 6);
    expect(staffPosition(n('F5'), Clef.treble), 8);
    expect(staffPosition(n('C4'), Clef.treble), -2);
    expect(staffPosition(n('C6'), Clef.treble), 12);
  });

  test('Bass clef G2 bottom line, A3 top line and C3 in second space', () {
    MusicNote n(String label) => allNotes.firstWhere((e) => e.latin == label);
    expect(staffPosition(n('C3'), Clef.bass), 3);
    expect(staffPosition(n('A3'), Clef.bass), 8);
    expect(staffPosition(n('C4'), Clef.bass), 10);
  });

  test('Songs have valid notes and unique IDs', () {
    expect(practiceSongs.length, greaterThanOrEqualTo(3));
    expect(practiceSongs.map((s) => s.id).toSet().length, practiceSongs.length);
    for (final song in practiceSongs) {
      expect(song.notes.length, song.pitchNames.length);
      expect(song.notes.every((n) => n.midi >= 60 && n.midi <= 84), true);
    }
  });

  test('Bass clef position uses G2 on bottom and A3 on top', () {
    final g2 = allNotes.firstWhere((n) => n.latin == 'G2');
    final a3 = allNotes.firstWhere((n) => n.latin == 'A3');
    expect(staffPosition(g2, Clef.bass), 0);
    expect(staffPosition(a3, Clef.bass), 8);
  });

  test('Five speeds', () {
    expect(Pace.values.map((e) => e.seconds).toList(), [0, 12, 8, 5, 3]);
  });

  test('Tempo multiplier changes song speed within safe bounds', () {
    expect(effectiveTempo(80, 50), 40);
    expect(effectiveTempo(120, 150), 180);
    expect(effectiveTempo(40, 25), 20);
    expect(effectiveTempo(160, 200), 320);
  });

  test('Middle C octave is the default practice range and octave selection is independent', () {
    final middle = notesForSelection({4}, {...noteLetters});
    expect(middle.length, 7);
    expect(middle.first.latin, 'C4');
    expect(middle.last.latin, 'B4');
    final selected = notesForSelection({3, 5}, {'C', 'G'});
    expect(selected.map((n) => n.latin).toSet(), {'C3', 'G3', 'C5', 'G5'});
  });
}
