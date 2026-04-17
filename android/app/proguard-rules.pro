# ─────────────────────────────────────────────────────────────
#  Keep attributes (required for Gson TypeToken, reflection, enums)
# ─────────────────────────────────────────────────────────────
# Signature         — generic type information (TypeToken<T> etc.)
# InnerClasses      — nested class relationships
# EnclosingMethod   — reflected method captures
# *Annotation*      — runtime annotations (@SerializedName, @Keep, ...)
# SourceFile,LineNumberTable — readable stack traces in crash reports
-keepattributes Signature,InnerClasses,EnclosingMethod,*Annotation*
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ─────────────────────────────────────────────────────────────
#  Flutter
# ─────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# @pragma('vm:entry-point') callbacks (our alarm callbacks)
-keep class * {
    @io.flutter.plugin.common.PluginRegistry$Registrar *;
}

# ─────────────────────────────────────────────────────────────
#  android_alarm_manager_plus
#  Receivers and services are referenced from AndroidManifest —
#  must keep exact class names.
# ─────────────────────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }
-keep class dev.fluttercommunity.plus.androidalarmmanager.AlarmService { *; }
-keep class dev.fluttercommunity.plus.androidalarmmanager.AlarmBroadcastReceiver { *; }
-keep class dev.fluttercommunity.plus.androidalarmmanager.RebootBroadcastReceiver { *; }
-keep class dev.fluttercommunity.plus.androidalarmmanager.AndroidAlarmManagerPlugin { *; }
# Legacy package path (older plugin versions)
-keep class io.flutter.plugins.androidalarmmanager.** { *; }

# ─────────────────────────────────────────────────────────────
#  flutter_local_notifications
#  Uses Gson to (de)serialize scheduled notification state —
#  needs both plugin classes AND Gson keep rules.
# ─────────────────────────────────────────────────────────────
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver { *; }
-keep class com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver { *; }
-keep class com.dexterous.flutterlocalnotifications.ForegroundService { *; }

# ─────────────────────────────────────────────────────────────
#  Gson  (canonical ruleset from google/gson android-proguard-example)
# ─────────────────────────────────────────────────────────────
-dontwarn sun.misc.**

# Keep all Gson classes so TypeAdapters, JsonSerializers, etc. resolve
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Prevent R8 from leaving @SerializedName fields as null
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Retain TypeToken generics (R8 3.0+ strips these without explicit rules)
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# ─────────────────────────────────────────────────────────────
#  @Keep annotated classes and members (androidx + legacy support)
# ─────────────────────────────────────────────────────────────
-keep,allowobfuscation,allowshrinking @interface androidx.annotation.Keep
-keep,allowobfuscation,allowshrinking @interface android.support.annotation.Keep

-keep @androidx.annotation.Keep class * { *; }
-keep @android.support.annotation.Keep class * { *; }

-keepclasseswithmembers class * {
    @androidx.annotation.Keep <methods>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <fields>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <init>(...);
}

# ─────────────────────────────────────────────────────────────
#  Other Flutter plugins used by this app
# ─────────────────────────────────────────────────────────────
-keep class es.antonborri.home_widget.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# ─────────────────────────────────────────────────────────────
#  App-owned components referenced from AndroidManifest.xml
# ─────────────────────────────────────────────────────────────
-keep class com.easistent.mealpicker.MealWidgetProvider { *; }
-keep class com.easistent.mealpicker.MainActivity { *; }

# ─────────────────────────────────────────────────────────────
#  Play Store deferred components (not used) — silence R8 warnings
# ─────────────────────────────────────────────────────────────
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ─────────────────────────────────────────────────────────────
#  Standard keep rules
# ─────────────────────────────────────────────────────────────
# Native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Enum values() and valueOf() — keep for JSON / reflection
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Parcelable CREATOR fields
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}
