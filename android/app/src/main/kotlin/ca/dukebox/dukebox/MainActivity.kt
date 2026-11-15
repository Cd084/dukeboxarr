package ca.dukebox.dukebox

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (audio_service) shares the Flutter engine with the
// background media service, so playback continues while the screen is locked.
class MainActivity : AudioServiceActivity()
