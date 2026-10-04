# Capacitor 8.4.1 exports consumerProguardFiles covering plugin classes,
# @PluginMethod and permission/activity callbacks. Do not duplicate those rules
# or retain com.getcapacitor.**, all plugins, or the whole app here.
# The optimized Android defaults retain @JavascriptInterface entry points.
# Preserve native source locations for retrace with the exact mapping.txt.
-keepattributes SourceFile,LineNumberTable

# No -dontoptimize, -dontshrink, -dontobfuscate or blanket -dontwarn.
# Add narrowly scoped rules only for a demonstrated reflection failure.
