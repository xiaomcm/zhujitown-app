# WordPress REST 数据模型（Gson 反射）
-keep class com.zhujitown.app.data.Models** { *; }
-keep class com.zhujitown.app.data.** { *; }

# Retrofit / OkHttp
-dontwarn okhttp3.**
-dontwarn retrofit2.**
-keepattributes Signature
-keepattributes *Annotation*
