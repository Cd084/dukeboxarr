# Release builds shrink and rename code (R8). Some Flutter plugins (e.g.
# shared_preferences, path_provider) call their Android code through JNI,
# which R8 can't see, so it renamed methods and the app crashed at start-up
# ("NoSuchMethodError: SharedPreferencesApiRegistrar.getAll"). Keep them.
-keep class io.flutter.plugins.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.alexmercerind.** { *; }

# JNI looks methods and classes up by name, including Kotlin types used in
# their signatures (R8 renamed kotlin.coroutines.Continuation to "n4", then
# dropped kotlin.Result$Failure). Keep the Kotlin standard library intact.
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# audio_service (media playback service, lock-screen controls).
-keep class com.ryanheise.** { *; }
