# Added to the release build by the Flutter Gradle plugin, after its own
# rules, whenever this file exists.

# ML Kit names its building blocks in the manifest
# (com.google.firebase.components:...) and creates each one by reflection
# through its no-argument constructor. R8 can't see that use and drops the
# constructors, and text recognition then fails to start on the phone with
# no error anywhere else (see TextReader.java).
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}
