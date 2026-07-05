# Flutter / Agora / native plugin keep rules — prevents R8 from stripping
# classes referenced only via JNI or Flutter's method channels.

-keep class io.flutter.**  { *; }
-keep class io.agora.**   { *; }
-keep class io.iris.**    { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-dontwarn io.flutter.embedding.**
-dontwarn io.agora.**

# Google Play Core — Flutter references SplitCompatApplication but we don't
# use dynamic feature delivery, so we just tell R8 to ignore missing classes.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Flutter plugins
-keep class com.ryanheise.** { *; }
-keep class com.dexterous.** { *; }
-keep class com.tekartik.** { *; }
-keep class com.baseflow.** { *; }
-keep class com.tarkpeer.** { *; }
-dontwarn com.squareup.okhttp.**
-dontwarn org.conscrypt.**
