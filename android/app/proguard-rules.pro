# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }

# android_alarm_manager_plus
-keep class io.flutter.plugins.androidalarmmanager.** { *; }
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }

# flutter_local_notifications
-keep class com.dexterous.** { *; }

# home_widget
-keep class es.antonborri.home_widget.** { *; }

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# App widget provider
-keep class com.easistent.mealpicker.MealWidgetProvider { *; }

# Play Store deferred components (not used, suppress R8 warnings)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Keep annotations
-keepattributes *Annotation*

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
