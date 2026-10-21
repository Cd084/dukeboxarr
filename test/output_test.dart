import 'package:dukebox/output.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the music timeline from a player XML reply', () {
    const xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<MediaContainer commandID="7" location="fullScreenMusic">'
        '<Timeline type="video" state="stopped" />'
        '<Timeline type="music" state="playing" time="15230" duration="242000" ratingKey="12345" key="/library/metadata/12345" />'
        '<Timeline type="photo" state="stopped" />'
        '</MediaContainer>';
    final t = PlexRemoteOutput.musicTimeline(xml)!;
    expect(t['state'], 'playing');
    expect(t['time'], '15230');
    expect(t['duration'], '242000');
    expect(t['ratingKey'], '12345');
  });

  test('reads the music timeline from a JSON reply', () {
    const json = '{"MediaContainer":{"Timeline":[{"type":"music","state":"stopped","time":0}]}}';
    expect(PlexRemoteOutput.musicTimeline(json)!['state'], 'stopped');
  });

  test('no music timeline -> null', () {
    expect(PlexRemoteOutput.musicTimeline('<MediaContainer><Timeline type="video" state="playing"/></MediaContainer>'), isNull);
  });
}
