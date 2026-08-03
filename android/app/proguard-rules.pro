# Flutter/Dart and drift codegen require these keep rules under R8 minification
# (R1-6). Add plugin/JNI/reflection keep rules here as needed.

# Keep Flutter engine entry points.
-keep class io.flutter.plugin.editing.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Drift generates generated columns / companions accessed via reflection.
-keep class **.*generated.* { *; }
-keep class **.DriftDatabase { *; }
-keep @com.google.gson.annotations.SerializedName class *

# kotlinx / reflection-based libraries
-keep class kotlin.Metadata { *; }
-dontwarn kotlinx.**

# Keep generic signatures (setAccessible / reflection used by plugins)
-keepattributes Signature,InnerClasses,EnclosingMethod
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations