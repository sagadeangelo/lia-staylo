# Flutter / Kotlin / coroutines
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# OkHttp/Okio (si alguna lib las usa)
-dontwarn okhttp3.**
-dontwarn okio.**

# Gson/Moshi (si usas)
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
-keep class com.squareup.moshi.** { *; }
-dontwarn com.squareup.moshi.**

# file_selector / Activity Result API (seguro)
-keep class androidx.activity.result.** { *; }
-keep class androidx.core.** { *; }

# (Añade reglas de otras libs si Play te reporta warnings específicos)
