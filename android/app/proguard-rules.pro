# ==============================================================================
# ProGuard / R8 Rules for Smriti (Android Offline Personal Knowledge Base)
# ==============================================================================

# --- Flutter Engine & Embeddings ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-dontwarn io.flutter.view.AccessibilityBridge$**
-dontwarn com.google.android.play.core.**

# --- ObjectBox Native Vector Database ---
-keep class io.objectbox.** { *; }
-keep interface io.objectbox.** { *; }
-keepclassmembers class io.objectbox.** {
    native <methods>;
}
-keep class * implements io.objectbox.EntityInfo { *; }
-keepclassmembers class * {
    @io.objectbox.annotation.Id <fields>;
    @io.objectbox.annotation.Entity <fields>;
    @io.objectbox.annotation.HnswIndex <fields>;
    @io.objectbox.annotation.Property <fields>;
}
-dontwarn io.objectbox.**

# --- LiteRT / TensorFlow Lite AI Runtimes ---
-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }
-keepclassmembers class org.tensorflow.lite.** {
    native <methods>;
}
-dontwarn org.tensorflow.lite.**

# --- Syncfusion Flutter PDF ---
-keep class com.syncfusion.** { *; }
-dontwarn com.syncfusion.**

# --- Google ML Kit Text Recognition (OCR) ---
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**


# --- Preserve Enums & Line Numbers for Symbolication ---
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
