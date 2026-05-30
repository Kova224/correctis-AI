# Règles ProGuard pour le build release de Correctis.

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# image_picker
-keep class androidx.lifecycle.** { *; }

# Conserve les annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions

# OkHttp / réseau (Supabase utilise des appels HTTP)
-dontwarn okhttp3.**
-dontwarn okio.**

# Évite de supprimer les classes utilisées par réflexion
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}
-keep @androidx.annotation.Keep class * { *; }
