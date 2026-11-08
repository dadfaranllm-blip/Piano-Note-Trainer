import 'package:flutter_test/flutter_test.dart';
import 'package:piano_note_trainer/main.dart';

void main() {
  test('songs have one duration per note', () {
    for (final song in practiceSongs) {
      expect(song.beats.length, song.notes.length);
      expect(song.beats.every((beats) => beats > 0), true);
    }
  });
  test('half notes are included in song exercises', () {
    expect(practiceSongs.any((s) => s.beats.contains(2)), true);
  });
  test('theory chapter IDs and answer indices are valid', () {
    expect(theoryLessons.length, 8);
    expect(theoryLessons.map((l) => l.id).toSet().length, theoryLessons.length);
    for (final lesson in theoryLessons) {
      expect(lesson.content.length, greaterThan(40));
      expect(lesson.correct, inInclusiveRange(0, lesson.answers.length - 1));
    }
  });
}
