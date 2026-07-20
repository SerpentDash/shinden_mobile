# Awesome Notifications needs these under R8 full mode
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.google.common.reflect.TypeToken { *; }
-keep class * extends com.google.common.reflect.TypeToken

# Optional / deferred components referenced by Flutter embedding
-dontwarn com.google.j2objc.annotations.RetainedWith
