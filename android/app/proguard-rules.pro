# Capacitor 8.4.1 exports consumerProguardFiles covering plugin classes,
# @PluginMethod and permission/activity callbacks. Do not duplicate those rules
# or retain com.getcapacitor.**, all plugins, or the whole app here.
# The optimized Android defaults retain @JavascriptInterface entry points.
# Preserve native source locations for retrace with the exact mapping.txt.
-keepattributes SourceFile,LineNumberTable

# Capacitor reads nested permission annotations at runtime. Optimized Android
# run 37296899799 crashed in getPermissionStates/checkPermissions after signup.
# Keep these two annotation contracts, not the bridge or all plugin code.
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault
-keep @interface com.getcapacitor.annotation.CapacitorPlugin { *; }
-keep @interface com.getcapacitor.annotation.Permission { *; }

# No -dontoptimize, -dontshrink, -dontobfuscate or blanket -dontwarn.
# Add narrowly scoped rules only for a demonstrated reflection failure.
